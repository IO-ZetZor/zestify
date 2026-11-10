import QtQuick
import QtTest
import "../../shell/components"
import "../../shell/surfaces"

Item {
    id: fixture
    width: 760
    height: 600
    property bool showingPower: false
    property var actions: []
    property var wallpaperCalls: []
    readonly property var collection: [
        {path: "/mountain.jpg", name: "Mountain Dawn.jpg", thumb: "", isVideo: false},
        {path: "/rain.mp4", name: "Mountain Rain.mp4", thumb: "", isVideo: true},
        {path: "/ocean.png", name: "Ocean.png", thumb: "", isVideo: false}
    ]
    Theme { id: fixtureTheme }
    QtObject {
        id: wallpaperService
        property var items: fixture.collection
        property bool busy: false
        property bool listing: false
        property string lastError: ""
        property string current: "/mountain.jpg"
        function currentFor(monitor) { return current; }
        function refresh() {}
        function apply(path, monitor) {
            fixture.wallpaperCalls = fixture.wallpaperCalls.concat([{path: path, monitor: monitor}]);
            busy = true;
        }
        function applyAll(path) { apply(path, "all"); }
        function random(monitor) { apply("random", monitor); }
    }
    WallpaperStudio {
        id: studio
        anchors.fill: parent
        theme: fixtureTheme
        screen: ({name: "eDP-1"})
        wallpapers: wallpaperService
        folder: "~/Pictures/Wallpapers"
        visible: !fixture.showingPower
    }
    Row {
        id: power
        visible: fixture.showingPower
        spacing: 8
        Repeater {
            model: ["lock", "restart", "shutdown"]
            delegate: PowerAction {
                required property string modelData
                width: 200
                height: 160
                theme: fixtureTheme
                action: modelData
                label: modelData
                confirm: modelData !== "lock"
                holdMs: 160
                onTriggered: action => fixture.actions = fixture.actions.concat([action])
            }
        }
    }
    TestCase {
        name: "PowerWallpaperUI"
        when: windowShown

        function tile(action, item) {
            item = item || power;
            if (item.action === action)
                return item;
            for (const child of item.children || []) {
                const found = tile(action, child);
                if (found) return found;
            }
            return null;
        }
        function init() {
            fixture.width = 760;
            fixture.height = 600;
            fixture.showingPower = false;
            fixture.actions = [];
            fixture.wallpaperCalls = [];
            studio.s = 1;
            studio.selectedPath = "";
            studio.query = "";
            studio.mediaFilter = "all";
            studio.allMonitors = false;
            wallpaperService.items = fixture.collection;
            wallpaperService.busy = false;
            wallpaperService.listing = false;
            wallpaperService.lastError = "";
            wait(30);
        }
        function test_search_filters_and_keyboard_selection() {
            const search = findChild(studio, "wallpaperSearch");
            const grid = findChild(studio, "wallpaperGrid");
            mouseClick(search);
            for (const character of "mountain") keyClick(character);
            compare(studio.filteredItems.length, 2);
            keyClick(Qt.Key_Down);
            compare(studio.selectedPath, "/mountain.jpg");
            keyClick(Qt.Key_Right);
            compare(studio.selectedPath, "/rain.mp4");
            keyClick(Qt.Key_Return);
            compare(fixture.wallpaperCalls.length, 1);
            compare(fixture.wallpaperCalls[0].monitor, "eDP-1");
            verify(!findChild(studio, "applyWallpaper").enabled);
            keyClick(Qt.Key_Left);
            compare(studio.selectedPath, "/rain.mp4");
            keyClick(Qt.Key_Return);
            compare(fixture.wallpaperCalls.length, 1);
            wallpaperService.busy = false;
            studio.mediaFilter = "images";
            compare(studio.filteredItems.length, 1);
            studio.query = "missing";
            compare(studio.filteredItems.length, 0);
            compare(grid.count, 0);
        }
        function test_target_and_removed_selection() {
            studio.selectedPath = "/ocean.png";
            mouseClick(findChild(studio, "allMonitors"));
            verify(studio.allMonitors);
            mouseClick(findChild(studio, "applyWallpaper"));
            compare(fixture.wallpaperCalls[0].monitor, "all");
            wallpaperService.busy = false;
            wallpaperService.items = [fixture.collection[0]];
            verify(!studio.canApply);
            studio.applySelected(true);
            compare(fixture.wallpaperCalls.length, 1);
        }
        function test_thumbnail_background_is_translucent_and_hover_is_accented() {
            const card = findChild(studio, "wallpaperCard0");
            verify(card !== null);
            mouseMove(fixture, 750, 590);
            wait(200);
            verify(card.color.a < 0.1);
            const normal = String(card.color);
            mouseMove(card, 20, 20);
            wait(200);
            verify(String(card.color) !== normal);
            verify(card.color.a > 0.15 && card.color.a < 0.25);
            mouseMove(fixture, 750, 590);
            wait(200);
            compare(String(card.color), normal);
        }
        function test_empty_loading_error_and_responsive_columns() {
            fixture.width = 480;
            wait(30);
            compare(studio.columns, 2);
            fixture.width = 320;
            wait(30);
            compare(studio.columns, 1);
            wallpaperService.items = [];
            wallpaperService.listing = true;
            verify(!findChild(studio, "randomWallpaper").enabled);
            verify(!studio.canApply);
            wallpaperService.listing = false;
            wallpaperService.lastError = "Could not read wallpaper folder";
            compare(studio.error, wallpaperService.lastError);
            verify(!studio.canApply);
        }
        function test_power_click_and_short_hold_cancel() {
            fixture.showingPower = true;
            fixture.width = 660;
            fixture.height = 420;
            wait(30);
            const lock = tile("lock");
            const restart = tile("restart");
            verify(lock !== null && restart !== null);
            mouseClick(lock);
            compare(fixture.actions[0], "lock");
            mousePress(restart);
            wait(60);
            verify(restart.progress > 0);
            mouseRelease(restart);
            wait(190);
            compare(fixture.actions.length, 1);
            compare(restart.progress, 0);
            mousePress(restart);
            mouseMove(restart, -10, -10, 20, Qt.LeftButton);
            wait(190);
            mouseRelease(restart, -10, -10);
            compare(fixture.actions.length, 1);
        }
        function test_power_full_hold_fires_once_and_keyboard_cancel() {
            fixture.showingPower = true;
            fixture.width = 660;
            fixture.height = 420;
            wait(30);
            const shutdown = tile("shutdown");
            mousePress(shutdown);
            tryCompare(fixture, "actions", ["shutdown"], 500);
            wait(200);
            compare(fixture.actions.length, 1);
            mouseRelease(shutdown);
            shutdown.forceActiveFocus();
            keyPress(Qt.Key_Space);
            wait(60);
            keyRelease(Qt.Key_Space);
            wait(190);
            compare(fixture.actions.length, 1);
            keyPress(Qt.Key_Space);
            tryCompare(fixture, "actions", ["shutdown", "shutdown"], 500);
            keyRelease(Qt.Key_Space);
        }
        function test_power_release_after_focus_transfer_does_not_trigger() {
            fixture.showingPower = true;
            wait(30);
            const restart = tile("restart");
            const lock = tile("lock");
            restart.forceActiveFocus();
            keyPress(Qt.Key_Space);
            wait(30);
            lock.forceActiveFocus();
            keyRelease(Qt.Key_Space);
            wait(190);
            compare(fixture.actions.length, 0);
            compare(restart.progress, 0);
            keyClick(Qt.Key_Space);
            compare(fixture.actions[0], "lock");
        }
    }
}
