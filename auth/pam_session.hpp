#pragma once
#include "protocol.hpp"
#include <QStringList>
#include <security/pam_appl.h>

namespace zestify {
// A handle is owned by one supervisor process for its entire lifetime. PAM
// cleanup runs after the session child exits, still with root credentials.
class PamSession {
public:
    PamSession(const char* service, const QString& user, int vt, Channel* channel, bool greeter = false, const char* testConfigDir = nullptr);
    ~PamSession();
    PamSession(const PamSession&) = delete;
    PamSession& operator=(const PamSession&) = delete;
    void authenticate();
    void open();
    void detachClient() { channel_ = nullptr; }
    QString user() const;
    QStringList environment() const;
private:
    pam_handle_t* handle_ = nullptr;
    Channel* channel_;
    bool credentials_ = false;
    bool opened_ = false;
    int status_ = PAM_SUCCESS;
    void check(int code, const char* operation);
    static int converse(int count, const pam_message** messages, pam_response** responses, void* data) noexcept;
};
} // namespace zestify
