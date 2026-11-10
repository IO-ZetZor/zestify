pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property var theme
    property real s: 1
    property bool dnd: false
    property var motion
    property var onOpenWallpaper

    signal dndToggled()

    spacing: 4 * root.s

    component Toggle: Rectangle {
        id: toggle
        property string glyph
        property bool on
        signal toggled()

        Layout.preferredWidth: 24 * root.s
        Layout.preferredHeight: 24 * root.s
        radius: 7 * root.s
        color: toggle.on ? root.theme.accent : root.theme.tileBg
        border.width: 1
        border.color: toggle.on ? root.theme.accent : root.theme.border
        Behavior on color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }

        Text {
            anchors.centerIn: parent
            text: toggle.glyph
            color: toggle.on ? root.theme.onAccent : root.theme.dim
            font.family: root.theme.iconFont
            font.pixelSize: 12 * root.s
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    Toggle {
        glyph: "󰖔"
        on: root.dnd
        onToggled: root.dndToggled()
    }

    Toggle {
        glyph: "󰸉"
        on: false
        onToggled: {
            if (root.onOpenWallpaper)
                root.onOpenWallpaper()
        }
    }
}
