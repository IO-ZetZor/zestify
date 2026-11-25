import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root
    property var targetScreen: null
    property var theme
    property var motion
    property real uiScale: 1
    property real backgroundOpacity: 1
    property string pendingAction: ""
    readonly property real s: targetScreen
        ? LayoutLib.pillScale(targetScreen.width, targetScreen.height) * uiScale : uiScale
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    readonly property bool ownsDrawer: screenName.length > 0 && ShellState.shortcutsOwner === screenName
    readonly property alias gesture: drawer

    screen: targetScreen
    visible: !Session.locked
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-shortcut-drawer"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    mask: !drawer.enabled ? emptyMask : drawer.active ? fullMask : edgeMask

    Region { id: emptyMask; width: 0; height: 0 }
    Region {
        id: edgeMask
        x: drawer.width - drawer.edgeWidth
        y: drawer.topInset
        width: drawer.edgeWidth
        height: Math.max(0, drawer.height - y - drawer.bottomInset)
    }
    Region {
        id: fullMask
        x: Math.max(8 * root.uiScale, 6)
        y: drawer.topInset
        width: Math.max(0, drawer.width - x)
        height: Math.max(0, drawer.height - y - drawer.bottomInset)
    }
    onOwnsDrawerChanged: {
        if (ownsDrawer && !drawer.dragging) drawer.open();
        else if (!ownsDrawer && drawer.active) {
            root.pendingAction = "";
            drawer.close();
        }
    }
    Component.onDestruction: ShellState.closeShortcuts(root.screenName)

    Connections {
        target: drawer
        function onEnabledChanged() {
            if (!drawer.enabled) {
                root.pendingAction = "";
                launchAction.stop();
            }
        }
    }

    Timer {
        id: launchAction
        // Let the compositor present the hidden drawer before capturing.
        interval: 50
        onTriggered: {
            const action = root.pendingAction;
            root.pendingAction = "";
            if (!drawer.enabled || drawer.active || ShellState.surface.length > 0
                    || ShellState.shortcutsOwner.length > 0 || ShellState.notificationsOwner.length > 0
                    || ShellState.powerOwner.length > 0 || ShellState.partyOwner.length > 0) return;
            if (action === "config" || action === "system" || action === "wallpaper") {
                ShellState.open(action, root.screenName);
            } else if (action === "screenshot" || action === "record") {
                Capture.run(action);
            }
        }
    }
    ShortcutDrawer {
        id: drawer
        anchors.fill: parent
        theme: root.theme
        motion: root.motion
        s: root.s
        topInset: Math.max(8 * root.uiScale, 6)
        bottomInset: Math.max(8 * root.uiScale, 6)
        backgroundOpacity: root.backgroundOpacity
        recording: Capture.recording
        enabled: !Session.locked && Session.dpmsActive
        onPullStarted: {
            root.pendingAction = "";
            launchAction.stop();
            ShellState.openShortcuts(root.screenName);
            Capture.refreshStatus();
        }
        onClosed: {
            ShellState.closeShortcuts(root.screenName);
            if (root.pendingAction.length > 0) launchAction.restart();
        }
        ShortcutActions {
            anchors.fill: parent
            theme: root.theme
            motion: root.motion
            s: root.s
            recording: Capture.recording
            enabled: !Capture.busy
            onTriggered: action => {
                root.pendingAction = action;
                // Capture should wait for presentation, not the closing spring.
                drawer.close(action === "screenshot" || action === "record");
            }
        }
    }
}
