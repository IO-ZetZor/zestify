import QtQuick
import QtTest
import "../../shell/components"
import "../../shell/surfaces"

Item {
    id: fixture
    width: 760
    height: 320
    property bool showingPower: false
    property var actions: []
    property var wallpaperCalls: []
    property var previews: []
    property int previewClears: 0
    readonly property var collection: [
        {path: "/mountain.jpg", name: "Mountain Dawn.jpg", thumb: "", isVideo: false},
        {path: "/rain.mp4", name: "Mountain Rain.mp4", thumb: "", isVideo: true},
        {path: "/ocean.png", name: "Ocean.png", thumb: "", isVideo: false},
        {path: "/forest.png", name: "Forest.png", thumb: "", isVideo: false},
        {path: "/dusk.png", name: "Dusk.png", thumb: "", isVideo: false},
        {path: "/dawn.png", name: "Dawn.png", thumb: "", isVideo: false}
    ]
    Theme { id: fixtureTheme }
    Component {
        id: startupStudioComponent
        WallpaperStudio {
            theme: fixtureTheme
            wallpapers: wallpaperService
            screen: ({name: "eDP-1"})
        }
    }
    QtObject {
        id: wallpaperService
        property var items: fixture.collection
        property bool busy: false
        property bool listing: false
        property string lastError: ""
        property string previewError: ""
        property string current: "/mountain.jpg"
        function currentFor(monitor) { return current; }
        function refresh() {}
        function preview(item, monitor) { fixture.previews = fixture.previews.concat([{path: item.path, monitor: monitor}]); }
        function clearPreview(monitor) { fixture.previewClears++; }
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
    SignalSpy { id: applying; target: studio; signalName: "applyRequested" }
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
                compact: true
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
            fixture.height = 320;
            fixture.showingPower = false;
            fixture.actions = [];
            fixture.wallpaperCalls = [];
            applying.clear();
            studio.s = 1;
            studio.browsed = false;
            studio.selectedPath = "";
            studio.previewEnabled = true;
            fixture.previews = [];
            fixture.previewClears = 0;
            wallpaperService.items = fixture.collection;
            wallpaperService.busy = false;
            wallpaperService.listing = false;
            wallpaperService.lastError = "";
            wallpaperService.current = "/mountain.jpg";
            mouseMove(fixture, -5, -5);
            wait(30);
            studio.openAtCurrent();
        }
        function test_circular_collection_keyboard_preview_and_apply() {
            const orbit = findChild(studio, "wallpaperOrbit");
            compare(orbit.count, fixture.collection.length);
            compare(studio.selectedPath, "/mountain.jpg");
            verify(orbit.activeFocus);
            keyClick(Qt.Key_Right);
            compare(studio.selectedPath, "/rain.mp4");
            compare(fixture.wallpaperCalls.length, 0);
            compare(fixture.previews[0].monitor, "eDP-1");
            keyClick(Qt.Key_Return);
            compare(applying.count, 1);
            compare(fixture.wallpaperCalls[0].monitor, "eDP-1");
            keyClick(Qt.Key_Right);
            compare(studio.selectedPath, "/rain.mp4", "Applying must block further selection");
            keyClick(Qt.Key_Return);
            compare(applying.count, 1, "Busy Enter must not restart dismissal");
            wallpaperService.busy = false;
            keyClick(Qt.Key_Return, Qt.ShiftModifier);
            compare(fixture.wallpaperCalls[1].monitor, "all");
        }
        function test_mouse_selection_does_not_apply_or_change_on_hover() {
            const card = findChild(studio, "wallpaperCard1");
            verify(card !== null);
            mouseMove(card, 20, 20);
            compare(studio.selectedPath, "/mountain.jpg");
            mouseClick(card, 20, 20);
            compare(studio.selectedPath, "/rain.mp4");
            compare(fixture.wallpaperCalls.length, 0);
            const apply = findChild(studio, "wallpaperApply");
            mouseClick(apply);
            compare(fixture.wallpaperCalls[0].path, "/rain.mp4");
        }
        function test_wheel_browses_and_wraps() {
            mouseWheel(studio, 100, 100, 0, -120, Qt.NoButton);
            compare(studio.selectedPath, "/rain.mp4");
            mouseWheel(studio, 100, 100, 120, 0, Qt.NoButton);
            compare(studio.selectedPath, "/mountain.jpg");
            keyClick(Qt.Key_Left);
            compare(studio.selectedPath, "/dawn.png");
            keyClick(Qt.Key_Right);
            compare(studio.selectedPath, "/mountain.jpg");
        }
        function test_close_removed_selection_and_loading_errors() {
            studio.selectIndex(2);
            wallpaperService.items = [fixture.collection[0]];
            compare(studio.selectedPath, "");
            verify(!studio.canApply);
            verify(fixture.previewClears > 0);
            wallpaperService.items = [];
            wallpaperService.listing = true;
            verify(findChild(studio, "wallpaperStatus").visible);
            verify(findChild(studio, "wallpaperStatus").text.includes("Finding"));
            wallpaperService.lastError = "Could not read wallpaper folder";
            compare(findChild(studio, "wallpaperStatus").text, wallpaperService.lastError);
            studio.previewEnabled = false;
            const cleared = fixture.previewClears;
            verify(cleared > 0);
            studio.selectIndex(0);
            compare(fixture.wallpaperCalls.length, 0);
        }
        function test_applied_opens_selected_and_reopening_tracks_new_current() {
            wallpaperService.current = "/dusk.png";
            wait(30);
            compare(studio.items[0].path, "/dusk.png");
            compare(studio.selectedPath, "/dusk.png");
            studio.selectIndex(1);
            const selected = studio.selectedPath;
            wallpaperService.current = "/rain.mp4";
            wait(30);
            compare(studio.items[0].path, "/dusk.png");
            compare(studio.selectedPath, selected);
            studio.previewEnabled = false;
            studio.previewEnabled = true;
            wait(30);
            compare(studio.selectedPath, "/rain.mp4");
        }
        function test_late_collection_and_large_collection_are_bounded() {
            wallpaperService.items = [];
            wallpaperService.current = "/ocean.png";
            studio.previewEnabled = false;
            studio.previewEnabled = true;
            wait(30);
            wallpaperService.items = fixture.collection;
            wait(30);
            compare(studio.selectedPath, "/ocean.png");
            const many = [];
            for (let i = 0; i < 500; i++) many.push({path: "/wall-" + i + ".png", name: "Wallpaper " + i, thumb: ""});
            wallpaperService.items = many;
            wait(30);
            const orbit = findChild(studio, "wallpaperOrbit");
            compare(orbit.count, 500);
            compare(orbit.pathItemCount, 9);
            studio.selectIndex(499);
            keyClick(Qt.Key_Right);
            compare(studio.selectedPath, "/wall-0.png");
        }
        function test_circle_layout_fits_narrow_and_scaled_sizes() {
            const hero = findChild(studio, "wallpaperHero");
            for (const size of [Qt.size(320, 420), Qt.size(760, 680), Qt.size(950, 800)]) {
                fixture.width = size.width;
                fixture.height = size.height;
                studio.s = 1.5;
                wait(30);
                compare(hero.width, hero.height);
                const point = hero.mapToItem(studio, 0, 0);
                verify(point.x >= 0 && point.y >= 0);
                verify(point.x + hero.width <= studio.width && point.y + hero.height <= studio.height);
                const apply = findChild(studio, "wallpaperApplyAll");
                const bottom = apply.mapToItem(studio, apply.width, apply.height);
                verify(bottom.x <= studio.width && bottom.y <= studio.height);
            }
        }
        function test_grid_labels_and_buttons_are_centered() {
            for (const size of [Qt.size(320, 420), Qt.size(760, 700), Qt.size(950, 800)]) {
                fixture.width = size.width;
                fixture.height = size.height;
                studio.s = 1.5;
                wait(60);
                for (const name of ["wallpaperGrid", "wallpaperName", "wallpaperApplyButtons", "wallpaperHelp"]) {
                    const item = findChild(studio, name);
                    const center = item.mapToItem(studio, item.width / 2, 0);
                    fuzzyCompare(center.x, studio.width / 2, 0.5);
                }
                const first = findChild(studio, "wallpaperCard0");
                const help = findChild(studio, "wallpaperHelp");
                const top = first.mapToItem(studio, 0, 0).y;
                const bottom = help.mapToItem(studio, 0, help.height).y;
                fuzzyCompare((top + bottom) / 2, studio.height / 2, 4);
            }
        }
        function test_thumbnails_fade_when_entering_both_edges() {
            fixture.width = 760;
            fixture.height = 700;
            const many = [];
            for (let i = 0; i < 30; i++) many.push({path: "/entry-" + i + ".png", name: "Entry " + i,
                thumb: String(Qt.resolvedUrl("../fixtures/album-cover.svg")), isVideo: false});
            wallpaperService.items = many;
            wait(200);
            studio.selectIndex(0);
            const orbit = findChild(studio, "wallpaperOrbit");
            tryCompare(findChild(studio, "wallpaperCard0"), "opacity", 1);
            const enteringIndex = orbit.pathItemCount;
            studio.moveSelection(1);
            tryVerify(() => {
                const item = findChild(studio, "wallpaperCard" + enteringIndex);
                return item !== null && item.onOrbit;
            });
            const entering = findChild(studio, "wallpaperCard" + enteringIndex);
            verify(entering.opacity < 0.95, "New edge thumbnail appeared fully opaque");
            tryCompare(entering, "opacity", 1, 1200);
            tryCompare(findChild(studio, "wallpaperCard1"), "opacity", 1);
            studio.moveSelection(-1);
            tryVerify(() => {
                const item = findChild(studio, "wallpaperCard0");
                return item !== null && item.onOrbit && item.opacity > 0 && item.opacity < 0.95;
            }, 1200);
            tryCompare(findChild(studio, "wallpaperCard0"), "opacity", 1, 1200);
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
