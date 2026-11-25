#include "pam_session.hpp"
#include <cstdlib>
#include <cstring>

namespace zestify {
PamSession::PamSession(const char* service, const QString& userName, int vt, Channel* channel, bool greeter, const char* testConfigDir)
    : channel_(channel) {
    pam_conv conversation{converse, this};
    QByteArray userBytes = userName.toUtf8();
    status_ = testConfigDir
        ? pam_start_confdir(service, userBytes.constData(), &conversation, testConfigDir, &handle_)
        : pam_start(service, userBytes.constData(), &conversation, &handle_);
    if (status_ != PAM_SUCCESS) throw Error("Cannot initialize PAM");
    try {
        QByteArray tty = "/dev/tty" + QByteArray::number(vt);
        check(pam_set_item(handle_, PAM_TTY, tty.constData()), "PAM TTY");
        for (const QByteArray& value : {QByteArray("XDG_SESSION_TYPE=wayland"), QByteArray("XDG_SEAT=seat0"),
                QByteArray("XDG_VTNR=") + QByteArray::number(vt),
                QByteArray(greeter ? "XDG_SESSION_CLASS=greeter" : "XDG_SESSION_CLASS=user")})
            check(pam_putenv(handle_, value.constData()), "PAM environment");
    } catch (...) { pam_end(handle_, status_); handle_ = nullptr; throw; }
}
PamSession::~PamSession() {
    if (!handle_) return;
    if (opened_) pam_close_session(handle_, 0);
    if (credentials_) pam_setcred(handle_, PAM_DELETE_CRED);
    pam_end(handle_, status_);
}
void PamSession::check(int code, const char* operation) {
    status_ = code;
    if (code != PAM_SUCCESS) throw Error(std::string(operation) + " failed: " + pam_strerror(handle_, code));
}
void PamSession::authenticate() {
    check(pam_authenticate(handle_, PAM_DISALLOW_NULL_AUTHTOK), "Authentication");
    const int account = pam_acct_mgmt(handle_, 0);
    if (account == PAM_NEW_AUTHTOK_REQD) check(pam_chauthtok(handle_, PAM_CHANGE_EXPIRED_AUTHTOK), "Password change");
    else check(account, "Account validation");
}
void PamSession::open() {
    check(pam_setcred(handle_, PAM_ESTABLISH_CRED), "Credentials");
    credentials_ = true;
    check(pam_open_session(handle_, 0), "Session setup");
    opened_ = true;
}
QString PamSession::user() const {
    const void* item = nullptr;
    if (pam_get_item(handle_, PAM_USER, &item) != PAM_SUCCESS || !item) throw Error("PAM returned no account");
    return QString::fromUtf8(static_cast<const char*>(item));
}
QStringList PamSession::environment() const {
    QStringList result;
    char** values = pam_getenvlist(handle_);
    if (!values) throw Error("PAM returned no environment");
    for (char** item = values; *item; ++item) {
        result.append(QString::fromUtf8(*item));
        free(*item);
    }
    free(values);
    return result;
}
int PamSession::converse(int count, const pam_message** messages, pam_response** responses, void* data) noexcept {
    if (!responses || !messages || count <= 0 || count > PAM_MAX_NUM_MSG) return PAM_CONV_ERR;
    *responses = nullptr;
    auto* self = static_cast<PamSession*>(data);
    auto* reply = static_cast<pam_response*>(calloc(static_cast<size_t>(count), sizeof(pam_response)));
    if (!reply) return PAM_BUF_ERR;
    try {
        for (int i = 0; i < count; ++i) {
            if (!messages[i]) throw Error("Invalid PAM message");
            const auto* message = messages[i];
            const QString prompt = QString::fromUtf8(message->msg ? message->msg : "").left(4096);
            if (message->msg_style == PAM_TEXT_INFO || message->msg_style == PAM_ERROR_MSG) {
                if (self->channel_)
                    self->channel_->send({{"type", "info"}, {"message", prompt}, {"error", message->msg_style == PAM_ERROR_MSG}});
            } else if (message->msg_style == PAM_PROMPT_ECHO_OFF || message->msg_style == PAM_PROMPT_ECHO_ON) {
                if (!self->channel_) throw Error("No conversation client");
                self->channel_->send({{"type", "prompt"}, {"message", prompt}, {"echo", message->msg_style == PAM_PROMPT_ECHO_ON}});
                auto response = self->channel_->receive();
                if (response.value("type") != "response" || !response.value("value").isString()) throw Error("Conversation cancelled");
                QByteArray value = response.value("value").toString().toUtf8();
                response = {};
                if (value.contains('\0') || value.size() > 4096) { wipe(value); throw Error("Invalid response"); }
                reply[i].resp = static_cast<char*>(malloc(static_cast<size_t>(value.size()) + 1));
                if (!reply[i].resp) { wipe(value); throw Error("Out of memory"); }
                memcpy(reply[i].resp, value.constData(), static_cast<size_t>(value.size()));
                reply[i].resp[value.size()] = '\0';
                wipe(value);
            } else throw Error("Unsupported PAM message");
        }
        *responses = reply;
        return PAM_SUCCESS;
    } catch (...) {
        for (int i = 0; i < count; ++i) if (reply[i].resp) {
            explicit_bzero(reply[i].resp, strlen(reply[i].resp));
            free(reply[i].resp);
        }
        free(reply);
        return PAM_CONV_ERR;
    }
}
} // namespace zestify
