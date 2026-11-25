#include "config.hpp"
#include "pam_session.hpp"
#include "users.hpp"
#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <chrono>
#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

using namespace zestify;
namespace {
void require(bool condition, const char* detail) { if (!condition) throw Error(detail); }
void rejects(const std::function<void()>& action, const char* detail) {
    bool rejected = false;
    try { action(); } catch (const Error&) { rejected = true; }
    require(rejected, detail);
}
struct Pair {
    Fd left, right;
    Pair() {
        int pair[2];
        require(socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, pair) == 0, "socketpair failed");
        left = Fd(pair[0]); right = Fd(pair[1]);
    }
};
struct Child {
    pid_t pid = -1;
    ~Child() { if (pid > 0) { kill(pid, SIGKILL); waitpid(pid, nullptr, 0); } }
    void passed() {
        int status = 0;
        require(waitpid(pid, &status, 0) == pid, "waitpid failed");
        pid = -1;
        require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "conversation client failed");
    }
};
void writeBytes(int fd, const QByteArray& bytes) {
    qsizetype offset = 0;
    while (offset < bytes.size()) {
        const ssize_t count = send(fd, bytes.constData() + offset, static_cast<size_t>(bytes.size() - offset), MSG_NOSIGNAL);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) throw Error(std::string("test socket write failed: ") + std::strerror(errno));
        offset += count;
    }
}
void protocolTests() {
    {
        Pair pair;
        const QJsonObject first{{"type", "response"}, {"value", "first"}};
        const QJsonObject second{{"type", "response"}, {"value", "second"}};
        writeBytes(pair.right.get(), encode(first) + encode(second));
        require(Channel(pair.left.get(), 1000).receive() == first, "first coalesced packet lost");
        require(Channel(pair.left.get(), 1000).receive() == second, "new Channel lost second packet");
    }
    {
        Pair pair;
        Child child;
        child.pid = fork();
        require(child.pid >= 0, "fork failed");
        if (child.pid == 0) {
            pair.left = Fd();
            try {
                for (const auto& part : {QByteArray("{\"type\":"), QByteArray("\"response\",\"value\":\"a"), QByteArray("b\"}\n")}) {
                    writeBytes(pair.right.get(), part); usleep(10000);
                }
                _exit(0);
            } catch (...) { _exit(1); }
        }
        pair.right = Fd();
        require(Channel(pair.left.get(), 1000).receive().value("value") == "ab", "fragmented packet corrupt");
        child.passed();
        rejects([&] { Channel(pair.left.get(), 100).receive(); }, "EOF accepted");
    }
    {
        Pair pair;
        const qsizetype overhead = QJsonDocument(QJsonObject{{"value", ""}}).toJson(QJsonDocument::Compact).size();
        const QJsonObject maximum{{"value", QString(MaxPacket - overhead, 'x')}};
        require(encode(maximum).size() == MaxPacket + 1, "test packet boundary wrong");
        writeBytes(pair.right.get(), encode(maximum));
        require(Channel(pair.left.get(), 1000).receive() == maximum, "maximum packet rejected");
        rejects([&] { encode({{"value", QString(MaxPacket - overhead + 1, 'x')}}); }, "oversize encode accepted");
        writeBytes(pair.right.get(), QByteArray(MaxPacket + 1, 'x'));
        rejects([&] { Channel(pair.left.get(), 1000).receive(); }, "oversize receive accepted");
    }
    {
        Pair pair;
        writeBytes(pair.right.get(), "{\"unfinished\":");
        const auto start = std::chrono::steady_clock::now();
        rejects([&] { Channel(pair.left.get(), 40).receive(); }, "partial packet did not time out");
        require(std::chrono::steady_clock::now() - start < std::chrono::seconds(1), "timeout exceeded deadline");
    }
    rejects([] { decode("[]"); }, "nonobject JSON accepted");
    rejects([] { decode("{invalid}"); }, "malformed JSON accepted");
    {
        Pair pair;
        pair.right = Fd();
        rejects([&] { Channel(pair.left.get(), 100).send({{"type", "test"}}); }, "send to closed peer succeeded");
    }
}
QJsonObject validConfig() {
    return {{"greeterUser", "zestify-greeter"}, {"greeterCommand", QJsonArray{"/bin/true"}}, {"vt", 7},
        {"sessions", QJsonArray{QJsonObject{{"id", "hyprland"}, {"name", "Hyprland"}, {"desktop", "Hyprland"}, {"command", QJsonArray{"/bin/true", ""}}}}}};
}
QByteArray json(const QJsonObject& object) { return QJsonDocument(object).toJson(QJsonDocument::Compact); }
void configTests() {
    const Config config = Config::parse(json(validConfig()));
    require(config.vt == 7 && config.session("hyprland").command.size() == 2, "valid configuration corrupt");
    require(config.publicSessions().first().toObject().size() == 2, "private command disclosed");
    rejects([&] { config.session("unknown"); }, "unknown session accepted");
    for (const QJsonValue& vt : {QJsonValue(0), QJsonValue(64), QJsonValue(1.5), QJsonValue("7")}) {
        auto object = validConfig(); object["vt"] = vt;
        rejects([&] { Config::parse(json(object)); }, "invalid VT accepted");
    }
    for (const QJsonValue& command : {QJsonValue("/bin/true"), QJsonValue(QJsonArray{}), QJsonValue(QJsonArray{"relative"}), QJsonValue(QJsonArray{"/bin/true", 3})}) {
        auto object = validConfig(); object["greeterCommand"] = command;
        rejects([&] { Config::parse(json(object)); }, "invalid command accepted");
    }
    {
        auto object = validConfig(); auto sessions = object["sessions"].toArray(); sessions.append(sessions.first()); object["sessions"] = sessions;
        rejects([&] { Config::parse(json(object)); }, "duplicate sessions accepted");
    }
    QTemporaryDir directory;
    require(directory.isValid(), "temporary config directory failed");
    const QString path = directory.filePath("config.json");
    QFile file(path);
    require(file.open(QIODevice::WriteOnly) && file.write(json(validConfig())) > 0, "write config failed"); file.close();
    require(Config::load(path, false).vt == 7, "config load failed");
    const QByteArray link = QFile::encodeName(directory.filePath("link.json"));
    const QByteArray target = QFile::encodeName(path);
    require(symlink(target.constData(), link.constData()) == 0, "symlink failed");
    rejects([&] { Config::load(QString::fromUtf8(link), false); }, "symlink config accepted");
    require(file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::WriteGroup), "set config permissions failed");
    rejects([&] { Config::load(path, true); }, "unsafe config ownership/mode accepted");
}
void userTests() {
    QTemporaryDir directory;
    require(directory.isValid(), "temporary account directory failed");
    const QString accounts = directory.filePath("passwd");
    const QString definitions = directory.filePath("login.defs");
    QFile file(accounts);
    require(file.open(QIODevice::WriteOnly), "cannot create account fixture");
    file.write("root:x:0:0:Root:/root:/bin/bash\n"
               "service:x:99:99:Service:/var/lib/service:/bin/bash\n"
               "zestify-greeter:x:1002:1002:Greeter:/var/lib/greeter:/bin/bash\n"
               "blocked:x:1003:1003:Blocked:/home/blocked:/usr/sbin/nologin\n"
               "false:x:1004:1004:False:/home/false:/bin/false\n"
               "no-shell:x:1005:1005:No shell:/home/no-shell:\n"
               "nobody:x:65534:65534:Nobody:/:/bin/bash\n"
               "zoe:x:1001:1001:Zoe,Room 1:/home/zoe:/bin/bash\n"
               "alice:x:1000:1000::/home/alice:/bin/zsh\n"
               "alice:x:1000:1000:Duplicate:/home/alice:/bin/zsh\n"
               "invalid:x:no-uid:1000:Invalid:/home/invalid:/bin/bash\n");
    file.close();
    const auto users = localUsers("zestify-greeter", accounts, definitions);
    require(users.size() == 2 && users[0].toObject().value("id") == "alice"
        && users[0].toObject().value("name") == "alice" && users[1].toObject().value("name") == "Zoe", "local user filtering/display names corrupt");
    require(users[0].toObject().size() == 2, "private account fields exposed");
    QFile defs(definitions); require(defs.open(QIODevice::WriteOnly), "cannot create UID policy fixture");
    defs.write("UID_MIN 1001\nUID_MAX 1001 # local range\n"); defs.close();
    require(localUsers("zestify-greeter", accounts, definitions).size() == 1, "UID policy not honored");
    require(file.open(QIODevice::Append), "cannot extend account fixture");
    for (int index = 0; index < 100; ++index) file.write(QString("user%1:x:%2:1000:Display name:/home/user:/bin/bash\n").arg(index).arg(1100 + index).toUtf8());
    file.close();
    require(localUsers("zestify-greeter", accounts, directory.filePath("missing")).size() <= 32, "account list exceeded protocol limit");
}
QStringList readEvents(const QString& path) {
    QFile file(path);
    require(file.open(QIODevice::ReadOnly), "PAM event log missing");
    return QString::fromUtf8(file.readAll()).split('\n', Qt::SkipEmptyParts);
}
void pamCase(const QString& module, const QString& option, bool success, const QString& password = "test-password") {
    QTemporaryDir directory;
    require(directory.isValid(), "temporary PAM directory failed");
    const QString eventsPath = directory.filePath("events");
    const QString policyPath = directory.filePath("zestify-test");
    const QByteArray policy = QString("auth required %1 log=%2 rewrite-user %3\naccount required %1 log=%2 %3\npassword required %1 log=%2\nsession required %1 log=%2 %3\n")
        .arg(module, eventsPath, option).toUtf8();
    QFile policyFile(policyPath);
    require(policyFile.open(QIODevice::WriteOnly) && policyFile.write(policy) == policy.size(), "write PAM policy failed"); policyFile.close();
    Pair pair;
    Child child;
    child.pid = fork();
    require(child.pid >= 0, "fork PAM client failed");
    if (child.pid == 0) {
        pair.left = Fd();
        try {
            Channel client(pair.right.get(), 2000);
            require(client.receive().value("type") == "info", "PAM info missing");
            require(client.receive().value("error").toBool(), "PAM error message missing");
            const auto prompt = client.receive();
            require(prompt.value("type") == "prompt" && !prompt.value("echo").toBool(), "password echo enabled");
            // Consecutive responses may arrive in one socket read. The server
            // must preserve the second response for the next PAM prompt.
            writeBytes(pair.right.get(), encode({{"type", "response"}, {"value", password}})
                + encode({{"type", "response"}, {"value", "123456"}}));
            const auto second = client.receive();
            require(second.value("type") == "prompt" && second.value("echo").toBool(), "echo-on prompt missing");
            _exit(0);
        } catch (...) { _exit(1); }
    }
    pair.right = Fd();
    bool completed = false;
    {
        Channel server(pair.left.get(), 2000);
        const QByteArray configDirectory = QFile::encodeName(directory.path());
        PamSession pam("zestify-test", "test-user", 7, &server, false, configDirectory.constData());
        try {
            pam.authenticate();
            require(pam.user() == "mapped-test-user", "PAM rewritten identity ignored");
            pam.open();
            require(pam.environment().contains("ZESTIFY_TEST_ENV=present"), "PAM session environment missing");
            completed = true;
        } catch (const Error&) { if (success) throw; }
    }
    child.passed();
    require(completed == success, "unexpected PAM authentication result");
    const QStringList events = readEvents(eventsPath);
    require(events.last() == "end", "pam_end cleanup did not run");
    if (success) {
        require(events.contains("session-close") && events.contains("credentials-delete"), "PAM resources not closed");
        require(events.indexOf("session-close") < events.indexOf("credentials-delete"), "PAM cleanup order wrong");
    } else if (option == "session-fail") {
        require(events.contains("credentials-delete") && !events.contains("session-close"), "partial session cleanup wrong");
    } else if (option == "credentials-fail") {
        require(!events.contains("session-open") && !events.contains("credentials-delete"), "failed credentials cleanup wrong");
    } else {
        require(!events.contains("session-open"), "authentication failure opened a session");
    }
    if (option == "expired") require(events.contains("password-change"), "expired password was not changed");
}
void missingClientTest(const QString& module) {
    QTemporaryDir directory;
    QFile policy(directory.filePath("zestify-test"));
    const QByteArray text = QString("auth required %1\naccount required %1\nsession required %1\n").arg(module).toUtf8();
    require(policy.open(QIODevice::WriteOnly) && policy.write(text) == text.size(), "write missing-client policy failed"); policy.close();
    const QByteArray path = QFile::encodeName(directory.path());
    PamSession pam("zestify-test", "test-user", 7, nullptr, false, path.constData());
    rejects([&] { pam.authenticate(); }, "password authentication without conversation succeeded");
}
}
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 2;
    signal(SIGPIPE, SIG_IGN);
    try {
        protocolTests(); configTests(); userTests();
        const QString module = QString::fromLocal8Bit(argv[1]);
        pamCase(module, "", true);
        pamCase(module, "expired", true);
        pamCase(module, "", false, "wrong-password");
        pamCase(module, "account-fail", false);
        pamCase(module, "credentials-fail", false);
        pamCase(module, "session-fail", false);
        missingClientTest(module);
        puts("AUTH PASS: protocol boundaries, configuration, PAM conversation and cleanup");
        return 0;
    } catch (const std::exception& error) {
        fprintf(stderr, "AUTH FAIL: %s\n", error.what());
        return 1;
    }
}
