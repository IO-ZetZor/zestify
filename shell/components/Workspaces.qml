import QtQuick
import Quickshell.Hyprland

Row {
    id: root

    property var theme
    property var screen
    property real s: 1

    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property int activeWorkspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0

    spacing: 2 * s

    Repeater {
        model: 9

        delegate: Rectangle {
            id: slot
            required property int index

            width: 14 * s
            height: 20 * s
            radius: 4 * s
            color: root.activeWorkspace === index + 1 ? root.theme.accent : "transparent"

            Text {
                anchors.centerIn: parent
                text: slot.index + 1
                color: root.activeWorkspace === slot.index + 1 ? root.theme.onAccent : root.theme.dim
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
                font.weight: root.activeWorkspace === slot.index + 1 ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + (slot.index + 1))
            }
        }
    }
}
