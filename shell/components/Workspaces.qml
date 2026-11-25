pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

Item {
    id: root

    property var theme
    property var screen
    property var motion
    property real s: 1
    readonly property real slotWidth: 11 * s
    readonly property real slotSpacing: 1 * s
    property bool ready: false

    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property int activeWorkspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
    readonly property bool hasActiveWorkspace: activeWorkspace >= 1 && activeWorkspace <= 9
    readonly property bool animate: ready && visible && !(motion && motion.calm)

    implicitWidth: workspaceRow.implicitWidth
    implicitHeight: workspaceRow.implicitHeight

    Component.onCompleted: ready = true

    Rectangle {
        x: (Math.max(1, Math.min(9, root.activeWorkspace)) - 1) * (root.slotWidth + root.slotSpacing)
        width: root.slotWidth
        height: 20 * root.s
        radius: 4 * root.s
        color: root.theme.accent
        visible: root.hasActiveWorkspace

        Behavior on x {
            enabled: root.animate && root.hasActiveWorkspace
            NumberAnimation {
                duration: root.motion ? root.motion.glide : 260
                easing.type: Easing.OutCubic
            }
        }
    }

    Row {
        id: workspaceRow
        spacing: root.slotSpacing

        Repeater {
            model: 9

            delegate: Item {
                id: slot
                required property int index
                readonly property bool active: root.activeWorkspace === index + 1

                width: root.slotWidth
                height: 20 * root.s

                Text {
                    objectName: "workspaceLabel-" + slot.index
                    anchors.centerIn: parent
                    text: slot.index + 1
                    color: slot.active ? root.theme.onAccent : root.theme.dim
                    font.family: root.theme.monoFont
                    font.pixelSize: Math.round(12 * root.s)
                    font.weight: slot.active ? Font.DemiBold : Font.Medium
                    renderType: Text.NativeRendering

                    Behavior on color {
                        enabled: root.animate
                        ColorAnimation { duration: root.motion ? root.motion.fast : 140 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + (slot.index + 1))
                }
            }
        }
    }
}
