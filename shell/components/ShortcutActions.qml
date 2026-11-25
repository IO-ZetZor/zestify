pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    property var theme
    property var motion
    property real s: 1
    property bool recording: false
    readonly property real buttonSize: Math.max(0, Math.min(48 * s, width,
        (height - 4 * buttons.spacing) / 5))
    signal triggered(string action)

    Column {
        id: buttons
        anchors.centerIn: parent
        spacing: 8 * root.s
        Repeater {
            model: [
                { action: "screenshot", glyph: "󰹑", label: "Take screenshot" },
                { action: "record", glyph: "", label: "Start or stop screen recording" },
                { action: "wallpaper", glyph: "󰸉", label: "Choose wallpaper" },
                { action: "config", glyph: "󰒓", label: "Open settings" },
                { action: "system", glyph: "󰍛", label: "Open system panel" }
            ]
            delegate: Rectangle {
                id: button
                required property var modelData
                readonly property bool recordingAction: modelData.action === "record" && root.recording
                objectName: "shortcut-" + modelData.action
                width: root.buttonSize
                height: width
                radius: root.theme.r.tile * root.s
                color: recordingAction ? root.theme.withAlpha(root.theme.danger, 0.16)
                    : hover.hovered ? root.theme.withAlpha(root.theme.accent, 0.08) : "transparent"
                border.width: 1
                border.color: recordingAction ? root.theme.danger : activeFocus ? root.theme.accent : "transparent"
                Behavior on color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }
                Behavior on border.color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.action === "record"
                    ? (root.recording ? "Stop screen recording" : "Start screen recording") : modelData.label
                Accessible.onPressAction: if (enabled) root.triggered(modelData.action)
                Keys.onReturnPressed: event => {
                    if (!event.isAutoRepeat) root.triggered(modelData.action);
                }
                Keys.onSpacePressed: event => {
                    if (!event.isAutoRepeat) root.triggered(modelData.action);
                }

                Text {
                    anchors.centerIn: parent
                    text: button.modelData.glyph
                    color: button.recordingAction ? root.theme.danger
                        : hover.hovered || button.activeFocus ? root.theme.accent : root.theme.dim
                    font.family: root.theme.iconFont
                    font.pixelSize: Math.min(22 * root.s, button.width * 0.5)
                }
                Rectangle {
                    objectName: "shortcutRecordingBadge"
                    visible: button.recordingAction
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 5 * root.s
                    width: 6 * root.s
                    height: width
                    radius: width / 2
                    color: root.theme.danger
                }
                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onPressedChanged: if (pressed) button.forceActiveFocus(Qt.MouseFocusReason)
                    onTapped: root.triggered(button.modelData.action)
                }
            }
        }
    }
}
