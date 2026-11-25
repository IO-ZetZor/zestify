import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 1000
    height: 700
    property int started: 0
    property int closed: 0
    property var actions: []
    Theme { id: fixtureTheme }
    PowerDrawer {
        id: drawer
        anchors.fill: parent
        theme: fixtureTheme
        onPullStarted: fixture.started++
        onClosed: fixture.closed++
        Item {
            id: power
            anchors.fill: parent
            PowerAction {
                id: restart
                width: 200
                height: 160
                theme: fixtureTheme
                action: "restart"
                label: "Restart"
                confirm: true
                compact: true
                holdMs: 250
                onCloseRequested: drawer.close()
                onTriggered: action => fixture.actions = fixture.actions.concat([action])
            }
        }
    }
    TestCase {
        name: "PowerDrawer"
        when: windowShown
        function init() {
            fixture.width = 1000;
            fixture.height = 700;
            drawer.s = 1;
            drawer.enabled = true;
            drawer.reset();
            fixture.started = 0;
            fixture.closed = 0;
            fixture.actions = [];
            mouseMove(fixture, 900, 100);
            wait(30);
        }
        function test_bottom_drag_tracks_pointer_and_springs_open() {
            const edge = findChild(drawer, "powerDrawerEdge");
            mousePress(edge, 492, 2);
            verify(drawer.dragging);
            compare(fixture.started, 1);
            verify(!power.enabled);
            mouseMove(edge, 492, -278, 200, Qt.LeftButton);
            verify(Math.abs(drawer.pull - 280) < 1);
            mouseRelease(edge, 492, -278);
            verify(drawer.opened);
            verify(drawer.settling);
            let overshot = false;
            for (let i = 0; i < 60 && drawer.settling; i++) {
                wait(16);
                if (drawer.pull > drawer.drawerHeight) overshot = true;
            }
            verify(overshot, "Opening should have a small spring bounce");
            tryCompare(drawer, "settling", false, 1500);
            compare(drawer.pull, drawer.drawerHeight);
            verify(power.enabled);
            compare(fixture.actions.length, 0);
        }
        function test_short_pull_and_interior_click_stay_closed() {
            mouseClick(drawer, 500, 400);
            compare(fixture.started, 0);
            drawer.beginPull(699);
            drawer.updatePull(650);
            wait(120);
            drawer.releasePull(650);
            verify(!drawer.opened);
            tryCompare(drawer, "active", false, 1500);
            compare(drawer.pull, 0);
            compare(fixture.closed, 1);
        }
        function test_top_handle_closes_and_escape_cancels_held_drag() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            const grab = findChild(drawer, "powerDrawerGrab");
            mousePress(grab, 350, 10);
            mouseMove(grab, 350, 330, 200, Qt.LeftButton);
            verify(drawer.dragging);
            verify(drawer.pull < 150);
            mouseRelease(grab, 350, 330);
            verify(!drawer.opened);
            tryCompare(drawer, "active", false, 1500);
            const edge = findChild(drawer, "powerDrawerEdge");
            mousePress(edge, 492, 2);
            mouseMove(edge, 492, -278, 200, Qt.LeftButton);
            keyClick(Qt.Key_Escape);
            mouseRelease(edge, 492, -278);
            tryCompare(drawer, "active", false, 1500);
        }
        function test_outside_escape_and_close_cancel_confirmation_holds() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            restart.forceActiveFocus();
            keyPress(Qt.Key_Space);
            wait(60);
            verify(restart.holding);
            keyClick(Qt.Key_Escape);
            keyRelease(Qt.Key_Space);
            verify(!restart.holding);
            tryCompare(drawer, "active", false, 1500);
            compare(fixture.actions.length, 0);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            mouseClick(drawer, 900, 100);
            tryCompare(drawer, "active", false, 1500);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            restart.forceActiveFocus();
            keyPress(Qt.Key_Space);
            wait(60);
            drawer.close();
            keyRelease(Qt.Key_Space);
            verify(!restart.holding);
            tryCompare(drawer, "active", false, 1500);
            compare(fixture.actions.length, 0);
        }
        function test_disable_resize_and_edge_coexistence() {
            const edge = findChild(drawer, "powerDrawerEdge");
            verify(edge.x >= 6);
            compare(edge.y + edge.height, fixture.height);
            verify(edge.height <= 6);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            fixture.width = 400;
            fixture.height = 500;
            compare(drawer.pull, drawer.drawerHeight);
            verify(drawer.drawerWidth < fixture.width);
            verify(drawer.drawerHeight < fixture.height);
            drawer.beginPull(499);
            fixture.height = 600;
            verify(!drawer.active);
            drawer.open();
            wait(100);
            drawer.enabled = false;
            verify(!drawer.active);
            verify(!restart.holding);
        }
    }
}
