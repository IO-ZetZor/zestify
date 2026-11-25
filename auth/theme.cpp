#include "theme.hpp"
#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QSaveFile>
#include <cmath>
#include <stdexcept>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
QJsonValue get(const QJsonObject& object, const QStringList& keys) {
    QJsonValue result(object);
    for (const auto& key : keys) result = result.toObject().value(key);
    return result;
}
void put(QJsonObject& object, const QStringList& keys, const QJsonValue& value, int index = 0) {
    if (index == keys.size() - 1) { object[keys[index]] = value; return; }
    QJsonObject child = object.value(keys[index]).toObject();
    put(child, keys, value, index + 1);
    object[keys[index]] = child;
}
void knownKeys(const QJsonObject& input, const QJsonObject& defaults, const QString& prefix = {}) {
    for (auto it = input.begin(); it != input.end(); ++it) {
        const QString key = prefix + it.key();
        if (!defaults.contains(it.key())) throw std::runtime_error(("Unknown theme field: " + key).toStdString());
        if (defaults.value(it.key()).isObject()) {
            if (!it->isObject()) throw std::runtime_error(("Expected an object: " + key).toStdString());
            knownKeys(it->toObject(), defaults.value(it.key()).toObject(), key + '.');
        }
    }
}
bool localPath(const QString& path) {
    return !path.contains(QChar::Null) && QUrl(path).scheme().isEmpty();
}
QString identity(const QString& path) {
    struct stat info{};
    if (lstat(QFile::encodeName(path).constData(), &info) != 0) return {};
    return QStringLiteral("%1/%2/%3/%4/%5")
        .arg(static_cast<qulonglong>(info.st_dev)).arg(static_cast<qulonglong>(info.st_ino))
        .arg(static_cast<qlonglong>(info.st_size)).arg(static_cast<qlonglong>(info.st_mtim.tv_sec))
        .arg(static_cast<qlonglong>(info.st_mtim.tv_nsec));
}
}

GreeterTheme::GreeterTheme(QString path, bool editable, bool allowMissing)
    : path_(QFileInfo(path).absoluteFilePath()), editable_(editable) {
    QFile schema(QStringLiteral(":/theme-schema.json"));
    if (!schema.open(QIODevice::ReadOnly)) throw std::runtime_error("Missing embedded theme schema");
    fields_ = QJsonDocument::fromJson(schema.readAll()).array();
    if (fields_.isEmpty()) throw std::runtime_error("Invalid embedded theme schema");
    for (const auto& field : fields_) {
        const auto spec = field.toObject();
        put(defaults_, spec.value("path").toString().split('.'), spec.value("value"));
    }
    values_ = defaults_;
    if (auto* app = qobject_cast<QGuiApplication*>(QCoreApplication::instance())) {
        refreshFonts();
        connect(app, &QGuiApplication::fontDatabaseChanged, this, &GreeterTheme::refreshFonts);
    }
    debounce_.setSingleShot(true);
    debounce_.setInterval(150);
    connect(&watcher_, &QFileSystemWatcher::fileChanged, this, [this] { debounce_.start(); });
    connect(&watcher_, &QFileSystemWatcher::directoryChanged, this, [this] {
        // Saving an asset or unrelated file beside the theme must not discard
        // unsaved preview edits. Reload only if the watched theme changed.
        if (identity(path_) != fileIdentity_) debounce_.start();
    });
    connect(&debounce_, &QTimer::timeout, this, [this] { reload(); });
    load(allowMissing);
}

