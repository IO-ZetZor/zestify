import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 420
    height: 420
    property int dismissed: 0
    property int expired: 0
    property string activated: ""
    Theme { id: fixtureTheme }
    Component {
        id: cardComponent
        NotificationCard {
            width: 360
            height: implicitHeight
            theme: fixtureTheme
            onDismissed: fixture.dismissed++
            onExpired: fixture.expired++
            onActionActivated: identifier => fixture.activated = identifier
        }
    }
    TestCase {
        name: "NotificationUI"
        when: windowShown
        function entry(timeout) {
            return {id: 1, appName: "Test", summary: "A long notification title that wraps across the card",
                body: "<b>Notification body</b> with a second line", urgency: "normal", time: Date.now(), expires: timeout, notification: null};
        }
        function init() {
            fixture.dismissed = 0;
            fixture.expired = 0;
            fixture.activated = "";
            mouseMove(fixture, 400, 400);
        }
        function test_hover_pauses_timeout_and_resumes_remaining_time() {
            const card = createTemporaryObject(cardComponent, fixture, {entry: entry(350), popup: true});
            verify(card !== null);
            wait(80);
            mouseMove(card, 20, 20);
            tryCompare(card, "hovered", true);
            const remaining = card.progress;
            wait(400);
            compare(fixture.expired, 0);
            compare(card.progress, remaining);
            mouseMove(fixture, 400, 400);
            tryCompare(fixture, "expired", 1, 500);
        }
        function test_persistent_popup_and_history_do_not_expire() {
            const card = createTemporaryObject(cardComponent, fixture, {entry: entry(0), popup: true});
            const history = createTemporaryObject(cardComponent, fixture, {entry: entry(50), popup: false, y: 180});
            wait(160);
            compare(fixture.expired, 0);
            mouseClick(findChild(card, "dismissNotification"));
            compare(fixture.dismissed, 1);
        }
        function test_default_action_and_critical_style() {
            const data = entry(0);
            data.urgency = "critical";
            data.notification = {actions: [{identifier: "default", text: "Open"}, {identifier: "reply", text: "Reply"}]};
            const card = createTemporaryObject(cardComponent, fixture, {entry: data, popup: true});
            verify(card.critical);
            compare(String(card.accent), String(fixtureTheme.danger));
            mouseClick(card, 5, 5);
            compare(fixture.activated, "default");
            compare(fixture.dismissed, 0);
        }
    }
}
