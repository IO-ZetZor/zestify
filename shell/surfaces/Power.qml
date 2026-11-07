pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib/power.js" as PowerLib

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

    component PowerTile: Rectangle {
        id: tile

        property string glyph
        property string label
        property string action
        property bool confirm: false
        property bool destructive: false
        property int holdMs: 700
        property real progress: 0
        property bool holding: false

        signal triggered(string action)

        readonly property bool active: tile.holding || tile.progress > 0

        radius: root.theme.r.tile * root.s
        color: tile.active
            ? root.theme.withAlpha(root.theme.accent, 0.16)
            : (tileHover.hovered
                ? root.theme.withAlpha(root.theme.cream, 0.06)
                : root.theme.tileBg)
        border.width: 1
        border.color: tile.active ? root.theme.accent : root.theme.border

        HoverHandler {
            id: tileHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            onPressed: {
                if (tile.confirm) {
                    tile.progress = 0;
                    tile.holding = true;
                } else {
                    tile.triggered(tile.action);
                }
            }
            onReleased: {
                tile.holding = false;
                tile.progress = 0;
            }
            onCanceled: {
                tile.holding = false;
                tile.progress = 0;
            }
        }

        Timer {
            interval: 16
            repeat: true
            running: tile.holding
            onTriggered: {
                tile.progress = PowerLib.progressAfter(tile.progress, interval, tile.holdMs);
                if (tile.progress >= 1) {
                    tile.holding = false;
                    tile.triggered(tile.action);
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 12 * root.s
            spacing: 6 * root.s

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.glyph
                color: tile.destructive ? root.theme.danger : root.theme.cream
                font.family: root.theme.iconFont
                font.pixelSize: 28 * root.s
            }

            Text {
                Layout.fillWidth: true
                text: tile.label
                color: root.theme.cream
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
            }

            Text {
                Layout.fillWidth: true
                visible: tile.confirm
                text: "Hold to confirm"
                color: root.theme.faint
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
            }
        }

        Canvas {
            id: ring

            anchors.fill: parent
            visible: tile.confirm && tile.progress > 0
            antialiasing: true

            Connections {
                target: tile

                function onProgressChanged() {
                    ring.requestPaint();
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (tile.progress <= 0)
                    return;
                const inset = 2 * root.s;
                const radius = Math.min(width, height) / 2 - inset;
                ctx.strokeStyle = root.theme.accent;
                ctx.lineWidth = 2.5 * root.s;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, radius,
                    -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * tile.progress);
                ctx.stroke();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * root.s

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8 * root.s

            PowerTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰌾"
                label: "Lock"
                action: "lock"
                onTriggered: root.runAction(action)
            }

            PowerTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰒲"
                label: "Sleep"
                action: "sleep"
                onTriggered: root.runAction(action)
            }

            PowerTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰍃"
                label: "Log out"
                action: "logout"
                confirm: true
                destructive: true
                holdMs: root.confirmHoldMs
                onTriggered: root.runAction(action)
            }

            PowerTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰜉"
                label: "Restart"
                action: "restart"
                confirm: true
                destructive: true
                holdMs: root.confirmHoldMs
                onTriggered: root.runAction(action)
            }

            PowerTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                glyph: "󰐥"
                label: "Shut down"
                action: "shutdown"
                confirm: true
                destructive: true
                holdMs: root.confirmHoldMs
                onTriggered: root.runAction(action)
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Click Lock or Sleep  ·  Hold the others to confirm  ·  Esc to cancel"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.label * root.s
        }
    }
}