QJsonObject GreeterTheme::parse(const QByteArray& bytes) const {
    if (bytes.size() > MaxThemeBytes) throw std::runtime_error("Theme exceeds 256 KiB");
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(bytes, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
        throw std::runtime_error("Theme must be a JSON object");
    const auto input = doc.object();
    knownKeys(input, defaults_);
    QJsonObject result = defaults_;
    for (const auto& field : fields_) {
        const auto spec = field.toObject();
        const QString key = spec.value("path").toString();
        const auto keys = key.split('.');
        const auto value = get(input, keys);
        if (value.isUndefined()) continue;
        const auto type = spec.value("type").toString();
        bool valid = false;
        if (type == "boolean") valid = value.isBool();
        else if (type == "number") {
            const double n = value.toDouble();
            valid = value.isDouble() && std::isfinite(n) && n >= spec.value("min").toDouble()
                && n <= spec.value("max").toDouble();
            if (key == "version") valid = valid && n == 1;
        } else if (value.isString()) {
            const QString text = value.toString();
            valid = text.size() <= 4096 && !text.contains(QChar::Null);
            if (type == "color") valid = valid && QColor::isValidColorName(text);
            if (type == "asset") valid = valid && localPath(text);
            if (type == "choice") valid = valid && spec.value("choices").toArray().contains(value);
            if (type == "order") {
                auto order = text.split(',');
                auto expected = spec.value("value").toString().split(',');
                order.sort(); expected.sort();
                valid = valid && order == expected;
            }
        }
        if (!valid) throw std::runtime_error(("Invalid theme field: " + key).toStdString());
        put(result, keys, value);
    }
    return result;
}

void GreeterTheme::report(const QString& text, bool error) {
    status_ = text;
    error_ = error;
    emit statusChanged();
}
void GreeterTheme::watch() {
    fileIdentity_ = identity(path_);
    if (!watcher_.files().isEmpty()) watcher_.removePaths(watcher_.files());
    if (!watcher_.directories().isEmpty()) watcher_.removePaths(watcher_.directories());
    // Watching the parent also catches atomic replacement and file recreation.
    QString parent = QFileInfo(path_).absolutePath();
    while (!QDir(parent).exists() && parent != "/") parent = QFileInfo(parent).absolutePath();
    watcher_.addPath(parent);
    if (QFileInfo(path_).isFile()) watcher_.addPath(path_);
}
bool GreeterTheme::load(bool allowMissing) {
    try {
        // Bound reads and reject nonregular files before opening through Qt:
        // a mistakenly configured FIFO must not hang the login screen.
        const QByteArray name = QFile::encodeName(path_);
        const int descriptor = open(name.constData(), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW);
        if (descriptor < 0) {
            if (allowMissing && errno == ENOENT) { watch(); return true; }
            throw std::runtime_error("Cannot open theme file");
        }
        QFile file;
        if (!file.open(descriptor, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
            close(descriptor);
            throw std::runtime_error("Cannot read theme file");
        }
        struct stat info{};
        if (fstat(descriptor, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size < 0 || info.st_size > MaxThemeBytes)
            throw std::runtime_error("Theme must be a regular file of at most 256 KiB");
        const auto next = parse(file.read(MaxThemeBytes + 1));
        values_ = next;
        report("Loaded " + path_, false);
        watch();
        emit changed();
        return true;
    } catch (const std::exception& error) {
        report(QString::fromUtf8(error.what()) + ": " + path_, true);
        watch();
        return false;
    }
}
bool GreeterTheme::reload() { return load(false); }
QUrl GreeterTheme::assetUrl(const QString& path) const {
    if (path.isEmpty() || !localPath(path)) return {};
    return QUrl::fromLocalFile(QDir(QFileInfo(path_).absolutePath()).absoluteFilePath(path));
}
QVariant GreeterTheme::value(const QString& key) const { return get(values_, key.split('.')).toVariant(); }
QStringList GreeterTheme::fontFamilies() const {
    // QML reference sequences reread the property during iteration. Returning
    // an implicitly shared cached list keeps each read cheap.
    return fontFamilies_;
}
void GreeterTheme::refreshFonts() {
    QStringList families = QFontDatabase::families();
    families.append({"sans-serif", "serif", "monospace"});
    families.removeDuplicates();
    families.sort(Qt::CaseInsensitive);
    if (families == fontFamilies_) return;
    fontFamilies_ = families;
    emit fontsChanged();
}
bool GreeterTheme::selectFont(const QString& key, const QString& family) {
    if (!editable_) return false;
    QString fileKey;
    if (key == "fonts.family") fileKey = "fonts.file";
    else if (key == "fonts.clockFamily") fileKey = "fonts.clockFile";
    else if (key == "fonts.iconFamily") fileKey = "fonts.iconFile";
    else return false;
    if (!fontFamilies().contains(family)) { report("Choose an installed font", true); return false; }
    // A file font takes precedence in QML; selecting a family must clear that
    // override so the font the user picked is actually applied.
    put(values_, key.split('.'), family);
    put(values_, fileKey.split('.'), QString{});
    report("Preview changed · save to keep this theme", false);
    emit changed();
    return true;
}
bool GreeterTheme::selectAsset(const QString& key, const QUrl& file) {
    if (!editable_) return false;
    bool asset = false;
    for (const auto& field : fields_) {
        const auto spec = field.toObject();
        if (spec.value("path") == key && spec.value("type") == "asset") asset = true;
    }
    if (!asset || !file.isLocalFile() || !QFileInfo(file.toLocalFile()).isFile() || !QFileInfo(file.toLocalFile()).isReadable()) {
        report("Choose a readable local file", true); return false;
    }
    QJsonObject candidate = values_;
    put(candidate, key.split('.'), file.toLocalFile());
    if (key == "background.source") {
        const QString suffix = QFileInfo(file.toLocalFile()).suffix().toLower();
        QString type = "image";
        if (QStringList{"mp4", "webm", "mkv", "mov", "avi", "m4v", "ogv"}.contains(suffix)) type = "video";
        else if (suffix == "gif" || suffix == "apng") type = "animated";
        put(candidate, {"background", "type"}, type);
    }
    try {
        values_ = parse(QJsonDocument(candidate).toJson(QJsonDocument::Compact));
        report("Preview changed · save to keep this theme", false);
        emit changed();
        return true;
    } catch (const std::exception& error) { report(QString::fromUtf8(error.what()), true); return false; }
}
bool GreeterTheme::setValue(const QString& key, const QVariant& value) {
    if (!editable_) return false;
    bool known = false;
    for (const auto& field : fields_) if (field.toObject().value("path") == key) known = true;
    if (!known) { report("Unknown theme field: " + key, true); return false; }
    QJsonObject candidate = values_;
    put(candidate, key.split('.'), QJsonValue::fromVariant(value));
    try {
        values_ = parse(QJsonDocument(candidate).toJson(QJsonDocument::Compact));
        report("Preview changed · save to keep this theme", false);
        emit changed();
        return true;
    } catch (const std::exception& error) { report(QString::fromUtf8(error.what()), true); return false; }
}
void GreeterTheme::reset() {
    if (!editable_) return;
    values_ = defaults_;
    report("Defaults restored in preview · save to keep", false);
    emit changed();
}
bool GreeterTheme::save(const QString& path) {
    if (!editable_) return false;
    try {
        if (path.isEmpty() || !localPath(path)) throw std::runtime_error("Choose a local theme filename");
        const QString destination = QFileInfo(path).absoluteFilePath();
        const QFileInfo info(destination);
        if (info.isSymLink() || (info.exists() && !info.isFile())) throw std::runtime_error("Destination must be a regular file");
        QJsonObject saved = values_;
        if (destination != path_) {
            // Keep relative assets pointing at the same files after Save As.
            for (const auto& field : fields_) {
                const auto spec = field.toObject();
                const auto keys = spec.value("path").toString().split('.');
                const QString asset = get(saved, keys).toString();
                if (spec.value("type") == "asset" && !asset.isEmpty()) put(saved, keys, assetUrl(asset).toLocalFile());
            }
        }
        if (!QDir().mkpath(info.absolutePath())) throw std::runtime_error("Cannot create theme directory");
        QSaveFile file(destination);
        const auto bytes = QJsonDocument(saved).toJson(QJsonDocument::Indented);
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
            throw std::runtime_error("Cannot save theme file");
        path_ = destination;
        values_ = saved;
        debounce_.stop();
        watch();
        report("Saved " + path_, false);
        emit changed();
        return true;
    } catch (const std::exception& error) { report(QString::fromUtf8(error.what()), true); return false; }
}
