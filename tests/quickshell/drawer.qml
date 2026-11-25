import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../shell/components"
import "../../shell/singletons"

ShellRoot {
    id: root
    property var temporaryPill: null
    readonly property bool checkAnimation: Quickshell.env("PILL_ANIMATION_CHECK") === "1"
    Component.onCompleted: if (checkAnimation) Appearance.applyLayerRules()
    Theme { id: fixtureTheme }
    PillWindow {
        id: pillPanel
        targetScreen: Quickshell.screens[0]
        theme: fixtureTheme
        stats: Stats
        players: Players
        wallpapers: Wallpapers
        WlrLayershell.namespace: root.checkAnimation ? "zestify-pill" : "zestify-drawer-pill-test"
    }
    Rectangle {
        parent: pillPanel.pill
        visible: root.checkAnimation
        x: parent.width / 2 - width / 2
        y: 4
        width: 8
        height: 8
        color: "#ff00ff"
        z: 1000
    }
    NotificationDrawerWindow {
        id: panel
        targetScreen: Quickshell.screens[0]
        theme: fixtureTheme
        WlrLayershell.namespace: "zestify-drawer-test"
    }
    PowerDrawerWindow {
        id: powerPanel
        targetScreen: panel.targetScreen
        theme: fixtureTheme
        WlrLayershell.namespace: "zestify-power-drawer-test"
    }
    ShortcutDrawerWindow {
        id: shortcutPanel
        targetScreen: panel.targetScreen
        theme: fixtureTheme
        WlrLayershell.namespace: "zestify-shortcut-drawer-test"
    }
    WallpaperPickerWindow {
        id: wallpaperPanel
        targetScreen: panel.targetScreen
        theme: fixtureTheme
        WlrLayershell.namespace: "zestify-wallpaper-picker-test"
    }
    // The real lock gesture with a harmless handoff, mapped above the drawer.
    PanelWindow {
        id: lockPanel
        screen: panel.targetScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "zestify-drawer-lock-test"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }
        mask: lockGesture.active ? fullLock : lockEdge
        Region { id: lockEdge; width: lockGesture.width; height: lockGesture.edgeHeight }
        Region { id: fullLock; width: lockGesture.width; height: lockGesture.height }
        LockPull {
            id: lockGesture
            anchors.fill: parent
            theme: fixtureTheme
            onActiveChanged: if (active) {
                ShellState.closeNotifications();
                ShellState.closePower();
                ShellState.closeShortcuts();
            }
            onLockRequested: { console.error("DRAWER FAIL: Test reached lock handoff"); Qt.exit(1); }
        }
    }
    Component {
        id: temporaryPillComponent
        PillWindow {
            targetScreen: panel.targetScreen
            theme: fixtureTheme
            stats: Stats
            players: Players
            wallpapers: Wallpapers
            showRest: false
            WlrLayershell.namespace: "zestify-initial-open-pill-test"
        }
    }
    IpcHandler {
        target: "drawerTest"
        function state(): string {
            const g = panel.gesture;
            const launcher = root.findLauncher(pillPanel.pill);
            return JSON.stringify({dragging: g.dragging, pull: g.pull, opened: g.opened, active: g.active,
                settling: g.settling, drawerWidth: g.drawerWidth, owner: ShellState.notificationsOwner,
                surface: ShellState.surface, screen: panel.targetScreen.name, maskWidth: panel.mask.width,
                nativeWidth: pillPanel.width, nativeHeight: pillPanel.height,
                pillWidth: pillPanel.pill.width, pillHeight: pillPanel.pill.height,
                screenWidth: panel.targetScreen.width, screenHeight: panel.targetScreen.height,
                topGap: pillPanel.topGap,
                layerRuleGeneration: Appearance.ruleGeneration,
                appliedLayerSettings: Appearance.appliedSettings,
                temporaryPill: root.temporaryPill ? {
                    held: root.temporaryPill.expandedCanvasHeld,
                    visible: root.temporaryPill.visible,
                    height: root.temporaryPill.height
                } : null,
                pillSurface: pillPanel.pill.surface, pillFocus: pillPanel.WlrLayershell.keyboardFocus,
                pillMaskX: pillPanel.mask.x, pillMaskWidth: pillPanel.mask.width,
                launcherQuery: launcher ? launcher.query : "",
                maskY: panel.mask.y, edgeWidth: g.edgeWidth, topInset: g.topInset,
                lockDragging: lockGesture.dragging, lockPull: lockGesture.pull,
                lockActive: lockGesture.active});
        }
        function createOpenPanel(): void {
            root.temporaryPill = temporaryPillComponent.createObject(root);
        }
        function closePill(): void { ShellState.close(panel.targetScreen.name); }
        function destroyOpenPanel(): void { root.temporaryPill.destroy(); root.temporaryPill = null; }
        function pin(value: bool): void { pillPanel.pill.pinned = value; }
        function scale(value: real): void { pillPanel.uiScale = value; }
        function open(): void { ShellState.open("notifications", panel.targetScreen.name); }
        function powerState(): string {
            const g = powerPanel.gesture;
            const portrait = root.findNamed(g, "powerRemControl");
            const point = portrait.mapToItem(g, 0, 0);
            return JSON.stringify({dragging: g.dragging, pull: g.pull, opened: g.opened, active: g.active,
                settling: g.settling, drawerHeight: g.drawerHeight, drawerWidth: g.drawerWidth,
                owner: ShellState.powerOwner, surface: ShellState.surface,
                maskX: powerPanel.mask.x, maskY: powerPanel.mask.y,
                maskWidth: powerPanel.mask.width, maskHeight: powerPanel.mask.height,
                edgeHeight: g.edgeHeight, sideInset: g.sideInset, topInset: g.topInset,
                width: g.width, height: g.height, pillSurface: pillPanel.pill.surface,
                portrait: {x: point.x, y: point.y, width: portrait.width, height: portrait.height,
                    angle: portrait.angle, dragging: portrait.dragging, settling: portrait.settling},
                lockDragging: lockGesture.dragging, lockPull: lockGesture.pull,
                lockActive: lockGesture.active});
        }
        function openPower(): void { ShellState.open("power", panel.targetScreen.name); }
        function transferPower(): void { ShellState.openPower("other-display"); }
        function clearPowerOwner(): void { ShellState.closePower(); }
        function shortcutState(): string {
            const g = shortcutPanel.gesture;
            const icons = ["screenshot", "record", "wallpaper", "config", "system"].map(action => {
                const icon = root.findNamed(g, "shortcut-" + action);
                const point = icon.mapToItem(g, 0, 0);
                return {action: action, x: point.x, y: point.y, width: icon.width, height: icon.height};
            });
            return JSON.stringify({dragging: g.dragging, pull: g.pull, opened: g.opened,
                active: g.active, settling: g.settling, drawerWidth: g.drawerWidth,
                owner: ShellState.shortcutsOwner, pending: shortcutPanel.pendingAction,
                surface: ShellState.surface, pillSurface: pillPanel.pill.surface,
                wallpaperOpened: wallpaperPanel.opened, wallpaperFocus: wallpaperPanel.WlrLayershell.keyboardFocus,
                pillVisible: pillPanel.pill.visible, pillOpacity: pillPanel.pill.opacity,
                pillMaskWidth: pillPanel.mask.width, maskX: shortcutPanel.mask.x,
                maskY: shortcutPanel.mask.y, maskWidth: shortcutPanel.mask.width,
                maskHeight: shortcutPanel.mask.height, edgeWidth: g.edgeWidth,
                topInset: g.topInset, bottomInset: g.bottomInset, icons: icons,
                lockDragging: lockGesture.dragging, lockPull: lockGesture.pull});
        }
        function openShortcuts(): void { ShellState.open("shortcuts", panel.targetScreen.name); }
        function transferShortcuts(): void { ShellState.openShortcuts("other-display"); }
        function clearShortcutOwner(): void { ShellState.closeShortcuts(); }
        function fullscreen(value: bool): void { pillPanel.pill.fullscreen = value; }
        function shortcutPreview(): void {
            const drawerPanel = root.findNamed(shortcutPanel.gesture, "shortcutDrawerPanel");
            drawerPanel.grabToImage(result => result.saveToFile(Quickshell.env("DRAWER_SHORTCUT_PREVIEW")));
        }
        function openPill(): void { ShellState.open("calendar", panel.targetScreen.name); }
        function openLauncher(): void { ShellState.open("launcher", panel.targetScreen.name); }
        function transfer(): void { ShellState.openNotifications("other-display"); }
        function clearOwner(): void { ShellState.closeNotifications(); }
        function dpmsOff(): void { Session.dpmsActive = false; }
        function dpmsOn(): void { Session.dpmsActive = true; }
    }
    Process {
        id: pointerTest
        command: ["python3", Quickshell.env("DRAWER_POINTER_SCRIPT"),
            Quickshell.shellDir + "/shell.qml", panel.targetScreen.name]
        stdout: StdioCollector { onStreamFinished: console.log(text.trim()) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) console.error(text.trim()); } }
        onExited: exitCode => {
            if (exitCode !== 0) { Qt.exit(exitCode); return; }
            console.log(Quickshell.env("DRAWER_SHORTCUT_ONLY") === "1"
                ? "DRAWER PASS: shortcut edge/handle drags, actions and capture dispatch, fullscreen surfaces, spring bounce, Escape, outside dismissal, ownership, DPMS and edge coexistence"
                : "DRAWER PASS: notification, power and shortcut drags, capture dispatch, fullscreen surfaces, portrait rotation, spring bounce, dismissal, ownership, DPMS and edge coexistence");
            Qt.quit();
        }
    }
    Timer {
        interval: 350
        running: true
        onTriggered: {
            if (panel.mask.width !== panel.gesture.edgeWidth || panel.mask.y < lockGesture.edgeHeight
                || panel.WlrLayershell.keyboardFocus !== WlrKeyboardFocus.OnDemand) {
                console.error("DRAWER FAIL: Idle mask/focus does not protect the lock edge",
                    panel.mask.width, panel.gesture.edgeWidth, panel.mask.y, lockGesture.edgeHeight,
                    panel.WlrLayershell.keyboardFocus, WlrKeyboardFocus.OnDemand,
                    panel.gesture.enabled, Session.locked, Session.dpmsActive);
                Qt.exit(1);
                return;
            }
            pointerTest.running = true;
        }
    }
    function findLauncher(item) {
        if (item.title === "Launcher" && item.query !== undefined) return item;
        for (const child of item.children || []) {
            const result = findLauncher(child);
            if (result) return result;
        }
        return null;
    }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const result = findNamed(child, name);
            if (result) return result;
        }
        return null;
    }
}
