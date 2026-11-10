pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root

    property var targetScreen
    property var theme
    property real uiScale: 1
    property var motion
    property bool enabled: true

    readonly property real s: targetScreen
        ? LayoutLib.pillScale(targetScreen.width, targetScreen.height) * uiScale
        : 1
    readonly property real cardWidth: targetScreen
        ? Math.min(380 * s, targetScreen.width - 32 * s)
        : 320

    screen: targetScreen
    visible: enabled && Notifications.popups.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.top: true
    anchors.right: true

    implicitWidth: cardWidth
    implicitHeight: column.implicitHeight
    margins.top: 14 * s
    margins.right: 14 * s

    function iconSource(entry) {
        const icon = entry && entry.appIcon ? String(entry.appIcon) : "";
        if (icon.length === 0)
            return "";
        if (icon.indexOf("/") >= 0 || icon.indexOf("file:") === 0)
            return icon;
        if (Quickshell.hasThemeIcon(icon))
            return Quickshell.iconPath(icon);
        return "";
    }

    Column {
        id: column

        width: parent.width
        spacing: 8 * root.s

        Repeater {
            model: Notifications.popups

            delegate: NotificationCard {
                required property var modelData
                width: column.width
                height: implicitHeight
                theme: root.theme
                s: root.s
                motion: root.motion
                entry: modelData
                iconSource: root.iconSource(modelData)
                popup: true
                onDismissed: Notifications.dismiss(modelData.id)
                onExpired: Notifications.expirePopup(modelData.id)
                onActionActivated: identifier => Notifications.invokeAction(modelData.id, identifier)
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
