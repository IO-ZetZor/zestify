import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/surfaces"

ShellRoot {
    id: root
    property int phase: 0
    property var powerCalls: []
    property int animationFrame: -1
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
        function preview(item, monitor) {}
        function clearPreview(monitor) {}
        function apply(path, monitor) {}
        function applyAll(path) {}
        function random(monitor) {}
    }
    Window {
        id: wallpaperWindow
        visible: true
        width: 1920
        height: 320
        color: fixtureTheme.surface
        Rectangle { anchors.fill: parent; color: fixtureTheme.surface }
        WallpaperStudio {
            id: studio
            anchors.fill: parent
            anchors.margins: 8 * s
            theme: fixtureTheme
            screen: ({name: "eDP-1"})
            wallpapers: wallpapers
            folder: "~/Pictures/Wallpapers"
            selectedPath: "/rain.mp4"
        }
    }

    Window {
        id: powerWindow
        visible: true
        width: 1000
        height: 700
        color: fixtureTheme.surface
        Rectangle { anchors.fill: parent; color: fixtureTheme.surface }
        PowerDrawer {
            id: powerDrawer
            anchors.fill: parent
            theme: fixtureTheme
            Component.onCompleted: open()
            Power {
                id: power
                anchors.fill: parent
                theme: fixtureTheme
                s: powerDrawer.s
                // Every action stays inside this fixture, including shutdown.
                function runAction(action) { root.powerCalls = root.powerCalls.concat([action]); }
            }
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
        if (powerDrawer.settling || !power.enabled)
            throw new Error("Power drawer did not settle open");
        const animation = root.childNamed(power, "powerRemAnimation");
        if (!animation || animation.status !== Image.Ready || animation.frameCount < 2 || !animation.playing)
            throw new Error("Bundled Rem GIF did not load and play");
        if (animation.sourceSize.width < 1280 || animation.sourceSize.height < 716)
            throw new Error("Rem GIF was decoded below its full resolution");
        if (root.phase === 0) root.animationFrame = animation.currentFrame;
        if (root.phase === 1 && animation.currentFrame === root.animationFrame)
            throw new Error("Rem GIF did not advance frames");
        const tiles = [];
        root.actions(power, tiles);
        if (tiles.length !== 5) throw new Error("Missing power actions");
        for (const tile of tiles) {
            const point = tile.mapToItem(power, 0, 0);
            if (tile.width < 60 || tile.height < 80 || point.x < 0 || point.y < 0
                || point.x + tile.width > power.width + 1 || point.y + tile.height > power.height + 1)
                throw new Error("Power action is clipped: " + tile.action);
        }
        const orbit = root.childNamed(studio, "wallpaperOrbit");
        if (root.phase < 4 && orbit.count !== root.collection.length)
            throw new Error("Wallpaper collection lost image/video entries");
        const hero = root.childNamed(studio, "wallpaperHero");
        if (Math.abs(hero.width - hero.height) > 0.01)
            throw new Error("Wallpaper preview must be circular");
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
            root.childNamed(power, "powerRemControl").angle = 60;
        } else if (root.phase === 2) {
            fixtureTheme.mode = "light";
            wallpaperWindow.width = 1920;
            powerWindow.width = 1000;
            root.childNamed(power, "powerRemControl").angle = 180;
        } else if (root.phase === 3) {
            wallpaperWindow.width = 2400;
            wallpaperWindow.height = 400;
            studio.s = 1.25;
            powerWindow.width = 1250;
            powerWindow.height = 875;
            powerDrawer.s = 1.25;
            root.childNamed(power, "powerRemControl").angle = 90;
        } else if (root.phase === 4) {
            wallpaperWindow.width = 320;
            wallpaperWindow.height = 320;
            studio.s = 1;
            powerWindow.width = 1000;
            powerWindow.height = 700;
            powerDrawer.s = 1;
            root.childNamed(power, "powerRemControl").angle = 0;
            wallpapers.items = [];
            wallpapers.lastError = "Could not read wallpaper folder. Check the folder in Settings and refresh.";
        } else if (root.phase === 5) {
            powerDrawer.close();
        }
        captureTimer.start();
    }
    Timer {
        id: captureTimer
        interval: 900
        running: true
        onTriggered: {
            try {
                if (root.phase === 5) {
                    const animation = root.childNamed(power, "powerRemAnimation");
                    if (powerDrawer.active || animation.playing)
                        throw new Error("Hidden power drawer kept playing the Rem GIF");
                    if (root.childNamed(power, "powerRemControl").angle !== 0)
                        throw new Error("Hidden power portrait did not reset its rotation");
                    console.log("POWER WALLPAPER PASS: integrated actions, normal/narrow/scaled layouts, dark/light and empty/error previews, full-resolution Rem GIF, rotated portraits and hidden pause");
                    Qt.quit();
                    return;
                }
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
