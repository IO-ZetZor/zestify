import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../surfaces"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root
    property var targetScreen: null
    property var theme
    property var motion
    property real uiScale: 1
    property real backgroundOpacity: 1
    readonly property real s: targetScreen
        ? LayoutLib.pillScale(targetScreen.width, targetScreen.height) * uiScale : uiScale
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    readonly property bool ownsDrawer: screenName.length > 0 && ShellState.powerOwner === screenName
    readonly property alias gesture: drawer

    screen: targetScreen
    visible: !Session.locked
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-power-drawer"
    // Keep focus mode stable throughout a pointer grab, like notifications.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    mask: !drawer.enabled ? emptyMask : drawer.active ? fullMask : edgeMask

    Region { id: emptyMask; width: 0; height: 0 }
    Region {
        id: edgeMask
        x: drawer.sideInset
        y: drawer.height - drawer.edgeHeight
        width: Math.max(0, drawer.width - 2 * x)
        height: drawer.edgeHeight
    }
    Region {
        id: fullMask
        x: drawer.sideInset
        y: drawer.topInset
        width: Math.max(0, drawer.width - 2 * x)
        height: Math.max(0, drawer.height - y)
    }
    onOwnsDrawerChanged: {
        if (ownsDrawer && !drawer.dragging) drawer.open();
        else if (!ownsDrawer && drawer.active) drawer.close();
    }
    Component.onDestruction: ShellState.closePower(root.screenName)
    PowerDrawer {
        id: drawer
        anchors.fill: parent
        theme: root.theme
        motion: root.motion
        s: root.s
        sideInset: Math.max(8 * root.uiScale, 6)
        topInset: Math.max(8 * root.uiScale, 6)
        backgroundOpacity: root.backgroundOpacity
        enabled: !Session.locked && Session.dpmsActive
        onPullStarted: ShellState.openPower(root.screenName)
        onClosed: ShellState.closePower(root.screenName)
        Power {
            anchors.fill: parent
            theme: root.theme
            s: root.s
            screen: root.targetScreen
            motion: root.motion
            session: Session
            confirmHoldMs: Config.power.confirmHoldMs
            onCloseRequested: drawer.close()
        }
    }
}
