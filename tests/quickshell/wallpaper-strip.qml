import QtQuick
import QtMultimedia
import QtTest
import Quickshell
import "../../shell/components"
import "../../shell/backgrounds"
import "../../shell/singletons"

ShellRoot {
    id: root
    property int phase: 0
    property int requestWaits: 0
    property real livePosition: 0
    property real heroPosition: 0
    property var entryThumbnail: null
    property size entryDecodeSize: Qt.size(0, 0)
    property int decodeChanges: 0
    readonly property var fixtureScreen: Quickshell.screens[0]
    readonly property string screenName: fixtureScreen.name || "fixture"
    readonly property var preview: Wallpapers.previewFor(screenName)
    readonly property var previewScheme: Wallpapers.previewSchemeFor(screenName)
    readonly property string outputDir: Quickshell.env("WALLPAPER_STRIP_PREVIEW")
    readonly property var expected: JSON.parse(Quickshell.env("WALLPAPER_EXPECTED"))
    readonly property var collection: JSON.parse(Quickshell.env("WALLPAPER_COLLECTION"))

    Theme { id: savedTheme }
    Connections {
        target: root.entryThumbnail
        function onSourceSizeChanged() { root.decodeChanges++; }
    }
    Theme {
        id: fixtureTheme
        scheme: root.previewScheme
        mode: Config.theme.mode
        shellAccent: root.previewScheme ? accent : savedTheme.accent
    }
    Window {
        id: window
        visible: true
        width: root.fixtureScreen.width
        height: 600
        color: fixtureTheme.surface
        BackgroundWindow {
            id: nativeBackground
            anchors.fill: parent
            targetScreen: root.fixtureScreen
            wallpaperPath: Wallpapers.currentFor(root.screenName)
            wallpaperThumb: root.collection.find(item => item.path === wallpaperPath)?.thumb || ""
            config: Config
            proxy: null
            effects: WallpaperEffects
            motion: Motion
            holdChanges: pickerPanel.opened
            locked: Session.locked
            dpmsOn: Session.dpmsActive
        }
        WallpaperPreview {
            id: desktopPreview
            anchors.fill: parent
            item: root.preview
            active: !Session.locked && Session.dpmsActive && !pickerPanel.dismissing
        }
        Pill {
            id: pill
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            theme: fixtureTheme
            screen: root.fixtureScreen
            stats: Stats
            players: Players
            wallpapers: Wallpapers
            motion: Motion
        }
    }
    WallpaperPickerWindow {
        id: pickerPanel
        targetScreen: ({name: root.screenName, width: root.fixtureScreen.width})
        theme: fixtureTheme
        motion: Motion
    }
    TestCase {
        id: pickerKeys
        parent: pickerPanel.contentItem
        when: false
        optional: true
        function applyByEnter() {
            root.named(pickerPanel.studio, "wallpaperOrbit").forceActiveFocus();
            keyClick(Qt.Key_Return, Qt.ShiftModifier);
        }
    }
    function named(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = named(child, name);
            if (found) return found;
        }
        return null;
    }
    function check(condition, message) { if (!condition) throw new Error(message); }
    function ready(condition, message) {
        if (condition) {
            root.requestWaits = 0;
            return true;
        }
        tick.interval = 80;
        root.requestWaits++;
        root.check(root.requestWaits < 50, message);
        return false;
    }
    function capture(name, after) {
        (pickerPanel.visible ? pickerPanel.contentItem : window.contentItem).grabToImage(result => {
            root.check(result.saveToFile(root.outputDir + "/" + name + ".png"), "Could not save " + name);
            if (after) after();
        });
    }
    Timer {
        id: tick
        interval: 650
        running: true
        repeat: true
        onTriggered: {
            try {
                if (root.phase === 0) {
                    if (!root.ready(!Wallpapers.busy && Wallpapers.items.length === root.collection.length,
                        "Wallpaper collection did not load")) return;
                    pill.hovered = true;
                    tick.interval = 650;
                } else if (root.phase === 1) {
                    root.capture("hover");
                    root.check(root.named(pill, "pillHoverRow").children.every(child => child.onOpenWallpaper === undefined),
                        "Wallpaper/DND toggles remain in the hover pill");
                    ShellState.open("wallpaper", root.screenName);
                    tick.interval = 70;
                } else if (root.phase === 2) {
                    root.check(pill.surface === "", "Wallpaper must use its own window");
                    root.check(pickerPanel.opened, "Wallpaper window did not open");
                    root.capture("entry");
                    tick.interval = 650;
                } else if (root.phase === 3) {
                    const studio = pickerPanel.studio;
                    root.check(studio !== null, "Picker did not load");
                    const orbit = root.named(studio, "wallpaperOrbit");
                    root.check(orbit.count === root.collection.length, "Image/video collection is incomplete");
                    root.check(orbit.activeFocus, "Opening must focus arrow-key navigation");
                    root.check(studio.selectedPath === Quickshell.env("WALLPAPER_COMMITTED"), "Applied wallpaper must open selected");
                    root.check(orbit.pathItemCount <= 9, "Wallpaper choices must stay bounded");
                    const hero = root.named(studio, "wallpaperHero");
                    root.check(hero.width === hero.height, "Hero preview must be circular");
                    studio.grabToImage(result => {
                        root.check(result.saveToFile(root.outputDir + "/circles.png"), "Could not save circle picker");
                    });
                    root.capture("strip", () => Wallpapers.preview(root.collection[0], root.screenName));
                    tick.interval = 180;
                } else if (root.phase === 4) {
                    if (!root.ready(Wallpapers.previewProcess.running, "Slow preview request was not started")) return;
                    Wallpapers.preview(root.collection[1], root.screenName);
                    tick.interval = 1200;
                } else if (root.phase === 5) {
                    if (!root.ready(Wallpapers.previewScheme !== null,
                        "Preview palette did not load: " + Wallpapers.previewError)) return;
                    root.check(fixtureTheme.c.primary === root.expected.warm, "Stale palette replaced the warm preview");
                    root.check(desktopPreview.image.path === root.collection[1].thumb, "Desktop preview did not change");
                    root.check(Wallpapers.currentFor(root.screenName) === Quickshell.env("WALLPAPER_COMMITTED"),
                        "Preview changed the committed wallpaper");
                    root.check(desktopPreview.image.status === Image.Ready, "Desktop preview image did not load");
                    root.capture("warm", () => Wallpapers.preview(root.collection[2], root.screenName));
                    tick.interval = 650;
                } else if (root.phase === 6) {
                    if (!root.ready(root.previewScheme !== null && fixtureTheme.c.primary === root.expected.gray,
                        "Gray preview palette did not load")) return;
                    root.check(fixtureTheme.c.primary === root.expected.gray, "B&W preview did not recolor the shell");
                    root.check(String(fixtureTheme.shellAccent) === String(fixtureTheme.accent), "Shell accent did not follow preview");
                    root.capture("gray", () => Config.setValue("theme.mode", "light"));
                    Wallpapers.clearPreview("another-display");
                    root.check(Wallpapers.previewItem !== null, "Another display cleared the preview");
                    tick.interval = 650;
                } else if (root.phase === 7) {
                    if (!root.ready(root.previewScheme !== null && fixtureTheme.c.primary === root.expected.grayLight,
                        "Light preview palette did not load")) return;
                    root.check(fixtureTheme.c.primary === root.expected.grayLight, "Theme mode retained the old preview palette");
                    root.capture("light", () => Wallpapers.preview(root.collection[0], root.screenName));
                    root.requestWaits = 0;
                    tick.interval = 80;
                } else if (root.phase === 8) {
                    if (!root.ready(Wallpapers.previewProcess.running,
                        "Exit must be exercised with a request in flight")) return;
                    ShellState.close(root.screenName);
                    root.check(Wallpapers.previewItem === null, "Closing the strip did not release the preview");
                    tick.interval = 1200;
                } else if (root.phase === 9) {
                    root.check(Wallpapers.previewScheme === null, "Late palette result survived close");
                    root.check(desktopPreview.item === null && desktopPreview.video === null, "Closing retained the wallpaper preview");
                    root.check(pill.surface === "" && !pill.morphing, "Pill did not settle closed");
                    Wallpapers.preview(root.collection[1], root.screenName);
                    Session.locked = true;
                    root.check(Wallpapers.previewItem === null, "Locking did not release preview state");
                    Session.locked = false;
                    root.capture("closed");
                    tick.interval = 650;
                } else if (root.phase === 10) {
                    ShellState.open("wallpaper", root.screenName);
                    Qt.callLater(() => {
                        const studio = pickerPanel.studio;
                        studio.selectIndex(studio.items.findIndex(item => item.path === root.collection[3].path));
                    });
                    tick.interval = 200;
                } else if (root.phase === 11) {
                    if (!root.ready(desktopPreview.video !== null && desktopPreview.video.hasFirstFrame,
                        "Live wallpaper preview did not decode a frame")) return;
                    root.check(!desktopPreview.video.failed, "Live wallpaper preview failed");
                    root.check(desktopPreview.video.player.playbackState === MediaPlayer.PlayingState, "Live preview did not play");
                    const hero = root.named(pickerPanel.studio, "wallpaperHeroVideo").item;
                    if (!root.ready(hero !== null && hero.video !== null && hero.video.hasFirstFrame,
                        "Circular live preview did not load")) return;
                    root.check(hero.video.muted && !hero.video.failed, "Circular live preview must play muted");
                    root.heroPosition = hero.video.player.position;
                    root.livePosition = desktopPreview.video.player.position;
                    root.capture("live");
                    tick.interval = 200;
                } else if (root.phase === 12) {
                    root.check(desktopPreview.video.player.position > root.livePosition, "Live preview did not advance");
                    root.check(root.named(pickerPanel.studio, "wallpaperHeroVideo").item.video.player.position > root.heroPosition,
                        "Circular live preview did not advance");
                    Session.dpmsActive = false;
                    root.check(desktopPreview.video === null, "DPMS off retained the preview decoder");
                    Session.dpmsActive = true;
                    Wallpapers.preview(root.collection[3], root.screenName);
                    tick.interval = 200;
                } else if (root.phase === 13) {
                    if (!root.ready(desktopPreview.video !== null && desktopPreview.video.hasFirstFrame,
                        "Live preview did not resume")) return;
                    Session.locked = true;
                    root.check(desktopPreview.video === null && Wallpapers.previewItem === null, "Lock retained the preview decoder");
                    Session.locked = false;
                    Wallpapers.preview(root.collection[3], root.screenName);
                    tick.interval = 200;
                } else if (root.phase === 14) {
                    if (!root.ready(desktopPreview.video !== null && desktopPreview.video.hasFirstFrame,
                        "Live preview did not reload")) return;
                    ShellState.open("wallpaper", root.screenName);
                    Qt.callLater(() => {
                        const studio = pickerPanel.studio;
                        studio.selectIndex(studio.items.findIndex(item => item.path === root.collection[3].path));
                    });
                    tick.interval = 300;
                } else if (root.phase === 15) {
                    const backdrop = root.named(pickerPanel.contentItem, "wallpaperPickerBackdrop");
                    if (!root.ready(!Wallpapers.busy && backdrop.opacity === 1, "Picker did not settle before Enter")) return;
                    pickerKeys.applyByEnter();
                    root.check(pickerPanel.dismissing && !pickerPanel.interactive, "Enter did not start immediate dismissal");
                    tick.interval = 60;
                } else if (root.phase === 16) {
                    const backdrop = root.named(pickerPanel.contentItem, "wallpaperPickerBackdrop");
                    root.check(backdrop.opacity > 0 && backdrop.opacity < 1, "Apply must fade instead of snapping or waiting");
                    root.check(Wallpapers.busy, "Apply test did not retain its pending command");
                    root.capture("apply-fade");
                    tick.interval = 160;
                } else if (root.phase === 17) {
                    root.check(!pickerPanel.visible && pickerPanel.dismissing, "Picker did not finish its fast fade: "
                        + JSON.stringify({visible: pickerPanel.visible, dismissing: pickerPanel.dismissing,
                            opacity: root.named(pickerPanel.contentItem, "wallpaperPickerBackdrop").opacity, busy: Wallpapers.busy}));
                    root.check(Wallpapers.busy && pickerPanel.opened, "Picker ownership must survive preparation");
                    root.check(Wallpapers.currentFor(root.screenName) === Quickshell.env("WALLPAPER_COMMITTED"),
                        "Fast dismissal committed the wallpaper before preparation completed");
                    root.check(root.named(pickerPanel.studio, "wallpaperHeroVideo").item === null,
                        "Faded picker retained a hidden video decoder");
                    tick.interval = 80;
                } else if (root.phase === 18) {
                    if (!root.ready(!Wallpapers.busy && pickerPanel.interactive, "Failed apply did not restore the picker")) return;
                    root.check(Wallpapers.lastError.includes("Simulated apply failure"), "Apply failure was not displayed");
                    root.check(pickerPanel.studio.selectedPath === root.collection[3].path, "Failed apply lost the selection");
                    root.check(root.named(pickerPanel.studio, "wallpaperOrbit").activeFocus,
                        "Failed apply did not restore keyboard navigation");
                    root.check(Wallpapers.currentFor(root.screenName) === Quickshell.env("WALLPAPER_COMMITTED"),
                        "Failed apply changed saved wallpaper state");
                    tick.interval = 350;
                } else if (root.phase === 19) {
                    root.check(pickerPanel.visible && pickerPanel.studio.canApply, "Restored picker cannot retry");
                    root.capture("apply-failure");
                    pickerKeys.applyByEnter();
                    root.check(pickerPanel.dismissing, "Retry did not start the fast fade");
                    tick.interval = 220;
                } else if (root.phase === 20) {
                    root.check(!pickerPanel.visible && Wallpapers.busy, "Retry waited for the command before fading");
                    tick.interval = 80;
                } else if (root.phase === 21) {
                    if (!root.ready(!Wallpapers.busy, "Live wallpaper apply did not finish")) return;
                    root.check(Wallpapers.currentFor(root.screenName) === root.collection[3].path, "Live wallpaper was not committed");
                    root.check(Wallpapers.previewItem === null, "Applied live wallpaper retained its preview");
                    root.check(!pickerPanel.opened, "Successful apply did not close the picker");
                    root.check(desktopPreview.video === null, "Apply retained the preview decoder");
                    tick.interval = 100;
                } else if (root.phase === 22) {
                    const scene = root.named(nativeBackground, "wallpaperTransition");
                    if (!root.ready(scene.transitioning && scene.progress > 0.05,
                        "Apply did not launch the mapped native wallpaper transition")) return;
                    root.check(scene.maps !== null && scene.maps.kind === "contagio", "Native transition did not receive generated maps");
                    root.check(scene.displayedLayer.wallpaper.path === Quickshell.env("WALLPAPER_COMMITTED"),
                        "Applying lost the outgoing wallpaper");
                    root.capture("applied-transition");
                    tick.interval = 100;
                } else if (root.phase === 23) {
                    const scene = root.named(nativeBackground, "wallpaperTransition");
                    if (!root.ready(!scene.transitioning && scene.video !== null && scene.video.hasFirstFrame,
                        "Applied wallpaper did not settle to live playback")) return;
                    root.check(scene.video.player.playbackState === MediaPlayer.PlayingState,
                        "Applied live wallpaper stayed paused after picker close");
                    root.check(scene.incomingLayer === null, "Native transition retained a second decoder");
                    console.log("WALLPAPER STRIP PASS: centered picker, palettes, preview cleanup, immediate Enter fade, failure recovery, native transition and live playback");
                    Qt.quit();
                }
                root.phase++;
            } catch (error) {
                console.error("WALLPAPER STRIP FAIL: " + error);
                Qt.quit();
            }
        }
    }
}
