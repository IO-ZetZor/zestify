#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <csignal>
#include <stdexcept>

namespace zestify {
constexpr qsizetype MaxPacket = 16384;
extern volatile sig_atomic_t stopping;

class Error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class Fd {
public:
    explicit Fd(int value = -1) : value_(value) {}
    ~Fd();
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
    Fd(Fd&& other) noexcept : value_(other.release()) {}
    Fd& operator=(Fd&& other) noexcept;
    int get() const { return value_; }
    int release() { int value = value_; value_ = -1; return value; }
private:
    int value_;
};

void wipe(QByteArray& bytes);
QByteArray encode(const QJsonObject& message);
QJsonObject decode(const QByteArray& bytes);

// Newline-framed UTF-8 JSON over an AF_UNIX stream. One bounded frame per
// request, with a deadline covering partial reads and writes.
class Channel {
public:
    explicit Channel(int fd, int timeoutMs = 120000) : fd_(fd), timeoutMs_(timeoutMs) {}
    void send(const QJsonObject& message);
    QJsonObject receive();
private:
    int fd_;
    int timeoutMs_;
};
} // namespace zestify
