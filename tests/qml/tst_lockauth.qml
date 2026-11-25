import QtQuick
import QtTest
import "../../shell/components"

Item {
    width: 960
    height: 720

    QtObject {
        id: mockPam
        property bool active: false
        property bool responseRequired: false
        property bool responseVisible: false
        property bool messageIsError: false
        property string message: "Password:"
        property bool startOk: true
        property var responses: []
        function start() { active = startOk; return startOk; }
        function abort() { active = false; responseRequired = false; }
        function respond(value) {
            responses = responses.concat([value]);
            // Real PamContext leaves this true until its next message.
        }
        function challenge(text, visible) {
            message = text;
            responseVisible = visible;
            responseRequired = true;
            flow.message();
        }
    }

    LockAuth { id: flow; pam: mockPam; available: true }
    LockScreenFace {
        id: face
        anchors.fill: parent
        s: 0.75
        locked: true
        handoffProgress: 1
        userName: "Zestify"
        auth: flow
    }

    TestCase {
        name: "NativeLockAuth"
        when: windowShown
        SignalSpy { id: success; target: flow; signalName: "authenticated" }

        function input() { return findChild(face, "lockResponse"); }
        function init() {
            flow.clear();
            flow.available = true;
            face.authActive = true;
            mockPam.startOk = true;
            mockPam.responseVisible = false;
            mockPam.responses = [];
            success.clear();
            face.focusResponse();
        }
        function startAttempt(value) {
            flow.submit(value);
            verify(flow.busy);
            mockPam.challenge("Password:", false);
        }
        function test_only_current_success_can_unlock() {
            flow.complete(true, "");
            compare(success.count, 0);
            startAttempt("test-response");
            mockPam.active = false;
            flow.complete(true, "");
            compare(success.count, 1);
            compare(flow.pendingResponse, "");
            verify(!flow.attemptActive);
        }
        function test_failed_and_unavailable_auth_stay_locked() {
            startAttempt("wrong");
            flow.complete(false, "Authentication failed");
            compare(success.count, 0);
            verify(flow.failed);
            compare(flow.pendingResponse, "");
            mockPam.startOk = false;
            flow.submit("retry");
            verify(flow.failed);
            verify(!flow.busy);
            compare(success.count, 0);
        }
        function test_one_response_per_prompt_and_mfa() {
            startAttempt("password");
            compare(mockPam.responses.length, 1);
            verify(flow.busy);
            flow.submit("duplicate");
            compare(mockPam.responses.length, 1);
            mockPam.challenge("One-time code:", true);
            verify(!flow.busy);
            verify(flow.responseVisible);
            compare(flow.prompt, "One-time code:");
            compare(findChild(face, "lockPrompt").text, "One-time code:");
            verify(findChild(face, "lockPrompt").visible);
            flow.submit("123456");
            compare(mockPam.responses[1], "123456");
            verify(flow.busy);
            flow.complete(true, "");
            compare(success.count, 1);
        }
        function test_cancel_and_lost_security_discard_response() {
            flow.submit("pending");
            flow.clear();
            compare(flow.pendingResponse, "");
            verify(!mockPam.active);
            flow.complete(true, "");
            compare(success.count, 0);
            flow.submit("another");
            flow.available = false;
            compare(flow.pendingResponse, "");
            verify(!mockPam.active);
            flow.complete(true, "");
            compare(success.count, 0);
        }
        function test_secure_enables_keyboard_without_click() {
            flow.available = false;
            input().focus = false;
            flow.available = true;
            tryCompare(input(), "activeFocus", true);
            keyClick(Qt.Key_A);
            compare(input().text, "a");
        }
        function test_enter_clears_input_and_escape_cancels_busy_auth() {
            input().text = "password";
            keyClick(Qt.Key_Return);
            compare(input().text, "");
            verify(flow.busy);
            mockPam.challenge("Password:", false);
            verify(flow.busy);
            keyClick(Qt.Key_Escape);
            verify(!mockPam.active);
            verify(!flow.busy);
            compare(flow.pendingResponse, "");
            compare(success.count, 0);
        }
        function test_switch_output_clears_local_input() {
            input().text = "partial";
            face.authActive = false;
            compare(input().text, "");
            verify(!input().enabled);
            face.authActive = true;
            tryCompare(input(), "activeFocus", true);
        }
        function test_password_dots_fade_without_restarting_existing_dots() {
            compare(input().opacity, 0);
            const cursor = input().cursorDelegate.createObject(input());
            compare(cursor.width, 0);
            compare(cursor.height, 0);
            cursor.destroy();
            keyClick(Qt.Key_A);
            const first = findChild(face, "lockDot0");
            verify(first !== null);
            verify(first.opacity < 1);
            tryCompare(first, "opacity", 1, 500);
            keyClick(Qt.Key_B);
            const second = findChild(face, "lockDot1");
            verify(second !== null);
            verify(second.opacity < 1);
            compare(findChild(face, "lockDot0"), first);
            compare(first.opacity, 1);
            verify(!findChild(face, "lockVisibleResponse").visible);
            tryCompare(second, "opacity", 1, 500);
            keyClick(Qt.Key_Backspace);
            compare(input().text, "a");
            compare(findChild(face, "lockDot1"), null);
            compare(findChild(face, "lockDot0"), first);
            keyClick(Qt.Key_Escape);
            compare(findChild(face, "lockDot0"), null);
            verify(findChild(face, "lockPrompt").visible);
        }
        function test_visible_pam_response_and_bounded_password_dots() {
            input().text = new Array(4097).join("a");
            wait(200);
            const dots = findChild(face, "lockDots");
            verify(dots.children.length <= 65);
            verify(dots.width <= input().parent.width);
            input().clear();
            startAttempt("password");
            mockPam.challenge("One-time code:", true);
            keyClick(Qt.Key_1);
            keyClick(Qt.Key_2);
            compare(findChild(face, "lockVisibleResponse").text, "12");
            verify(findChild(face, "lockVisibleResponse").visible);
            verify(!dots.visible);
            keyClick(Qt.Key_Return);
            compare(mockPam.responses[1], "12");
            compare(input().text, "");
            compare(findChild(face, "lockVisibleResponse").text, "");
        }
    }
}
