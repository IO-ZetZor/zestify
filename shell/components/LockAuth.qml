import QtQuick

// One conversation shared by all outputs. The UI never validates credentials.
Item {
    id: root

    required property var pam
    property bool available: false
    property string pendingResponse: ""
    property bool hasPendingResponse: false
    property bool waitingForInput: false
    property bool attemptActive: false
    property string feedback: ""
    property bool failed: false
    readonly property bool busy: hasPendingResponse || (pam.active && !waitingForInput)
    readonly property string prompt: waitingForInput ? pam.message : "Password"
    readonly property bool responseVisible: waitingForInput && pam.responseVisible

    signal authenticated()
    signal cleared()

    function clear() {
        pendingResponse = "";
        hasPendingResponse = false;
        waitingForInput = false;
        attemptActive = false;
        pam.abort();
        feedback = "";
        failed = false;
        cleared();
    }

    function submit(response) {
        if (!available || busy || !response.length)
            return;
        failed = false;
        feedback = "";
        if (pam.active) {
            if (waitingForInput && pam.responseRequired) {
                waitingForInput = false;
                pam.respond(response);
            }
            return;
        }
        pendingResponse = response;
        hasPendingResponse = true;
        attemptActive = true;
        if (!pam.start())
            complete(false, "Authentication unavailable. Try again.");
    }

    function message() {
        if (!available)
            return;
        waitingForInput = pam.responseRequired;
        if (pam.responseRequired && hasPendingResponse) {
            const response = pendingResponse;
            pendingResponse = "";
            hasPendingResponse = false;
            waitingForInput = false;
            pam.respond(response);
        } else if (!pam.responseRequired) {
            feedback = pam.message;
            failed = pam.messageIsError;
        }
    }

    function complete(success, reason) {
        const canUnlock = available && attemptActive && success;
        pendingResponse = "";
        hasPendingResponse = false;
        waitingForInput = false;
        attemptActive = false;
        pam.abort();
        feedback = success ? "" : reason;
        failed = !success;
        cleared();
        if (canUnlock)
            authenticated();
    }

    onAvailableChanged: if (!available) clear()
    Component.onDestruction: {
        pendingResponse = "";
        pam.abort();
    }
}
