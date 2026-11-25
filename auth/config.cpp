#include "config.hpp"
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <set>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace zestify {
static QString textField(const QJsonObject& obj, const char* key) {
    QJsonValue field = obj.value(QLatin1String(key));
    if (!field.isString() || field.toString().isEmpty() || field.toString().size() > 256 || field.toString().contains(QChar::Null))
        throw Error(std::string("Invalid config field: ") + key);
    return field.toString();
}
static QStringList commandField(const QJsonObject& obj, const char* key) {
    QJsonArray values = obj.value(QLatin1String(key)).toArray();
    if (values.isEmpty() || values.size() > 64) throw Error("Command must be a nonempty argument array");
    QStringList command;
    for (const auto& value : values) {
        if (!value.isString() || value.toString().contains(QChar::Null) || value.toString().size() > 4096)
            throw Error("Invalid command argument");
        command.append(value.toString());
    }
    if (!command.first().startsWith('/')) throw Error("Executable must be an absolute path");
    return command;
}
Config Config::parse(const QByteArray& bytes) {
    QJsonObject object = decode(bytes);
    Config result;
    result.greeterUser = textField(object, "greeterUser");
    result.greeterCommand = commandField(object, "greeterCommand");
    const QJsonValue vt = object.value("vt");
    if (!vt.isDouble() || vt.toDouble() != vt.toInt() || vt.toInt() < 1 || vt.toInt() > 63)
        throw Error("VT must be an integer between 1 and 63");
    result.vt = vt.toInt();
    QJsonArray sessions = object.value("sessions").toArray();
    if (sessions.isEmpty() || sessions.size() > 32) throw Error("Configure between 1 and 32 sessions");
    std::set<QString> ids;
    for (const auto& value : sessions) {
        if (!value.isObject()) throw Error("Invalid session");
        const auto obj = value.toObject();
        Session item{textField(obj, "id"), textField(obj, "name"), textField(obj, "desktop"), commandField(obj, "command")};
        if (!QRegularExpression(QStringLiteral("^[a-zA-Z0-9_-]+$")).match(item.id).hasMatch() || !ids.insert(item.id).second)
            throw Error("Session IDs must be unique alphanumeric identifiers");
        result.sessions.push_back(std::move(item));
    }
    return result;
}
Config Config::load(const QString& path, bool requireRootOwner) {
    const QByteArray name = QFile::encodeName(path);
    Fd fd(open(name.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
    struct stat info{};
    if (fd.get() < 0 || fstat(fd.get(), &info) != 0 || !S_ISREG(info.st_mode)
        || info.st_size < 0 || info.st_size > MaxPacket)
        throw Error("Cannot read configuration file");
    if (requireRootOwner && (info.st_uid != 0 || (info.st_mode & 0022)))
        throw Error("Configuration must be owned by root and not writable by group or others");
    QFile file;
    if (!file.open(fd.get(), QIODevice::ReadOnly, QFileDevice::DontCloseHandle)) throw Error("Cannot open configuration");
    QByteArray bytes = file.read(MaxPacket + 1);
    return parse(bytes);
}
const Session& Config::session(const QString& id) const {
    for (const auto& item : sessions) if (item.id == id) return item;
    throw Error("Unknown session");
}
QJsonArray Config::publicSessions() const {
    QJsonArray result;
    for (const auto& item : sessions) result.append(QJsonObject{{"id", item.id}, {"name", item.name}});
    return result;
}
} // namespace zestify
