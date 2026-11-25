#include "protocol.hpp"

#include <QJsonDocument>
#include <QJsonParseError>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

namespace zestify {
volatile sig_atomic_t stopping = 0;
Fd::~Fd() { if (value_ >= 0) close(value_); }
Fd& Fd::operator=(Fd&& other) noexcept {
    if (this != &other) {
        if (value_ >= 0) close(value_);
        value_ = other.release();
    }
    return *this;
}

void wipe(QByteArray& bytes) {
    // QByteArray is implicitly shared; detach before erasing our owned copy.
    if (!bytes.isEmpty()) explicit_bzero(bytes.data(), static_cast<size_t>(bytes.size()));
    bytes.clear();
}

QByteArray encode(const QJsonObject& message) {
    QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
    if (bytes.size() > MaxPacket) {
        wipe(bytes);
        throw Error("Protocol frame too large");
    }
    bytes.append('\n');
    return bytes;
}

QJsonObject decode(const QByteArray& bytes) {
    if (bytes.size() > MaxPacket) throw Error("Protocol frame too large");
    QJsonParseError error;
    QJsonDocument document = QJsonDocument::fromJson(bytes, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        throw Error("Invalid protocol frame");
    return document.object();
}

using Clock = std::chrono::steady_clock;
static void waitReady(int fd, short events, Clock::time_point deadline) {
    while (!stopping) {
        auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
        if (remaining <= 0) throw Error("Authentication timed out");
        pollfd item{fd, events, 0};
        int result = poll(&item, 1, static_cast<int>(std::min<int64_t>(remaining, 250)));
        if (result < 0 && errno != EINTR) throw Error("Protocol poll failed");
        if (result > 0) {
            if (item.revents & events) return;
            if (item.revents & (POLLERR | POLLHUP | POLLNVAL)) throw Error("Peer disconnected");
        }
    }
    throw Error("Stopping");
}

void Channel::send(const QJsonObject& message) {
    QByteArray bytes = encode(message);
    const auto deadline = Clock::now() + std::chrono::milliseconds(timeoutMs_);
    qsizetype offset = 0;
    try {
        while (offset < bytes.size()) {
            waitReady(fd_, POLLOUT, deadline);
            ssize_t count = ::send(fd_, bytes.constData() + offset, static_cast<size_t>(bytes.size() - offset), MSG_NOSIGNAL | MSG_DONTWAIT);
            if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
            if (count <= 0) throw Error("Protocol write failed");
            offset += count;
        }
    } catch (...) { wipe(bytes); throw; }
    wipe(bytes);
}

QJsonObject Channel::receive() {
    QByteArray bytes;
    struct Scratch {
        char data[4096];
        ~Scratch() { explicit_bzero(data, sizeof(data)); }
    } scratch;
    const auto deadline = Clock::now() + std::chrono::milliseconds(timeoutMs_);
    try {
        // Peek for the delimiter before consuming a chunk. Leave the next
        // frame in the socket, including across Channel destruction/handoff.
        for (;;) {
            waitReady(fd_, POLLIN, deadline);
            const auto room = static_cast<size_t>(MaxPacket - bytes.size() + 1);
            ssize_t count = recv(fd_, scratch.data, std::min(sizeof(scratch.data), room), MSG_PEEK | MSG_DONTWAIT);
            if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
            if (count <= 0) throw Error("Peer disconnected");
            const auto* newline = static_cast<const char*>(memchr(scratch.data, '\n', static_cast<size_t>(count)));
            const size_t wanted = newline ? static_cast<size_t>(newline - scratch.data) + 1 : static_cast<size_t>(count);
            if (bytes.size() + static_cast<qsizetype>(wanted) - (newline ? 1 : 0) > MaxPacket)
                throw Error("Protocol frame too large");
            count = recv(fd_, scratch.data, wanted, MSG_DONTWAIT);
            if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
            if (count <= 0) throw Error("Peer disconnected");
            const bool complete = newline && static_cast<size_t>(count) == wanted;
            bytes.append(scratch.data, count - (complete ? 1 : 0));
            if (complete) {
                QJsonObject message = decode(bytes);
                wipe(bytes);
                return message;
            }
        }
    } catch (...) { wipe(bytes); throw; }
}
} // namespace zestify
