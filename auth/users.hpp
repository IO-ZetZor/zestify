#pragma once
#include <QJsonArray>
#include <QString>

namespace zestify {
// Public display names only; no shadow/password data or session credentials.
QJsonArray localUsers(const QString& excludedUser, const QString& passwdPath = QStringLiteral("/etc/passwd"),
    const QString& loginDefsPath = QStringLiteral("/etc/login.defs"));
}
