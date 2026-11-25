#include "users.hpp"
#include "protocol.hpp"
#include <QFile>
#include <QJsonObject>
#include <QRegularExpression>
#include <algorithm>
#include <set>
#include <fcntl.h>
#include <sys/stat.h>

namespace zestify {
namespace {
QByteArray readLocalFile(const QString& path) {
    Fd descriptor(open(QFile::encodeName(path).constData(), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW));
    struct stat info{};
    constexpr int limit = 1024 * 1024;
    if (descriptor.get() < 0 || fstat(descriptor.get(), &info) != 0 || !S_ISREG(info.st_mode)
        || info.st_size < 0 || info.st_size > limit) return {};
    QFile file;
    if (!file.open(descriptor.get(), QIODevice::ReadOnly, QFileDevice::DontCloseHandle)) return {};
    const auto bytes = file.read(limit + 1);
    return bytes.size() <= limit ? bytes : QByteArray{};
}
}
QJsonArray localUsers(const QString& excluded, const QString& passwdPath, const QString& loginDefsPath) {
    quint64 minimum = 1000, maximum = 60000;
    const QString definitions = QString::fromUtf8(readLocalFile(loginDefsPath));
    const QRegularExpression setting(QStringLiteral("^\\s*(UID_MIN|UID_MAX)\\s+(\\d+)\\s*(?:#.*)?$"));
    for (const auto& line : definitions.split('\n')) {
        const auto match = setting.match(line);
        if (!match.hasMatch()) continue;
        bool valid = false;
        const auto number = match.captured(2).toULongLong(&valid);
        if (!valid || number > 0xffffffffULL) continue;
        if (match.captured(1) == "UID_MIN") minimum = number;
        else maximum = number;
    }
    std::vector<QJsonObject> accounts;
    std::set<QString> names;
    for (const auto& line : QString::fromUtf8(readLocalFile(passwdPath)).split('\n')) {
        const auto fields = line.split(':');
        if (fields.size() != 7) continue;
        const QString user = fields[0];
        bool valid = false;
        const auto uid = fields[2].toULongLong(&valid);
        const auto shell = fields[6].trimmed();
        if (!valid || uid == 0 || uid < minimum || uid > maximum || user == excluded || user.isEmpty()
            || user.size() > 256 || user.contains(QChar::Null) || fields[5].isEmpty()
            || shell.isEmpty() || shell.endsWith("/nologin") || shell.endsWith("/false") || !names.insert(user).second) continue;
        QString name = fields[4].section(',', 0, 0).trimmed();
        if (name.isEmpty() || name.size() > 256 || name.contains(QChar::Null)) name = user;
        accounts.push_back({{"id", user}, {"name", name}});
    }
    std::sort(accounts.begin(), accounts.end(), [](const auto& left, const auto& right) {
        return left.value("id").toString() < right.value("id").toString();
    });
    QJsonArray result;
    // Keep hello safely below the existing 16 KiB protocol frame limit even
    // when the account database is large or names require JSON escaping.
    for (const auto& account : accounts) {
        if (result.size() >= 32) break;
        try { encode({{"users", QJsonArray{account}}}); }
        catch (const Error&) { continue; }
        auto candidate = result; candidate.append(account);
        try {
            const auto bytes = encode({{"users", candidate}});
            if (bytes.size() > MaxPacket / 2) break;
        } catch (const Error&) { break; }
        result = candidate;
    }
    return result;
}
}
