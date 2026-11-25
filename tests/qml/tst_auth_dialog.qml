import QtQuick
import QtTest
import "../../shell/components"

TestCase {
    id: test
    name: "AuthDialog"
    width: 640
    height: 520
    when: windowShown

    QtObject {
        id: flow
        property string message: "An application wants administrator privileges."
        property var identities: [{ displayName: "Alice", string: "alice" }, { displayName: "Bob", string: "bob" }]
        property var selectedIdentity: identities[0]
        property bool isResponseRequired: true
        property bool isCompleted: false
        property string inputPrompt: "Password"
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property string submitted: ""
        property bool cancelled: false
        signal authenticationFailed()
        function submit(value) { submitted = value; isResponseRequired = false; }
        function cancelAuthenticationRequest() { cancelled = true; isCompleted = true; }
    }
    AuthDialog { id: dialog; flow: flow; anchors.centerIn: parent; width: 420 }

    function init() {
        dialog.flow = flow;
        dialog.failure = "";
        flow.isCompleted = false;
        flow.isResponseRequired = true;
        flow.responseVisible = false;
        flow.submitted = "";
        flow.cancelled = false;
        flow.selectedIdentity = flow.identities[0];
        dialog.resetResponse();
    }
    function test_submit_clears_and_prevents_duplicate_reply() {
        const input = findChild(dialog, "authResponse");
        input.text = "synthetic test response";
        dialog.submit();
        compare(flow.submitted, "synthetic test response");
        compare(input.text, "");
        input.text = "must not be submitted";
        dialog.submit();
        compare(flow.submitted, "synthetic test response");
    }
    function test_cancel_clears_response() {
        const input = findChild(dialog, "authResponse");
        input.text = "synthetic test response";
        dialog.cancel();
        compare(flow.cancelled, true);
        compare(input.text, "");
    }
    function test_identity_change_and_failure_clear_response() {
        const input = findChild(dialog, "authResponse");
        input.text = "old identity response";
        flow.selectedIdentity = flow.identities[1];
        compare(input.text, "");
        input.text = "failed response";
        flow.authenticationFailed();
        compare(input.text, "");
        compare(dialog.failure, "Authentication failed. Try again.");
    }
    function test_echo_and_completed_state() {
        const input = findChild(dialog, "authResponse");
        compare(input.echoMode, TextInput.Password);
        flow.responseVisible = true;
        compare(input.echoMode, TextInput.Normal);
        input.text = "synthetic test response";
        flow.isCompleted = true;
        compare(input.text, "");
        compare(input.enabled, false);
    }
    function test_flow_replacement_clears_response() {
        const input = findChild(dialog, "authResponse");
        input.text = "old request response";
        dialog.flow = null;
        compare(input.text, "");
        compare(input.enabled, false);
    }
}
