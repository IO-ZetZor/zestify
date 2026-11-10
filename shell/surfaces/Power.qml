pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"

SurfaceFrame {
    id: root

    property var screen
    property var motion
    property var session
    property int confirmHoldMs: 700

    title: "Power"

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
        spacing: 10 * root.s

        Text {
            Layout.fillWidth: true
            text: "Take a break or end your session"
            color: root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8 * root.s

            PowerAction {
                theme: root.theme
                motion: root.motion
                s: root.s
                onCloseRequested: root.closeRequested()
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰌾"
                label: "Lock"
                description: "Keep your session private"
                action: "lock"
                onTriggered: root.runAction(action)
            }

            PowerAction {
                theme: root.theme
                motion: root.motion
                s: root.s
                onCloseRequested: root.closeRequested()
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰒲"
                label: "Sleep"
                description: "Resume where you left off"
                action: "sleep"
                onTriggered: root.runAction(action)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * root.s

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.border
            }

            Text {
                text: "END SESSION"
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.label * root.s
                font.letterSpacing: 1 * root.s
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.border
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8 * root.s

            PowerAction {
                theme: root.theme
                motion: root.motion
                s: root.s
                onCloseRequested: root.closeRequested()
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰍃"
                label: "Log out"
                description: "Return to sign in"
                action: "logout"
                confirm: true
                destructive: true
                holdMs: root.confirmHoldMs
                onTriggered: root.runAction(action)
            }

            PowerAction {
                theme: root.theme
                motion: root.motion
                s: root.s
                onCloseRequested: root.closeRequested()
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰜉"
                label: "Restart"
                description: "Reboot your computer"
                action: "restart"
                confirm: true
                destructive: true
                holdMs: root.confirmHoldMs
                onTriggered: root.runAction(action)
            }

            PowerAction {
                theme: root.theme
                motion: root.motion
                s: root.s
                onCloseRequested: root.closeRequested()
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰐥"
                label: "Shut down"
                description: "Power off your computer"
                action: "shutdown"
                confirm: true
                destructive: true
                holdMs: root.confirmHoldMs
                onTriggered: root.runAction(action)
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Hold to confirm session actions  ·  Release to cancel  ·  Esc to close"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.label * root.s
        }
    }
}
