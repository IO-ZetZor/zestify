import QtQuick
import QtQuick.Effects

Item {
    id: root
    property var theme
    property real s: 1
    property url source: ""
    property bool playing: false
    property bool active: true
    property color ringColor: theme ? theme.accent : "#bfc4ee"
    readonly property alias angle: disc.rotation
    readonly property bool rotating: spin.running && !spin.paused

    implicitWidth: 180 * s
    implicitHeight: implicitWidth

    Rectangle {
        objectName: "albumRing"
        anchors.centerIn: parent
        width: Math.min(root.width, root.height)
        height: width
        radius: width / 2
        color: root.theme.withAlpha(root.theme.tileBg, 0.35)
        border.width: 4 * root.s
        border.color: root.ringColor

        Item {
            id: disc
            anchors.fill: parent
            anchors.margins: 8 * root.s

            Rectangle {
                id: mask
                anchors.fill: parent
                radius: width / 2
                color: "white"
                antialiasing: true
                visible: false
                layer.enabled: true
                layer.smooth: true
            }
            Image {
                id: art
                anchors.fill: parent
                source: root.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                mipmap: true
                sourceSize.width: Math.max(1, Math.round(width * 2))
                sourceSize.height: Math.max(1, Math.round(height * 2))
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: art
                maskEnabled: true
                maskSource: mask
                visible: art.status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                visible: art.status !== Image.Ready
                radius: width / 2
                color: root.theme.withAlpha(root.theme.cream, 0.06)
                Text {
                    anchors.centerIn: parent
                    text: "󰎆"
                    color: root.theme.faint
                    font.family: root.theme.iconFont
                    font.pixelSize: parent.width * 0.32
                }
            }
            NumberAnimation on rotation {
                id: spin
                from: 0
                to: 360
                duration: 24000
                loops: Animation.Infinite
                running: true
                paused: !root.playing || !root.active || !root.visible
            }
        }
    }
}
