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
    ShortcutDrawer {
        id: drawer
        anchors.fill: parent
        theme: fixtureTheme
        onPullStarted: fixture.started++
        onClosed: fixture.closed++
        ShortcutActions {
            id: shortcuts
            anchors.fill: parent
            theme: fixtureTheme
            s: drawer.s
            onTriggered: action => fixture.actions = fixture.actions.concat([action])
        }
    }
    TestCase {
        name: "ShortcutDrawer"
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
            drawer.recording = false;
            shortcuts.recording = false;
            mouseMove(fixture, 100, 100);
            wait(30);
        }
        function test_right_edge_tracks_left_drag_and_springs_open() {
            const edge = findChild(drawer, "shortcutDrawerEdge");
            mousePress(edge, 2, 340);
            verify(drawer.dragging);
            compare(fixture.started, 1);
            verify(!shortcuts.enabled);
            mouseMove(edge, 2 - drawer.drawerWidth, 340, 200, Qt.LeftButton);
            fuzzyCompare(drawer.pull, drawer.drawerWidth, 1);
            mouseRelease(edge, 2 - drawer.drawerWidth, 340);
            verify(drawer.opened && drawer.settling);
            let overshot = false;
            for (let i = 0; i < 60 && drawer.settling; i++) {
                wait(16);
                if (drawer.pull > drawer.drawerWidth) overshot = true;
            }
            verify(overshot, "Opening should bounce like the power drawer");
            tryCompare(drawer, "settling", false, 1500);
            compare(drawer.pull, drawer.drawerWidth);
            verify(shortcuts.enabled);
            compare(fixture.actions.length, 0);
        }
        function test_short_pull_and_interior_click_do_not_open() {
            mouseClick(drawer, 500, 350);
            compare(fixture.started, 0);
            drawer.beginPull(999);
            drawer.updatePull(980);
            wait(120);
            drawer.releasePull(980);
            verify(!drawer.opened);
            tryCompare(drawer, "active", false, 1500);
            compare(drawer.pull, 0);
            compare(fixture.closed, 1);
        }
        function test_left_handle_closes_and_escape_cancels_drag() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            const grab = findChild(drawer, "shortcutDrawerGrab");
            mousePress(grab, 10, 120);
            mouseMove(grab, 110, 120, 200, Qt.LeftButton);
            verify(drawer.dragging);
            verify(!shortcuts.enabled);
            fuzzyCompare(drawer.pull, 0, 1);
            mouseRelease(grab, 110, 120);
            tryCompare(drawer, "active", false, 1500);
            const edge = findChild(drawer, "shortcutDrawerEdge");
            mousePress(edge, 2, 340);
            mouseMove(edge, 2 - drawer.drawerWidth, 340, 200, Qt.LeftButton);
            keyClick(Qt.Key_Escape);
            mouseRelease(edge, 2 - drawer.drawerWidth, 340);
            tryCompare(drawer, "active", false, 1500);
            compare(fixture.actions.length, 0);
        }
        function test_outside_and_keyboard_escape_dismiss() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            mouseClick(drawer, 500, 350);
            tryCompare(drawer, "active", false, 1500);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            const settings = findChild(shortcuts, "shortcut-config");
            settings.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            tryCompare(drawer, "active", false, 1500);
            compare(fixture.actions.length, 0);
        }
        function test_capture_close_hides_immediately_and_emits_once() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            drawer.close(true);
            verify(!drawer.active && !drawer.settling && !drawer.opened);
            compare(drawer.pull, 0);
            compare(fixture.closed, 1);
            wait(100);
            compare(fixture.closed, 1);
        }
        function test_icons_are_vertical_and_activate_by_mouse_and_keyboard() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            let lastY = -1;
            let lastX = -1;
            for (const action of ["screenshot", "record", "wallpaper", "config", "system"]) {
                const icon = findChild(shortcuts, "shortcut-" + action);
                verify(icon !== null && icon.width > 0);
                const point = icon.mapToItem(shortcuts, 0, 0);
                verify(point.y > lastY);
                if (lastX >= 0) compare(point.x, lastX);
                lastX = point.x;
                lastY = point.y;
                mouseClick(icon);
                compare(fixture.actions[fixture.actions.length - 1], action);
                icon.forceActiveFocus();
                keyClick(Qt.Key_Return);
                compare(fixture.actions[fixture.actions.length - 1], action);
                keyClick(Qt.Key_Space);
                compare(fixture.actions[fixture.actions.length - 1], action);
            }
            compare(fixture.actions.length, 15);
        }
        function test_equal_padding_at_both_scales() {
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            const panel = findChild(drawer, "shortcutDrawerPanel");
            const first = findChild(shortcuts, "shortcut-screenshot");
            const last = findChild(shortcuts, "shortcut-system");
            for (const scale of [1, 1.5]) {
                drawer.s = scale;
                wait(30);
                const topLeft = first.mapToItem(panel, 0, 0);
                const bottomRight = last.mapToItem(panel, last.width, last.height);
                fuzzyCompare(topLeft.x, 16 * scale, 0.1);
                fuzzyCompare(topLeft.y, topLeft.x, 0.1);
                fuzzyCompare(panel.width - bottomRight.x, topLeft.x, 0.1);
                fuzzyCompare(panel.height - bottomRight.y, topLeft.x, 0.1);
            }
        }
        function test_recording_badges_visible_while_open_and_closed() {
            drawer.recording = true;
            shortcuts.recording = true;
            const edgeIndicator = findChild(drawer, "shortcutRecordingIndicator");
            verify(edgeIndicator.visible);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            verify(!edgeIndicator.visible);
            const record = findChild(shortcuts, "shortcut-record");
            verify(record.recordingAction);
            verify(findChild(record, "shortcutRecordingBadge").visible);
            compare(record.Accessible.name, "Stop screen recording");
            drawer.close();
            tryCompare(drawer, "active", false, 1500);
            verify(edgeIndicator.visible);
            drawer.recording = false;
            shortcuts.recording = false;
            verify(!edgeIndicator.visible && !record.recordingAction);
            compare(record.Accessible.name, "Start screen recording");
        }
        function test_resize_disable_and_other_edges() {
            const edge = findChild(drawer, "shortcutDrawerEdge");
            compare(edge.x + edge.width, fixture.width);
            verify(edge.y >= 6 && edge.y + edge.height <= fixture.height - 6);
            verify(edge.width <= 6);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            fixture.height = 240;
            drawer.s = 1.5;
            compare(drawer.pull, drawer.drawerWidth);
            verify(drawer.drawerHeight < fixture.height);
            verify(shortcuts.buttonSize > 0);
            drawer.beginPull(999);
            fixture.width = 900;
            verify(!drawer.active);
            drawer.open();
            wait(100);
            drawer.enabled = false;
            verify(!drawer.active && !shortcuts.enabled);
        }
    }
}
