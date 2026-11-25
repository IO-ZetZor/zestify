#pragma once
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QStringList>

// Appearance is local data, never QML or executable code. Only the preview
// exposes edits/saves; the system greeter reads its theme as an unprivileged user.
class GreeterTheme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap data READ data NOTIFY changed)
    Q_PROPERTY(QVariantList fields READ fields CONSTANT)
    Q_PROPERTY(QString path READ path NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool error READ error NOTIFY statusChanged)
    Q_PROPERTY(bool editable READ editable CONSTANT)
    Q_PROPERTY(QStringList fontFamilies READ fontFamilies NOTIFY fontsChanged)
public:
    GreeterTheme(QString path, bool editable, bool allowMissing = false);
    QVariantMap data() const { return values_.toVariantMap(); }
    QVariantList fields() const { return fields_.toVariantList(); }
    QString path() const { return path_; }
    QString status() const { return status_; }
    bool error() const { return error_; }
    bool editable() const { return editable_; }
    QStringList fontFamilies() const;
    Q_INVOKABLE QUrl assetUrl(const QString& path) const;
    Q_INVOKABLE QVariant value(const QString& key) const;
    Q_INVOKABLE bool setValue(const QString& key, const QVariant& value);
    Q_INVOKABLE bool selectFont(const QString& key, const QString& family);
    Q_INVOKABLE bool selectAsset(const QString& key, const QUrl& file);
    Q_INVOKABLE bool save(const QString& path);
    Q_INVOKABLE void reset();
    Q_INVOKABLE bool reload();
    static constexpr int MaxThemeBytes = 256 * 1024;
signals:
    void changed();
    void statusChanged();
    void fontsChanged();
private:
    QJsonObject parse(const QByteArray& bytes) const;
    void watch();
    bool load(bool allowMissing);
    void refreshFonts();
    void report(const QString& text, bool error);
    QJsonArray fields_;
    QJsonObject defaults_, values_;
    QString path_, status_, fileIdentity_;
    QStringList fontFamilies_;
    bool editable_, error_ = false;
    QFileSystemWatcher watcher_;
    QTimer debounce_;
};
