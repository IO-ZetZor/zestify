import QtQuick
import QtQuick.Layouts
import "../lib/power.js" as PowerLib

Rectangle {
    id: tile

    property var theme
    property var motion
    property real s: 1

    property string glyph
    property string label
    property string description
    property string action
    property bool confirm: false
    property bool destructive: false
    property bool compact: false
    property int holdMs: 700
    property real progress: 0
    property bool holding: false
    property double startedAt: 0
    property int keyboardKey: 0

    signal closeRequested()
    signal triggered(string action)

    readonly property bool active: tile.holding || tile.progress > 0
    readonly property color actionColor: tile.destructive ? tile.theme.danger : tile.theme.accent
    readonly property var fillGeometry: PowerLib.fillGeometry(tile.progress, tile.height)

    function cancelHold() {
        tile.holding = false;
        tile.progress = 0;
        tile.keyboardKey = 0;
    }

    function beginHold() {
        if (tile.holding)
            return;
        tile.progress = 0;
        tile.startedAt = Date.now();
        tile.holding = true;
    }

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: tile.label
    Accessible.description: tile.description + (tile.confirm ? ". Hold Space or Enter to confirm." : "")
    onActiveFocusChanged: if (!activeFocus) tile.cancelHold()
    onVisibleChanged: if (!visible) tile.cancelHold()
    onEnabledChanged: if (!enabled) tile.cancelHold()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) {
                tile.keyboardKey = event.key;
                if (tile.confirm)
                    tile.beginHold();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            tile.cancelHold();
            tile.closeRequested();
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) {
                const armed = tile.keyboardKey === event.key;
                tile.cancelHold();
                if (armed && !tile.confirm)
                    tile.triggered(tile.action);
            }
            event.accepted = true;
        }
    }

    radius: tile.theme.r.tile * tile.s
    color: tile.active
        ? tile.theme.withAlpha(tile.actionColor, 0.16)
        : (tileHover.hovered
            ? tile.theme.withAlpha(tile.compact ? tile.theme.accent : tile.theme.cream,
                                   tile.compact ? 0.08 : 0.06)
            : tile.compact ? "transparent" : tile.theme.tileBg)
    border.width: 1
    border.color: tile.active || tile.activeFocus ? tile.actionColor
        : tile.compact ? "transparent" : tile.theme.border
    Behavior on color { ColorAnimation { duration: tile.motion ? tile.motion.fast : 140 } }
    Behavior on border.color { ColorAnimation { duration: tile.motion ? tile.motion.fast : 140 } }

    Item {
        id: holdFillClip

        x: 0
        y: tile.fillGeometry.y
        width: tile.width
        height: tile.fillGeometry.height
        visible: tile.confirm && tile.progress > 0
        clip: true

        Rectangle {
            y: -holdFillClip.y
            width: tile.width
            height: tile.height
            radius: tile.radius
            color: tile.theme.withAlpha(tile.actionColor, 0.24)
        }
    }

    HoverHandler {
        id: tileHover
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        onClicked: if (!tile.confirm) tile.triggered(tile.action)
        onPressed: {
            tile.forceActiveFocus(Qt.MouseFocusReason);
            if (tile.confirm)
                tile.beginHold();
        }
        onPositionChanged: mouse => {
            if (mouse.x < 0 || mouse.y < 0 || mouse.x > width || mouse.y > height)
                tile.cancelHold();
        }
        onReleased: tile.cancelHold()
        onCanceled: tile.cancelHold()
    }

    Timer {
        interval: 16
        repeat: true
        running: tile.holding
        onTriggered: {
            tile.progress = PowerLib.progressAfter(0, Date.now() - tile.startedAt, tile.holdMs);
            if (tile.progress >= 1) {
                tile.holding = false;
                tile.triggered(tile.action);
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - (tile.compact ? 4 : 20) * tile.s
        spacing: 6 * tile.s

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: (tile.compact ? 36 : tile.confirm ? 36 : 44) * tile.s
            implicitHeight: implicitWidth
            radius: 12 * tile.s
            color: tile.compact ? "transparent" : tile.theme.withAlpha(tile.actionColor, 0.10)

            Text {
                anchors.centerIn: parent
                text: tile.glyph
                color: tile.compact && !tile.active && !tileHover.hovered && !tile.activeFocus
                    ? tile.theme.dim : tile.actionColor
                font.family: tile.theme.iconFont
                font.pixelSize: (tile.compact ? 22 : tile.confirm ? 19 : 23) * tile.s
            }
        }

        Text {
            Layout.fillWidth: true
            text: tile.label
            color: tile.theme.cream
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: tile.theme.fontFamily
            font.pixelSize: tile.theme.fs.body * tile.s
            font.weight: Font.Medium
        }

        Text {
            Layout.fillWidth: true
            visible: !tile.compact && tile.description.length > 0
            text: tile.description
            color: tile.theme.dim
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: tile.theme.fontFamily
            font.pixelSize: tile.theme.fs.meta * tile.s
        }

        Text {
            Layout.fillWidth: true
            visible: tile.confirm && !tile.compact
            text: tile.holding ? "Keep holding…" : "Hold to confirm"
            color: tile.holding ? tile.actionColor : tile.theme.faint
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: tile.theme.fontFamily
            font.pixelSize: tile.theme.fs.label * tile.s
        }
    }
}
