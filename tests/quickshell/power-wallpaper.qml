import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/surfaces"

ShellRoot {
    id: root
    property int phase: 0
    property var powerCalls: []
    readonly property string outputDir: Quickshell.env("POWER_WALLPAPER_PREVIEW")
    readonly property var thumbs: JSON.parse(Quickshell.env("POWER_WALLPAPER_THUMBS") || "[]")
    readonly property var collection: [
        {path: "/mountain.jpg", name: "Mountain Dawn.jpg", thumb: thumbs[0] || "", isVideo: false},
        {path: "/rain.mp4", name: "Mountain Rain.mp4", thumb: thumbs[1] || "", isVideo: true},
        {path: "/ocean.png", name: "Ocean.png", thumb: thumbs[2] || "", isVideo: false},
        {path: "/forest.jpg", name: "Forest light.jpg", thumb: thumbs[3] || thumbs[0] || "", isVideo: false},
        {path: "/city.mp4", name: "City after hours.mp4", thumb: thumbs[4] || thumbs[1] || "", isVideo: true},
        {path: "/sky.jpg", name: "A very long wallpaper filename at sunset.jpg", thumb: thumbs[5] || thumbs[2] || "", isVideo: false}
    ]
    Theme { id: fixtureTheme }
    QtObject {
        id: wallpapers
        property var items: root.collection
        property bool busy: false
        property bool listing: false
        property string lastError: ""
        function currentFor(monitor) { return "/mountain.jpg"; }
        function refresh() {}
        function apply(path, monitor) {}
        function applyAll(path) {}
        function random(monitor) {}
    }
    Window {
        id: wallpaperWindow
        visible: true
        width: 760
        height: 600
        color: fixtureTheme.surface
        Rectangle { anchors.fill: parent; color: fixtureTheme.surface }
        SurfaceFrame {
            id: wallpaperFrame
            anchors.fill: parent
            theme: fixtureTheme
            title: "Wallpaper"
            WallpaperStudio {
                id: studio
                anchors.fill: parent
                theme: fixtureTheme
                s: wallpaperFrame.s
                screen: ({name: "eDP-1"})
                wallpapers: wallpapers
                folder: "~/Pictures/Wallpapers"
                selectedPath: "/rain.mp4"
            }
        }
    }
    Window {
        id: powerWindow
        visible: true
        width: 660
        height: 420
        color: fixtureTheme.surface
        Rectangle { anchors.fill: parent; color: fixtureTheme.surface }
        Power {
            id: power
            anchors.fill: parent
            theme: fixtureTheme
            // Every action stays inside this fixture, including shutdown.
            function runAction(action) { root.powerCalls = root.powerCalls.concat([action]); }
        }
    }
    function actions(item, result) {
        if (item.action !== undefined && item.holdMs !== undefined)
            result.push(item);
        for (const child of item.children || []) root.actions(child, result);
    }
    function childNamed(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = root.childNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    function checkLayout() {
        const tiles = [];
        root.actions(power, tiles);
        if (tiles.length !== 5) throw new Error("Missing power actions");
        for (const tile of tiles) {
            const point = tile.mapToItem(power, 0, 0);
            if (tile.width < 60 || tile.height < 80 || point.x < 0 || point.y < 0
                || point.x + tile.width > power.width + 1 || point.y + tile.height > power.height + 1)
                throw new Error("Power action is clipped: " + tile.action);
        }
        const apply = root.childNamed(studio, "applyWallpaper");
        const point = apply.mapToItem(studio, 0, 0);
        if (point.x < 0 || point.x + apply.width > studio.width + 1 || point.y + apply.height > studio.height + 1)
            throw new Error("Wallpaper Apply control is clipped");
        if (root.phase === 0) {
            for (const tile of tiles) tile.triggered(tile.action);
            if (root.powerCalls.join(",") !== "lock,sleep,logout,restart,shutdown")
                throw new Error("Power action dispatch is disconnected");
        }
    }
    function next() {
        root.phase++;
        if (root.phase === 1) {
            wallpaperWindow.width = 480;
            powerWindow.width = 420;
        } else if (root.phase === 2) {
            fixtureTheme.mode = "light";
            wallpaperWindow.width = 760;
            powerWindow.width = 660;
        } else if (root.phase === 3) {
            wallpaperWindow.width = 950;
            wallpaperWindow.height = 750;
            wallpaperFrame.s = 1.25;
            powerWindow.width = 825;
            powerWindow.height = 525;
            power.s = 1.25;
        } else if (root.phase === 4) {
            wallpaperWindow.width = 320;
            wallpaperWindow.height = 600;
            wallpaperFrame.s = 1;
            powerWindow.width = 660;
            powerWindow.height = 420;
            power.s = 1;
            wallpapers.items = [];
            wallpapers.lastError = "Could not read wallpaper folder. Check the folder in Settings and refresh.";
        } else {
            console.log("POWER WALLPAPER PASS: integrated actions, normal/narrow/scaled layouts, dark/light and empty/error previews");
            Qt.quit();
            return;
        }
        captureTimer.start();
    }
    Timer {
        id: captureTimer
        interval: 250
        running: true
        onTriggered: {
            try {
                root.checkLayout();
                powerWindow.contentItem.grabToImage(result => {
                    if (!result.saveToFile(root.outputDir + "/power-" + root.phase + ".png")) {
                        console.error("POWER WALLPAPER FAIL: Could not save power preview");
                        Qt.quit();
                        return;
                    }
                    wallpaperWindow.contentItem.grabToImage(wallpaperResult => {
                        if (!wallpaperResult.saveToFile(root.outputDir + "/wallpaper-" + root.phase + ".png")) {
                            console.error("POWER WALLPAPER FAIL: Could not save wallpaper preview");
                            Qt.quit();
                            return;
                        }
                        root.next();
                    });
                });
            } catch (error) {
                console.error("POWER WALLPAPER FAIL: " + error);
                Qt.quit();
            }
        }
    }
}
