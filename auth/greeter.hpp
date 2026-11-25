#pragma once
#include "protocol.hpp"
#include <QObject>
#include <QLocalSocket>
#include <QTimer>
#include <QVariantList>
#include <sys/types.h>

class LoginClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool needsResponse READ needsResponse NOTIFY changed)
    Q_PROPERTY(bool echo READ echo NOTIFY changed)
    Q_PROPERTY(QString prompt READ prompt NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(bool error READ error NOTIFY changed)
    Q_PROPERTY(QVariantList sessions READ sessions NOTIFY changed)
    Q_PROPERTY(QVariantList users READ users NOTIFY changed)
    Q_PROPERTY(QString preferredUser READ preferredUser NOTIFY changed)
    Q_PROPERTY(QString preferredSession READ preferredSession NOTIFY changed)
    Q_PROPERTY(bool preview READ preview CONSTANT)
public:
    explicit LoginClient(QString socketPath, bool preview = false, uid_t expectedPeer = 0, QString selectionPath = {});
    ~LoginClient() override;
    bool ready() const { return ready_; }
    bool busy() const { return busy_; }
    bool needsResponse() const { return needsResponse_; }
    bool echo() const { return echo_; }
    QString prompt() const { return prompt_; }
    QString message() const { return message_; }
    bool error() const { return error_; }
    QVariantList sessions() const { return sessions_; }
    QVariantList users() const { return users_; }
    QString preferredUser() const { return preferredUser_; }
    QString preferredSession() const { return preferredSession_; }
    bool preview() const { return preview_; }
    Q_INVOKABLE void login(const QString& user, const QString& session);
    Q_INVOKABLE void submitPassword(const QString& user, const QString& session, const QString& password);
    Q_INVOKABLE void respond(const QString& value);
    Q_INVOKABLE void cancel();
    void start();
signals:
    void changed();
    void clearResponse();
private:
    void connectSocket();
    void readMessages();
    void handle(const QJsonObject& message);
    void send(const QJsonObject& message);
    void disconnectWith(const QString& message, bool error);
    void loadSelection();
    void saveSelection();
    QLocalSocket socket_;
    QTimer reconnect_;
    QString socketPath_;
    QByteArray incoming_, pendingPassword_;
    QVariantList sessions_, users_;
    QString prompt_, message_;
    QString selectionPath_, preferredUser_, preferredSession_, currentUser_, currentSession_;
    uid_t expectedPeer_;
    bool preview_, ready_ = false, busy_ = false, needsResponse_ = false, echo_ = false, error_ = false;
    bool handedOff_ = false;
};
