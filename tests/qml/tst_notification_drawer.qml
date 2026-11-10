import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 1000
    height: 700
    property int started: 0
    property int closed: 0
    Theme { id: fixtureTheme }
    NotificationDrawer {
        id: drawer
        anchors.fill: parent
        theme: fixtureTheme
        onPullStarted: fixture.started++
        onClosed: fixture.closed++
        Text { anchors.centerIn: parent; text: "Notifications"; color: fixtureTheme.cream }
    }
    TestCase {
        name: "NotificationDrawer"
        when: windowShown
        function init() {
            fixture.width = 1000;
            fixture.height = 700;
            drawer.enabled = true;
            drawer.reset();
            fixture.started = 0;
            fixture.closed = 0;
            wait(30);
        }
        function test_edge_drag_tracks_pointer_then_bounces_and_settles() {
            const edge = findChild(drawer, "notificationDrawerEdge");
            mousePress(edge, 2, 300);
            verify(drawer.dragging);
            compare(fixture.started, 1);
            mouseMove(edge, 280, 300, 200, Qt.LeftButton);
            verify(Math.abs(drawer.pull - 278) < 1);
            mouseRelease(edge, 280, 300);
            verify(drawer.opened);
            verify(drawer.settling);
            let overshot = false;
            for (let i = 0; i < 60 && drawer.settling; i++) {
                wait(16);
                if (drawer.pull > drawer.drawerWidth) overshot = true;
            }
            verify(overshot, "Opening should have a small spring overshoot");
            tryCompare(drawer, "settling", false, 1200);
            compare(drawer.pull, drawer.drawerWidth);
            verify(drawer.active);
        }
        function test_short_pull_returns_closed_and_does_not_intercept_interior() {
            mousePress(drawer, 100, 300);
            mouseRelease(drawer, 100, 300);
            verify(!drawer.dragging);
            compare(fixture.started, 0);
            drawer.beginPull(2);
            drawer.updatePull(65);
            wait(120); // A held short drag should not count as a flick.
            drawer.releasePull(65);
            verify(!drawer.opened);
            tryCompare(drawer, "active", false, 1200);
            compare(drawer.pull, 0);
            compare(fixture.closed, 1);
        }
        function test_right_handle_drag_closes_and_escape_and_outside_dismiss() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            const grab = findChild(drawer, "notificationDrawerGrab");
            mousePress(grab, 10, 300);
            mouseMove(grab, -260, 300, 200, Qt.LeftButton);
            mouseRelease(grab, -260, 300);
            verify(!drawer.opened);
            tryCompare(drawer, "active", false, 1500);
            drawer.open();
            wait(150);
            keyClick(Qt.Key_Escape);
            tryCompare(drawer, "active", false, 1500);
            drawer.open();
            wait(150);
            mouseClick(drawer, 800, 300);
            tryCompare(drawer, "active", false, 1500);
        }
        function test_disable_resize_and_top_edge_exclusion() {
            const edge = findChild(drawer, "notificationDrawerEdge");
            verify(edge.y >= 6);
            verify(edge.width <= 6);
            drawer.open();
            wait(100);
            drawer.enabled = false;
            verify(!drawer.active);
            drawer.enabled = true;
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            fixture.width = 340;
            compare(drawer.pull, drawer.drawerWidth);
            verify(drawer.drawerWidth < 340);
            drawer.beginPull(2);
            fixture.width = 400;
            verify(!drawer.active);
        }
    }
}
