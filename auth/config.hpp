#pragma once
#include "protocol.hpp"
#include <QStringList>
#include <vector>

namespace zestify {
struct Session {
    QString id;
    QString name;
    QString desktop;
    QStringList command;
};
struct Config {
    QString greeterUser;
    QStringList greeterCommand;
    int vt = 7;
    std::vector<Session> sessions;
    static Config load(const QString& path, bool requireRootOwner);
    static Config parse(const QByteArray& bytes);
    const Session& session(const QString& id) const;
    QJsonArray publicSessions() const;
};
} // namespace zestify
