#include "greeter.hpp"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QFile>
#include <QLocalServer>
#include <QTemporaryDir>
#include <QThread>
#include <cstdio>
#include <functional>
#include <memory>
#include <unistd.h>

using namespace zestify;
namespace {
void require(bool condition, const char* detail) { if (!condition) throw Error(detail); }
void until(const std::function<bool()>& predicate, const char* detail) {
    QElapsedTimer timer; timer.start();
    while (!predicate() && timer.elapsed() < 2000) {
        QCoreApplication::processEvents();
        QThread::msleep(1);
    }
    require(predicate(), detail);
}
QJsonObject hello() {
    return {{"type", "hello"}, {"version", 1},
        {"users", QJsonArray{QJsonObject{{"id", "test-user"}, {"name", "Test user"}}, QJsonObject{{"id", "second-user"}, {"name", "Second user"}}}},
        {"sessions", QJsonArray{QJsonObject{{"id", "hyprland"}, {"name", "Hyprland"}}}}};
}
QJsonObject prompt(bool echo = false) {
    return {{"type", "prompt"}, {"message", "Test prompt"}, {"echo", echo}};
}
struct Fixture {
    QTemporaryDir directory;
    QLocalServer server;
    LoginClient client;
    std::unique_ptr<QLocalSocket> peer;
    Fixture() : client(directory.filePath("control.sock"), false, geteuid(), directory.filePath("selection.json")) {
        require(directory.isValid() && server.listen(directory.filePath("control.sock")), "test login socket failed");
        client.start();
        until([&] { return server.hasPendingConnections(); }, "greeter did not connect");
        peer.reset(server.nextPendingConnection());
        require(peer != nullptr, "missing greeter connection");
    }
    void write(const QByteArray& bytes) {
        require(peer->write(bytes) == bytes.size(), "mock login write failed");
        peer->flush();
    }
    void send(const QJsonObject& message) { write(encode(message)); }
    QJsonObject receive() {
        until([&] { return peer->canReadLine(); }, "greeter response missing");
        return decode(peer->readLine().trimmed());
    }
    void prepare() {
        const QByteArray greeting = encode(hello());
        write(greeting.first(7));
        QCoreApplication::processEvents();
        require(!client.ready(), "partial hello accepted");
        write(greeting.sliced(7));
        until([&] { return client.ready(); }, "hello not consumed");
        client.login("test-user", "hyprland");
        const auto login = receive();
        require(login.value("type") == "login" && login.value("user") == "test-user", "login request wrong");
        write(encode(prompt()) + encode({{"type", "info"}, {"message", "Additional information"}, {"error", false}}));
        until([&] { return client.needsResponse() && client.message() == "Additional information"; }, "coalesced messages lost");
        require(!client.echo(), "password prompt exposes text");
    }
};
void responseBounds() {
    Fixture fixture; fixture.prepare();
    for (const QString& oversized : {QString(4096, QChar(1)), QString(4096, QChar(0x00e9)), QString(4097, 'x'), QString("a") + QChar::Null + "b"}) {
        fixture.client.respond(oversized);
        QCoreApplication::processEvents();
        require(fixture.client.busy() && fixture.client.needsResponse(), "invalid response consumed the prompt");
        require(fixture.peer->bytesAvailable() == 0, "invalid response reached server");
    }
    // Exactly 4096 UTF-8 bytes must remain valid, even though QString has fewer
    // code units. Limits follow the PAM response bytes, not character count.
    const QString accepted(2048, QChar(0x00e9));
    fixture.client.respond(accepted);
    const auto reply = fixture.receive();
    require(reply.value("type") == "response" && reply.value("value") == accepted, "valid boundary response corrupt");
    require(!fixture.client.needsResponse(), "valid response did not consume prompt");
    fixture.send(prompt(true));
    until([&] { return fixture.client.needsResponse(); }, "second PAM prompt not consumed");
    require(fixture.client.echo(), "echo-on prompt hidden");
    fixture.client.respond("123456");
    require(fixture.receive().value("value") == "123456", "second response corrupt");
    fixture.send({{"type", "authenticated"}});
    until([&] { return fixture.client.message().contains("Starting"); }, "authenticated state missing");
    fixture.peer->disconnectFromServer();
    QCoreApplication::processEvents();
    require(fixture.client.busy() && !fixture.client.needsResponse(), "handoff disconnect reset state");
}
void invalidServerMessages() {
    for (const auto& users : {QJsonValue("users"), QJsonValue(QJsonArray{1}),
        QJsonValue(QJsonArray{QJsonObject{{"id", "duplicate"}, {"name", "User"}}, QJsonObject{{"id", "duplicate"}, {"name", "User"}}}),
        QJsonValue(QJsonArray{QJsonObject{{"id", "bad"}, {"name", QString(257, 'x')}}})}) {
        Fixture fixture;
        auto message = hello(); message["users"] = users;
        fixture.send(message);
        until([&] { return fixture.client.error(); }, "invalid user list accepted");
        require(!fixture.client.ready(), "invalid users enabled authentication");
    }
    {
        Fixture fixture;
        auto message = hello(); message["version"] = 99;
        fixture.send(message);
        until([&] { return fixture.client.error(); }, "unknown version accepted");
        require(!fixture.client.ready(), "invalid version enabled authentication");
    }
    {
        Fixture fixture; fixture.prepare();
        fixture.send(prompt());
        until([&] { return !fixture.client.ready(); }, "duplicate prompt accepted");
        require(!fixture.client.busy() && !fixture.client.needsResponse(), "bad state retained response");
    }
    {
        Fixture fixture;
        fixture.write(QByteArray(MaxPacket + 1, 'x'));
        until([&] { return fixture.client.error(); }, "oversized server frame accepted");
        require(!fixture.client.ready(), "oversized frame enabled authentication");
    }
    {
        Fixture fixture; fixture.prepare(); fixture.client.cancel();
        require(!fixture.client.ready() && !fixture.client.busy() && !fixture.client.needsResponse(), "cancel retained credentials state");
        until([&] { return fixture.server.hasPendingConnections(); }, "cancel did not reconnect");
        std::unique_ptr<QLocalSocket> replacement(fixture.server.nextPendingConnection());
        require(replacement->write(encode(hello())) > 0, "replacement hello failed"); replacement->flush();
        until([&] { return fixture.client.ready(); }, "reconnected client did not reset handshake");
    }
}
void passwordFirst() {
    Fixture fixture;
    fixture.send(hello()); until([&] { return fixture.client.ready(); }, "password-first handshake failed");
    require(fixture.client.users().size() == 2, "users not exposed to picker");
    for (const auto& password : {QString(4097, 'x'), QString(4096, QChar(1)), QString("a") + QChar::Null + "b"}) {
        fixture.client.submitPassword("test-user", "hyprland", password);
        QCoreApplication::processEvents();
        require(!fixture.client.busy() && fixture.peer->bytesAvailable() == 0, "oversized initial password started authentication");
    }
    const QString password(2048, QChar(0x00e9));
    fixture.client.submitPassword("second-user", "hyprland", password);
    const auto request = fixture.receive();
    require(request.value("type") == "login" && request.value("user") == "second-user" && !request.contains("value"), "password-first login request wrong");
    fixture.send(prompt());
    const auto response = fixture.receive();
    require(response.value("type") == "response" && response.value("value") == password, "initial password not supplied to PAM");
    require(!fixture.client.needsResponse() && fixture.client.busy(), "password-first prompt state corrupt");
    fixture.send(prompt(true));
    until([&] { return fixture.client.needsResponse(); }, "MFA prompt not surfaced");
    fixture.client.respond("123456");
    require(fixture.receive().value("value") == "123456", "MFA response corrupt");
    fixture.send({{"type", "authenticated"}});
    until([&] { return fixture.client.preferredUser() == "second-user"; }, "successful account not remembered");
    LoginClient restored({}, false, geteuid(), fixture.directory.filePath("selection.json"));
    require(restored.preferredUser() == "second-user" && restored.preferredSession() == "hyprland", "remembered selection not restored");
    QFile selection(fixture.directory.filePath("selection.json")); require(selection.open(QIODevice::ReadOnly), "selection file missing");
    const auto bytes = selection.readAll();
    require(!bytes.contains(password.toUtf8()) && !bytes.contains("123456"), "selection file saved credentials");
}
void stagedPasswordCleanup() {
    {
        Fixture fixture; fixture.send(hello()); until([&] { return fixture.client.ready(); }, "promptless fixture hello missing");
        fixture.client.submitPassword("test-user", "hyprland", "not-needed-by-pam"); fixture.receive();
        fixture.send({{"type", "authenticated"}});
        until([&] { return fixture.client.preferredUser() == "test-user"; }, "PAM success without a prompt not handled");
        require(fixture.peer->bytesAvailable() == 0 && !fixture.client.needsResponse(), "password sent after promptless success");
    }
    {
        Fixture fixture; fixture.send(hello()); until([&] { return fixture.client.ready(); }, "echo fixture hello missing");
        fixture.client.submitPassword("test-user", "hyprland", "never-echo-this"); fixture.receive();
        fixture.send(prompt(true)); until([&] { return fixture.client.needsResponse(); }, "first echo-on prompt missing");
        require(fixture.peer->bytesAvailable() == 0, "staged password sent to echo-on prompt");
        fixture.client.respond("visible-response"); fixture.receive();
        fixture.send(prompt()); until([&] { return fixture.client.needsResponse(); }, "later password prompt missing");
        require(fixture.peer->bytesAvailable() == 0, "discarded password reused for later prompt");
    }
    for (const bool cancel : {false, true}) {
        Fixture fixture; fixture.send(hello()); until([&] { return fixture.client.ready(); }, "cleanup fixture hello missing");
        fixture.client.submitPassword("test-user", "hyprland", "discard-on-disconnect"); fixture.receive();
        if (cancel) fixture.client.cancel();
        else fixture.peer->disconnectFromServer();
        until([&] { return !fixture.client.ready(); }, "old authentication connection stayed ready");
        until([&] { return fixture.server.hasPendingConnections(); }, "cleanup did not reconnect");
        fixture.peer.reset(fixture.server.nextPendingConnection());
        fixture.send(hello()); until([&] { return fixture.client.ready(); }, "replacement hello missing");
        fixture.client.login("second-user", "hyprland"); fixture.receive();
        fixture.send(prompt()); until([&] { return fixture.client.needsResponse(); }, "replacement prompt missing");
        require(fixture.peer->bytesAvailable() == 0, "staged password survived cancel/disconnect");
    }
}
void preview() {
    LoginClient client({}, true);
    client.start();
    require(client.ready() && !client.busy(), "preview handshake failed");
    client.login("preview-user", "hyprland");
    require(client.needsResponse(), "preview prompt missing");
    client.respond("dummy-preview-value");
    require(!client.busy() && !client.needsResponse() && client.message().contains("no credentials"), "preview checked credentials");
}
void connectedDestruction() {
    // QLocalSocket destruction can synchronously emit disconnected. The
    // client must disable its callbacks before timer/string members die.
    Fixture fixture;
    fixture.send(hello());
    until([&] { return fixture.client.ready(); }, "destruction fixture handshake failed");
}
}
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    try {
        preview(); responseBounds(); invalidServerMessages(); connectedDestruction(); passwordFirst(); stagedPasswordCleanup();
        puts("GREETER CLIENT PASS: boundaries, multiprompt state, reconnect and preview");
        return 0;
    } catch (const std::exception& error) {
        fprintf(stderr, "GREETER CLIENT FAIL: %s\n", error.what());
        return 1;
    }
}
