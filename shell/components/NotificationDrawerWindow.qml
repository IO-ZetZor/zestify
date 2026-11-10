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
    readonly property bool ownsDrawer: screenName.length > 0 && ShellState.notificationsOwner === screenName
    readonly property alias gesture: drawer

    screen: targetScreen
    visible: !Session.locked
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-notification-drawer"
    // Keep focus mode stable for the duration of the pointer grab.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    mask: !drawer.enabled ? emptyMask : drawer.active ? fullMask : edgeMask

    Region { id: emptyMask; width: 0; height: 0 }
    Region {
        id: edgeMask
        x: 0
        y: drawer.topInset
        width: drawer.edgeWidth
        height: Math.max(0, drawer.height - y)
    }
    Region {
        id: fullMask
        x: 0
        y: drawer.topInset
        width: drawer.width
        height: Math.max(0, drawer.height - y)
    }
    onOwnsDrawerChanged: {
        if (ownsDrawer && !drawer.dragging) drawer.open();
        else if (!ownsDrawer && drawer.active) drawer.close();
    }
    Component.onDestruction: ShellState.closeNotifications(root.screenName)
    NotificationDrawer {
        id: drawer
        anchors.fill: parent
        theme: root.theme
        motion: root.motion
        s: root.s
        topInset: Math.max(8 * root.uiScale, 6)
        backgroundOpacity: root.backgroundOpacity
        enabled: !Session.locked && Session.dpmsActive
        onPullStarted: ShellState.openNotifications(root.screenName)
        onClosed: ShellState.closeNotifications(root.screenName)
        NotificationsSurface {
            anchors.fill: parent
            theme: root.theme
            s: root.s
            motion: root.motion
            onCloseRequested: drawer.close()
        }
    }
}
