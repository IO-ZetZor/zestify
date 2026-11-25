// Test-only PAM provider. It is loaded exclusively through pam_start_confdir
// and a temporary policy; no host authentication policy uses this module.
#include <security/pam_modules.h>
#include <security/pam_appl.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {
bool option(int argc, const char** argv, const char* wanted) {
    for (int i = 0; i < argc; ++i) if (std::strcmp(argv[i], wanted) == 0) return true;
    return false;
}
const char* logPath(int argc, const char** argv) {
    for (int i = 0; i < argc; ++i)
        if (std::strncmp(argv[i], "log=", 4) == 0) return argv[i] + 4;
    return nullptr;
}
void record(const char* path, const char* event) {
    if (!path) return;
    if (FILE* file = std::fopen(path, "a")) {
        std::fprintf(file, "%s\n", event);
        std::fclose(file);
    }
}
void cleanup(pam_handle_t*, void* data, int) {
    auto* path = static_cast<char*>(data);
    record(path, "end");
    std::free(path);
}
void freeReplies(pam_response* replies, int count) {
    if (!replies) return;
    for (int i = 0; i < count; ++i) if (replies[i].resp) {
        explicit_bzero(replies[i].resp, std::strlen(replies[i].resp));
        std::free(replies[i].resp);
    }
    std::free(replies);
}
}

extern "C" int pam_sm_authenticate(pam_handle_t* pam, int, int argc, const char** argv) {
    record(logPath(argc, argv), "authenticate");
    if (const char* path = logPath(argc, argv)) {
        char* copy = ::strdup(path);
        if (!copy) return PAM_BUF_ERR;
        if (pam_set_data(pam, "zestify-test-log", copy, cleanup) != PAM_SUCCESS) {
            std::free(copy);
            return PAM_SYSTEM_ERR;
        }
    }
    const void* tty = nullptr;
    if (pam_get_item(pam, PAM_TTY, &tty) != PAM_SUCCESS || !tty || std::strcmp(static_cast<const char*>(tty), "/dev/tty7") != 0)
        return PAM_SYSTEM_ERR;
    const char* type = pam_getenv(pam, "XDG_SESSION_TYPE");
    const char* seat = pam_getenv(pam, "XDG_SEAT");
    const char* vt = pam_getenv(pam, "XDG_VTNR");
    if (!type || std::strcmp(type, "wayland") || !seat || std::strcmp(seat, "seat0") || !vt || std::strcmp(vt, "7"))
        return PAM_SYSTEM_ERR;
    const void* item = nullptr;
    if (pam_get_item(pam, PAM_CONV, &item) != PAM_SUCCESS || !item) return PAM_SYSTEM_ERR;
    const auto* conversation = static_cast<const pam_conv*>(item);
    const pam_message messages[] = {
        {PAM_TEXT_INFO, "Test conversation"}, {PAM_ERROR_MSG, "Test information only"},
        {PAM_PROMPT_ECHO_OFF, "Password"}, {PAM_PROMPT_ECHO_ON, "Verification code"}
    };
    const pam_message* pointers[] = {&messages[0], &messages[1], &messages[2], &messages[3]};
    pam_response* replies = nullptr;
    const int status = conversation->conv(4, pointers, &replies, conversation->appdata_ptr);
    if (status != PAM_SUCCESS) { freeReplies(replies, 4); return status; }
    const bool correct = replies && replies[2].resp && replies[3].resp
        && std::strcmp(replies[2].resp, "test-password") == 0 && std::strcmp(replies[3].resp, "123456") == 0;
    freeReplies(replies, 4);
    if (!correct) return PAM_AUTH_ERR;
    if (option(argc, argv, "rewrite-user")) return pam_set_item(pam, PAM_USER, "mapped-test-user");
    return PAM_SUCCESS;
}
extern "C" int pam_sm_setcred(pam_handle_t*, int flags, int argc, const char** argv) {
    record(logPath(argc, argv), flags & PAM_DELETE_CRED ? "credentials-delete" : "credentials-establish");
    return !(flags & PAM_DELETE_CRED) && option(argc, argv, "credentials-fail") ? PAM_CRED_ERR : PAM_SUCCESS;
}
extern "C" int pam_sm_acct_mgmt(pam_handle_t*, int, int argc, const char** argv) {
    record(logPath(argc, argv), "account");
    if (option(argc, argv, "account-fail")) return PAM_PERM_DENIED;
    return option(argc, argv, "expired") ? PAM_NEW_AUTHTOK_REQD : PAM_SUCCESS;
}
extern "C" int pam_sm_chauthtok(pam_handle_t*, int flags, int argc, const char** argv) {
    record(logPath(argc, argv), flags & PAM_PRELIM_CHECK ? "password-preliminary" : "password-change");
    return PAM_SUCCESS;
}
extern "C" int pam_sm_open_session(pam_handle_t* pam, int, int argc, const char** argv) {
    record(logPath(argc, argv), "session-open");
    if (option(argc, argv, "session-fail")) return PAM_SESSION_ERR;
    return pam_putenv(pam, "ZESTIFY_TEST_ENV=present");
}
extern "C" int pam_sm_close_session(pam_handle_t*, int, int argc, const char** argv) {
    record(logPath(argc, argv), "session-close");
    return PAM_SUCCESS;
}
