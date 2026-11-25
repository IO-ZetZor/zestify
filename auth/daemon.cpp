#include "config.hpp"
#include "pam_session.hpp"
#include "users.hpp"

#include <QJsonArray>
#include <QFile>
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <grp.h>
#include <linux/vt.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <systemd/sd-bus.h>
#include <unistd.h>

using namespace zestify;
namespace {
constexpr const char* SocketPath = "/run/zestify-dm/control.sock";
void stopSignal(int) { stopping = 1; }
void installSignals() {
    struct sigaction action{};
    action.sa_handler = stopSignal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);
    signal(SIGPIPE, SIG_IGN);
}
void parentDeath(pid_t expected) {
    stopping = 0;
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || getppid() != expected) _exit(1);
}
struct Account {
    std::string name, home, shell;
    uid_t uid;
    gid_t gid;
};
Account lookup(const QString& name) {
    if (name.isEmpty() || name.size() > 256 || name.contains(QChar::Null)) throw Error("Invalid account");
    const QByteArray bytes = name.toUtf8();
    // NSS storage is copied before another lookup can overwrite it.
    passwd* entry = getpwnam(bytes.constData());
    if (!entry) throw Error("Account does not exist");
    return {entry->pw_name, entry->pw_dir, entry->pw_shell, entry->pw_uid, entry->pw_gid};
}
int waitChild(pid_t child) {
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
void terminate(pid_t& child, bool group = false) {
    if (child <= 0) return;
    const pid_t target = group ? -child : child;
    kill(target, SIGTERM);
    // Supervisors must outlive the child's five-second grace period and the
    // bounded logind teardown, so they can close their PAM session themselves.
    const int attempts = group ? 50 : 150;
    for (int i = 0; i < attempts; ++i) {
        int status;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child || (result < 0 && errno == ECHILD)) {
            // Kill descendants still in the child's process group after its
            // leader has exited (for example compositor helper processes).
            if (group) kill(target, SIGKILL);
            child = -1;
            return;
        }
        poll(nullptr, 0, 100);
    }
    kill(target, SIGKILL);
    waitChild(child);
    child = -1;
}
void terminateLogind(const QStringList& environment) {
    QString id;
    for (const auto& value : environment)
        if (value.startsWith("XDG_SESSION_ID=")) id = value.mid(15);
    if (id.isEmpty()) return;
    sd_bus* bus = nullptr;
    if (sd_bus_open_system(&bus) < 0) return;
    sd_bus_set_method_call_timeout(bus, 3000000);
    const QByteArray bytes = id.toUtf8();
    // The session supervisor is part of this scope too. Ignore TERM during
    // orderly logind teardown so PAM close_session still runs.
    sd_bus_call_method(bus, "org.freedesktop.login1", "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager", "TerminateSession", nullptr, nullptr, "s", bytes.constData());
    sd_bus_unref(bus);
}
Fd attachTerminal(int vt) {
    if (setsid() < 0) throw Error("Cannot create session leader");
    const QByteArray name = "/dev/tty" + QByteArray::number(vt);
    Fd tty(open(name.constData(), O_RDWR | O_NOCTTY | O_CLOEXEC));
    if (tty.get() < 0 || ioctl(tty.get(), TIOCSCTTY, 0) < 0) throw Error("Cannot acquire login terminal");
    if (ioctl(tty.get(), VT_ACTIVATE, vt) < 0 || ioctl(tty.get(), VT_WAITACTIVE, vt) < 0)
        throw Error("Cannot activate login terminal");
    return tty;
}
void prepareEnvironment(const Account& account, const QStringList& environment, const QString& desktop, bool greeter) {
    if (clearenv() != 0) throw Error("Cannot clear session environment");
    for (const auto& value : environment) {
        const qsizetype split = value.indexOf('=');
        if (split <= 0) continue;
        QByteArray key = value.left(split).toUtf8();
        QByteArray data = value.mid(split + 1).toUtf8();
        if (setenv(key.constData(), data.constData(), 1) < 0) throw Error("Cannot set PAM environment");
    }
    const char* runtime = getenv("XDG_RUNTIME_DIR");
    struct stat info{};
    if (!runtime || lstat(runtime, &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != account.uid || (info.st_mode & 0077))
        throw Error("PAM/logind did not provide a private runtime directory");
    const std::pair<const char*, std::string> values[] = {
        {"HOME", account.home}, {"USER", account.name}, {"LOGNAME", account.name}, {"SHELL", account.shell},
        {"PATH", "/usr/local/bin:/usr/bin:/bin"}, {"LANG", "C.UTF-8"}, {"TERM", "linux"},
        {"XDG_SESSION_TYPE", "wayland"}, {"XDG_SESSION_CLASS", greeter ? "greeter" : "user"},
        {"XDG_CURRENT_DESKTOP", desktop.toStdString()}, {"XDG_SESSION_DESKTOP", desktop.toStdString()}
    };
    for (const auto& value : values)
        if (setenv(value.first, value.second.c_str(), 1) < 0) throw Error("Cannot initialize session environment");
    if (greeter && setenv("ZESTIFY_DM_SOCKET", SocketPath, 1) < 0) throw Error("Cannot set greeter socket");
    unsetenv("DISPLAY");
    unsetenv("WAYLAND_DISPLAY");
    unsetenv("DBUS_SESSION_BUS_ADDRESS");
}
int runProgram(const Account& account, const QStringList& command, int tty, PamSession& pam, const QString& desktop, bool greeter,
    Channel* control = nullptr) {
    QStringList environment = pam.environment();
    int pipeFds[2];
    if (pipe2(pipeFds, O_CLOEXEC) < 0) throw Error("Cannot create exec status pipe");
    Fd reader(pipeFds[0]), writer(pipeFds[1]);
    const pid_t parent = getpid();
    pid_t child = fork();
    if (child < 0) throw Error("Cannot start session process");
    if (child == 0) {
        parentDeath(parent);
        // TERM must kill the unprivileged process, not merely set the
        // supervisor's stopping flag inherited at fork.
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        reader = Fd();
        try {
            if (setpgid(0, 0) < 0) throw Error("Cannot create process group");
            if (initgroups(account.name.c_str(), account.gid) < 0 || setgid(account.gid) < 0 || setuid(account.uid) < 0)
                throw Error("Cannot drop session privileges");
            // setuid clears PDEATHSIG on Linux.
            if (prctl(PR_SET_PDEATHSIG, SIGTERM) < 0 || getppid() != parent) throw Error("Session supervisor exited");
            prepareEnvironment(account, environment, desktop, greeter);
            if (chdir(account.home.c_str()) < 0) throw Error("Cannot enter account home");
            for (int fd = 0; fd < 3; ++fd) if (dup2(tty, fd) < 0) throw Error("Cannot connect terminal streams");
            std::vector<QByteArray> storage;
            for (const auto& arg : command) storage.push_back(arg.toUtf8());
            std::vector<char*> args;
            for (auto& arg : storage) args.push_back(arg.data());
            args.push_back(nullptr);
            execv(args[0], args.data());
        } catch (...) { /* Parent receives a generic setup failure. */ }
        const char failed = 1;
        ssize_t ignored = write(writer.get(), &failed, 1);
        (void)ignored;
        _exit(127);
    }
    writer = Fd();
    setpgid(child, child);
    // Ignore SIGTTOU while making the session child the foreground group.
    struct sigaction previous{}, ignored{};
    ignored.sa_handler = SIG_IGN;
    sigemptyset(&ignored.sa_mask);
    sigaction(SIGTTOU, &ignored, &previous);
    const int foreground = ioctl(tty, TIOCSPGRP, &child);
    sigaction(SIGTTOU, &previous, nullptr);
    if (foreground < 0) { terminate(child, true); throw Error("Cannot set foreground process group"); }
    pollfd statusPipe{reader.get(), POLLIN | POLLHUP, 0};
    int ready;
    do { ready = poll(&statusPipe, 1, 10000); } while (ready < 0 && errno == EINTR && !stopping);
    char failed = 0;
    if (ready <= 0 || read(reader.get(), &failed, 1) != 0) {
        terminate(child, true);
        terminateLogind(environment);
        throw Error("Session executable failed to start");
    }
    try {
        if (control) control->send({{"type", "started"}});
    } catch (...) { terminate(child, true); terminateLogind(environment); throw; }
    int status = 0;
    while (!stopping) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) {
            kill(-child, SIGTERM);
            terminateLogind(environment);
            return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
        }
        if (result < 0 && errno != EINTR) break;
        poll(nullptr, 0, 100);
    }
    terminate(child, true);
    terminateLogind(environment);
    return 1;
}
pid_t startGreeter(const Config& config, const Account& account, int listener) {
    const pid_t parent = getpid();
    pid_t child = fork();
    if (child < 0) throw Error("Cannot start greeter supervisor");
    if (child == 0) {
        parentDeath(parent);
        close(listener);
        int status = 1;
        try {
            Fd tty = attachTerminal(config.vt);
            PamSession pam("zestify-greeter", QString::fromStdString(account.name), config.vt, nullptr, true);
            pam.open();
            status = runProgram(account, config.greeterCommand, tty.get(), pam, "Zestify", true);
        } catch (const std::exception& error) { fprintf(stderr, "zestify-dm: greeter: %s\n", error.what()); }
        _exit(status);
    }
    return child;
}
void worker(const Config& config, const Account& greeter, int clientFd, int controlFd) {
    Channel client(clientFd), control(controlFd);
    try {
        QJsonObject hello{{"type", "hello"}, {"version", 1}, {"sessions", config.publicSessions()}, {"users", QJsonArray{}}};
        QJsonArray accounts;
        for (const auto& user : localUsers(config.greeterUser)) {
            auto candidate = accounts; candidate.append(user);
            hello["users"] = candidate;
            try { encode(hello); accounts = candidate; }
            catch (const Error&) { break; }
        }
        hello["users"] = accounts;
        client.send(hello);
        const QJsonObject request = client.receive();
        if (request.value("type") != "login" || !request.value("user").isString() || !request.value("session").isString())
            throw Error("Invalid login request");
        const Session& session = config.session(request.value("session").toString());
        PamSession pam("zestify-dm", request.value("user").toString(), config.vt, &client);
        pam.authenticate();
        Account account = lookup(pam.user());
        if (account.uid == 0 || account.uid == greeter.uid) throw Error("This account cannot log in here");
        client.send({{"type", "authenticated"}});
        control.send({{"type", "authenticated"}});
        if (control.receive().value("type") != "handoff") throw Error("Session handoff denied");
        pam.detachClient();
        Fd tty = attachTerminal(config.vt);
        pam.open();
        runProgram(account, session.command, tty.get(), pam, session.desktop, false, &control);
    } catch (const std::exception& error) {
        fprintf(stderr, "zestify-dm: login: %s\n", error.what());
        try { client.send({{"type", "error"}, {"message", "Unable to sign in. Check your credentials and try again."}}); } catch (...) {}
        try { control.send({{"type", "error"}}); } catch (...) {}
    }
}
Fd listenSocket(const Account& greeter) {
    struct stat directory{};
    if (lstat("/run/zestify-dm", &directory) < 0 || !S_ISDIR(directory.st_mode) || directory.st_uid != 0 || (directory.st_mode & 0022))
        throw Error("/run/zestify-dm must be a root-owned service runtime directory");
    if (chown("/run/zestify-dm", 0, greeter.gid) < 0 || chmod("/run/zestify-dm", 0750) < 0) throw Error("Cannot secure runtime directory");
    struct stat existing{};
    if (lstat(SocketPath, &existing) == 0) {
        if (!S_ISSOCK(existing.st_mode) || existing.st_uid != 0) throw Error("Unexpected control socket file");
        if (unlink(SocketPath) < 0) throw Error("Cannot remove stale socket");
    } else if (errno != ENOENT) throw Error("Cannot inspect control socket");
    Fd socket(::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0));
    if (socket.get() < 0) throw Error("Cannot create control socket");
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::strcpy(address.sun_path, SocketPath);
    if (bind(socket.get(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) < 0
        || chown(SocketPath, 0, greeter.gid) < 0 || chmod(SocketPath, 0660) < 0 || listen(socket.get(), 4) < 0)
        throw Error("Cannot publish control socket");
    return socket;
}
void serve(const Config& config) {
    const Account greeter = lookup(config.greeterUser);
    if (greeter.uid == 0) throw Error("The greeter must be unprivileged");
    for (const auto& command : {config.greeterCommand})
        if (access(QFile::encodeName(command.first()).constData(), X_OK) < 0) throw Error("Greeter compositor is not installed");
    for (const auto& session : config.sessions)
        if (access(QFile::encodeName(session.command.first()).constData(), X_OK) < 0) throw Error("Session executable is not installed");
    Fd listener = listenSocket(greeter);
    pid_t greeterPid = -1, workerPid = -1;
    try {
        greeterPid = startGreeter(config, greeter, listener.get());
        int crashes = 0;
        while (!stopping) {
            int status;
            if (waitpid(greeterPid, &status, WNOHANG) == greeterPid) {
                greeterPid = -1;
                if (++crashes >= 3) throw Error("Greeter repeatedly exited; inspect PAM/compositor logs");
                poll(nullptr, 0, 1000);
                if (stopping) break;
                greeterPid = startGreeter(config, greeter, listener.get());
            }
            pollfd incoming{listener.get(), POLLIN, 0};
            if (poll(&incoming, 1, 250) <= 0) continue;
            Fd client(accept4(listener.get(), nullptr, nullptr, SOCK_CLOEXEC));
            if (client.get() < 0) continue;
            ucred peer{};
            socklen_t length = sizeof(peer);
            if (getsockopt(client.get(), SOL_SOCKET, SO_PEERCRED, &peer, &length) < 0 || peer.uid != greeter.uid) continue;
            int pair[2];
            if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, pair) < 0) throw Error("Cannot create supervisor channel");
            Fd parentEnd(pair[0]), workerEnd(pair[1]);
            const pid_t parent = getpid();
            workerPid = fork();
            if (workerPid < 0) throw Error("Cannot create authentication worker");
            if (workerPid == 0) {
                parentDeath(parent);
                listener = Fd();
                parentEnd = Fd();
                worker(config, greeter, client.get(), workerEnd.get());
                _exit(0);
            }
            workerEnd = Fd();
            client = Fd();
            Channel control(parentEnd.get(), 5000);
            bool handoff = false, started = false;
            const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(180);
            while (!stopping) {
                if (waitpid(workerPid, &status, WNOHANG) == workerPid) { workerPid = -1; break; }
                if (!started && std::chrono::steady_clock::now() >= deadline) break;
                pollfd event{parentEnd.get(), POLLIN, 0};
                if (poll(&event, 1, 250) <= 0) continue;
                if (event.revents & POLLIN) {
                    try {
                        const QString type = control.receive().value("type").toString();
                        if (type == "authenticated" && !handoff) {
                            handoff = true;
                            terminate(greeterPid);
                            control.send({{"type", "handoff"}});
                        } else if (type == "started" && handoff) started = true;
                        else if (type == "error") break;
                        else throw Error("Unexpected worker event");
                    } catch (const Error&) { break; }
                } else if (event.revents & (POLLHUP | POLLERR)) break;
            }
            terminate(workerPid);
            if (handoff && !stopping) {
                crashes = 0;
                greeterPid = startGreeter(config, greeter, listener.get());
            } else if (!stopping) poll(nullptr, 0, 1000);
        }
    } catch (...) {
        terminate(workerPid);
        terminate(greeterPid);
        unlink(SocketPath);
        throw;
    }
    terminate(workerPid);
    terminate(greeterPid);
    unlink(SocketPath);
}
} // namespace

int main(int argc, char** argv) {
    installSignals();
    bool check = false;
    QString path = QStringLiteral("/etc/zestify-dm/config.json");
    if (argc == 3 && std::strcmp(argv[1], "--check-config") == 0) { check = true; path = QString::fromLocal8Bit(argv[2]); }
    else if (argc == 3 && std::strcmp(argv[1], "--config") == 0) path = QString::fromLocal8Bit(argv[2]);
    else if (argc != 1) {
        fprintf(stderr, "usage: zestify-dm [--config FILE | --check-config FILE]\n");
        return 2;
    }
    try {
        if (!check && geteuid() != 0) throw Error("The display manager must run as root through systemd");
        const Config config = Config::load(path, !check);
        if (check) { puts("Configuration syntax is valid (runtime dependencies were not checked)."); return 0; }
        umask(0077);
        serve(config);
        return 0;
    } catch (const std::exception& error) {
        fprintf(stderr, "zestify-dm: %s\n", error.what());
        return 1;
    }
}
