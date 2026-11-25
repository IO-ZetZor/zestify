#include "greeter.hpp"
#include "users.hpp"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <set>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/socket.h>

using namespace zestify;
namespace {
bool responseFits(const QString& value) {
    if (value.size() > 4096 || value.contains(QChar::Null)) return false;
    QByteArray bytes = value.toUtf8();
    const bool fits = bytes.size() <= 4096;
    wipe(bytes);
    if (!fits) return false;
    try {
        bytes = encode({{"type", "response"}, {"value", value}});
        wipe(bytes);
        return true;
    } catch (const Error&) { return false; }
}
bool identifier(const QJsonValue& value) {
    return value.isString() && !value.toString().isEmpty() && value.toString().size() <= 256
        && !value.toString().contains(QChar::Null);
}
}
LoginClient::LoginClient(QString path, bool preview, uid_t expectedPeer, QString selectionPath)
    : socketPath_(std::move(path)), selectionPath_(std::move(selectionPath)), expectedPeer_(expectedPeer), preview_(preview) {
    if (selectionPath_.isEmpty()) selectionPath_ = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + "/zestify-dm/selection.json";
    loadSelection();
    reconnect_.setSingleShot(true);
    reconnect_.setInterval(1000);
    socket_.setReadBufferSize(MaxPacket + 1);
    connect(&reconnect_, &QTimer::timeout, this, &LoginClient::connectSocket);
    connect(&socket_, &QLocalSocket::connected, this, [this] {
        ucred peer{};
        socklen_t size = sizeof(peer);
        if (getsockopt(static_cast<int>(socket_.socketDescriptor()), SOL_SOCKET, SO_PEERCRED, &peer, &size) < 0 || peer.uid != expectedPeer_) {
            disconnectWith(QStringLiteral("The login service has an unexpected owner."), true);
        }
    });
    connect(&socket_, &QLocalSocket::readyRead, this, &LoginClient::readMessages);
    connect(&socket_, &QLocalSocket::disconnected, this, [this] {
        if (!handedOff_) disconnectWith(QStringLiteral("Connecting to the login service…"), false);
    });
    connect(&socket_, &QLocalSocket::errorOccurred, this, [this] {
        if (!handedOff_) disconnectWith(QStringLiteral("The login service is unavailable. Retrying…"), true);
    });
}
LoginClient::~LoginClient() {
    // QLocalSocket can emit disconnected while its destructor closes the
    // connection. Remove callbacks before later-declared state is destroyed.
    reconnect_.stop();
    disconnect(&socket_, nullptr, this, nullptr);
    socket_.abort();
    wipe(incoming_);
    wipe(pendingPassword_);
}
void LoginClient::start() {
    if (preview_) {
        auto users = localUsers(QStringLiteral("zestify-greeter"));
        if (users.isEmpty()) users.append(QJsonObject{{"id", "preview-user"}, {"name", "Preview user"}});
        handle({{"type", "hello"}, {"version", 1}, {"users", users},
            {"sessions", QJsonArray{QJsonObject{{"id", "hyprland"}, {"name", "Hyprland"}}}}});
        message_ = QStringLiteral("Preview · authentication is disabled");
        emit changed();
    } else connectSocket();
}
void LoginClient::connectSocket() {
    incoming_.clear();
    socket_.connectToServer(socketPath_);
}
void LoginClient::disconnectWith(const QString& message, bool error) {
    ready_ = false;
    busy_ = false;
    needsResponse_ = false;
    echo_ = false;
    message_ = message;
    error_ = error;
    wipe(incoming_);
    wipe(pendingPassword_);
    // abort() can synchronously emit disconnected(); block its signals
    // while clearing this connection's state.
    const QSignalBlocker block(&socket_);
    socket_.abort();
    emit clearResponse();
    emit changed();
    if (!preview_ && !handedOff_) reconnect_.start();
}
void LoginClient::readMessages() {
    try {
        while (socket_.bytesAvailable() > 0) {
            incoming_.append(socket_.read(MaxPacket + 1 - incoming_.size()));
            for (;;) {
                const auto newline = incoming_.indexOf('\n');
                if (newline < 0) break;
                QByteArray frame = incoming_.first(newline);
                incoming_.remove(0, newline + 1);
                handle(decode(frame));
                wipe(frame);
            }
            if (incoming_.size() > MaxPacket) throw Error("Protocol frame too large");
        }
    } catch (const Error&) { disconnectWith(QStringLiteral("The login service sent an invalid response."), true); }
}
void LoginClient::handle(const QJsonObject& message) {
    const QString type = message.value("type").toString();
    if (type == "hello" && !ready_ && !busy_) {
        if (message.value("version").toInt() != 1 || !message.value("sessions").isArray()) throw Error("Unknown protocol version");
        const auto array = message.value("sessions").toArray();
        if (array.isEmpty() || array.size() > 32) throw Error("Invalid sessions");
        sessions_.clear();
        for (const auto& value : array) {
            const QJsonObject session = value.toObject();
            if (!session.value("id").isString() || !session.value("name").isString()) throw Error("Invalid session");
            sessions_.append(session.toVariantMap());
        }
        // Older version-1 daemons lack a user list; discover the same local
        // accounts rather than bringing back a username text field.
        const auto userList = message.value("users");
        if (!userList.isUndefined() && (!userList.isArray() || userList.toArray().size() > 32)) throw Error("Invalid users");
        const auto accounts = userList.isUndefined() ? localUsers(QStringLiteral("zestify-greeter")) : userList.toArray();
        users_.clear();
        std::set<QString> ids;
        for (const auto& value : accounts) {
            const auto account = value.toObject();
            if (!identifier(account.value("id")) || !identifier(account.value("name"))
                || !ids.insert(account.value("id").toString()).second) throw Error("Invalid user list");
            users_.append(QVariantMap{{"id", account.value("id").toString()}, {"name", account.value("name").toString()}});
        }
        ready_ = true;
        message_.clear();
        error_ = false;
    } else if (type == "prompt" && busy_ && !needsResponse_ && !handedOff_) {
        if (!message.value("message").isString() || !message.value("echo").isBool()) throw Error("Invalid prompt");
        prompt_ = message.value("message").toString();
        echo_ = message.value("echo").toBool();
        needsResponse_ = true;
        emit clearResponse();
        if (!echo_ && !pendingPassword_.isEmpty()) {
            const QString value = QString::fromUtf8(pendingPassword_);
            wipe(pendingPassword_);
            respond(value);
            return;
        }
        // Never send a staged secret to a PAM echo-on prompt.
        wipe(pendingPassword_);
    } else if (type == "info" && busy_ && !handedOff_) {
        message_ = message.value("message").toString();
        error_ = message.value("error").toBool();
    } else if (type == "authenticated" && busy_ && !handedOff_) {
        needsResponse_ = false;
        handedOff_ = true;
        // PAM may succeed through another method without asking for a secret.
        wipe(pendingPassword_);
        preferredUser_ = currentUser_;
        preferredSession_ = currentSession_;
        saveSelection();
        message_ = QStringLiteral("Starting your session…");
        emit clearResponse();
    } else if (type == "error" && busy_) {
        handedOff_ = false;
        disconnectWith(message.value("message").toString(), true);
        return;
    } else throw Error("Unexpected protocol state");
    emit changed();
}
void LoginClient::send(const QJsonObject& message) {
    if (preview_) return;
    QByteArray bytes;
    try { bytes = encode(message); }
    catch (const Error&) {
        disconnectWith(QStringLiteral("The response is too large to send."), true);
        return;
    }
    if (socket_.write(bytes) != bytes.size()) {
        wipe(bytes);
        disconnectWith(QStringLiteral("Could not contact the login service."), true);
        return;
    }
    socket_.flush();
    wipe(bytes);
}
void LoginClient::login(const QString& user, const QString& session) {
    if (!ready_ || busy_ || user.trimmed().isEmpty() || user.size() > 256 || user.contains(QChar::Null)) return;
    bool known = false;
    for (const auto& item : sessions_) if (item.toMap().value("id") == session) known = true;
    if (!known) return;
    busy_ = true;
    currentUser_ = user.trimmed();
    currentSession_ = session;
    error_ = false;
    message_ = QStringLiteral("Authenticating…");
    emit changed();
    if (preview_) handle({{"type", "prompt"}, {"message", "Password"}, {"echo", false}});
    else send({{"type", "login"}, {"user", user.trimmed()}, {"session", session}});
}
void LoginClient::submitPassword(const QString& user, const QString& session, const QString& password) {
    if (!ready_ || busy_ || password.isEmpty()) return;
    if (!responseFits(password)) {
        message_ = QStringLiteral("The response is too large. Please try a shorter response.");
        error_ = true;
        emit clearResponse(); emit changed();
        return;
    }
    wipe(pendingPassword_);
    pendingPassword_ = password.toUtf8();
    login(user, session);
    if (!busy_) wipe(pendingPassword_);
}
void LoginClient::respond(const QString& value) {
    if (!busy_ || !needsResponse_ || value.size() > 4096 || value.contains(QChar::Null)) return;
    if (!responseFits(value)) {
        message_ = QStringLiteral("The response is too large. Please try a shorter response.");
        error_ = true;
        emit clearResponse();
        emit changed();
        return;
    }
    needsResponse_ = false;
    echo_ = false;
    message_ = QStringLiteral("Checking credentials…");
    emit clearResponse();
    emit changed();
    if (preview_) {
        busy_ = false;
        message_ = QStringLiteral("Preview · no credentials were checked or saved");
        emit changed();
    } else send({{"type", "response"}, {"value", value}});
}
void LoginClient::cancel() {
    if (handedOff_) return;
    if (preview_) {
        wipe(pendingPassword_);
        busy_ = needsResponse_ = echo_ = false;
        message_ = QStringLiteral("Preview · authentication is disabled");
        emit clearResponse();
        emit changed();
    } else disconnectWith(QStringLiteral("Sign-in cancelled."), false);
}
void LoginClient::loadSelection() {
    Fd descriptor(open(QFile::encodeName(selectionPath_).constData(), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW));
    struct stat info{};
    if (descriptor.get() < 0 || fstat(descriptor.get(), &info) != 0 || !S_ISREG(info.st_mode)
        || info.st_size < 0 || info.st_size > 4096) return;
    QFile file;
    if (!file.open(descriptor.get(), QIODevice::ReadOnly, QFileDevice::DontCloseHandle)) return;
    const auto bytes = file.read(4097);
    if (bytes.size() > 4096) return;
    const auto object = QJsonDocument::fromJson(bytes).object();
    if (identifier(object.value("user"))) preferredUser_ = object.value("user").toString();
    if (identifier(object.value("session"))) preferredSession_ = object.value("session").toString();
}
void LoginClient::saveSelection() {
    if (preview_) return;
    const QFileInfo info(selectionPath_);
    if (info.isSymLink() || (info.exists() && !info.isFile()) || !QDir().mkpath(info.absolutePath())) return;
    QSaveFile file(selectionPath_);
    const auto bytes = QJsonDocument(QJsonObject{{"user", preferredUser_}, {"session", preferredSession_}}).toJson(QJsonDocument::Compact);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
        fprintf(stderr, "zestify-greeter: could not remember account/session selection\n");
}
