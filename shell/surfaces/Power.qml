pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"

Item {
    id: root

    property var theme
    property real s: 1
    property var screen
    property var motion
    property var session
    property int confirmHoldMs: 700

    signal closeRequested()

    implicitWidth: 504
    implicitHeight: 248

    function runAction(action) {
        root.closeRequested();
        if (action === "lock") {
            if (root.session)
                root.session.lock(false);
            else
                Quickshell.execDetached(["zesti", "lock"]);
        } else if (action === "sleep") {
            if (root.session)
                root.session.sleep();
            else
                Quickshell.execDetached(["zesti", "sleep"]);
        } else if (action === "logout") {
            Quickshell.execDetached(["hyprctl", "dispatch", "exit"]);
        } else if (action === "restart") {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (action === "shutdown") {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10 * root.s
        spacing: 8 * root.s

        Item {
            id: heading
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.max(portrait.width, caption.implicitWidth)
            Layout.preferredHeight: 116 * root.s
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            Layout.maximumHeight: 116 * root.s

            PowerPortrait {
                id: portrait
                theme: root.theme
                motion: root.motion
                s: root.s
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(92 * root.s,
                                Math.max(0, heading.height - caption.implicitHeight - 8 * root.s))
                height: width
            }

            Text {
                id: caption
                objectName: "powerRemCaption"
                anchors.top: portrait.bottom
                anchors.topMargin: 8 * root.s
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Take a break Master."
                color: root.theme.dim
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.body * root.s
                horizontalAlignment: Text.AlignHCenter
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80 * root.s
            Layout.minimumHeight: 80 * root.s
            Layout.maximumHeight: 80 * root.s
            spacing: 4 * root.s

            Repeater {
                model: [
                    {action: "lock", glyph: "󰌾", label: "Lock"},
                    {action: "sleep", glyph: "󰒲", label: "Sleep"},
                    {action: "logout", glyph: "󰍃", label: "Log out"},
                    {action: "restart", glyph: "󰜉", label: "Restart"},
                    {action: "shutdown", glyph: "󰐥", label: "Shut down"}
                ]
                delegate: PowerAction {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    theme: root.theme
                    motion: root.motion
                    s: root.s
                    compact: true
                    glyph: modelData.glyph
                    label: modelData.label
                    action: modelData.action
                    confirm: action !== "lock" && action !== "sleep"
                    destructive: confirm
                    holdMs: root.confirmHoldMs
                    onCloseRequested: root.closeRequested()
                    onTriggered: action => root.runAction(action)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Hold to confirm  ·  Esc to close"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }
    }
}
