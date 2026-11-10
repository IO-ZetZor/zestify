import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../shell/components"
import "../../shell/singletons"

ShellRoot {
    id: root
    Theme { id: fixtureTheme }
    PillWindow {
        id: pillPanel
        targetScreen: Quickshell.screens[0]
        theme: fixtureTheme
        stats: Stats
        players: Players
        wallpapers: Wallpapers
        WlrLayershell.namespace: "zestify-drawer-pill-test"
    }
    NotificationDrawerWindow {
        id: panel
        targetScreen: Quickshell.screens[0]
        theme: fixtureTheme
        WlrLayershell.namespace: "zestify-drawer-test"
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
            onActiveChanged: if (active) ShellState.closeNotifications()
            onLockRequested: { console.error("DRAWER FAIL: Test reached lock handoff"); Qt.exit(1); }
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
                pillSurface: pillPanel.pill.surface, pillFocus: pillPanel.WlrLayershell.keyboardFocus,
                pillMaskX: pillPanel.mask.x, pillMaskWidth: pillPanel.mask.width,
                launcherQuery: launcher ? launcher.query : "",
                maskY: panel.mask.y, edgeWidth: g.edgeWidth, topInset: g.topInset,
                lockDragging: lockGesture.dragging, lockPull: lockGesture.pull,
                lockActive: lockGesture.active});
        }
        function open(): void { ShellState.open("notifications", panel.targetScreen.name); }
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
            console.log("DRAWER PASS: compositor-delivered edge and handle drags, spring bounce, Escape, outside dismissal, ownership transfer, DPMS, top-edge lock coexistence");
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
}
