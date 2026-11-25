import QtQuick

Item {
    id: root
    property var theme
    property real s: 1
    property url source: ""
    property bool playing: false
    property bool active: true
    property color ringColor: theme ? theme.accent : "#bfc4ee"
    property int longPressDuration: 550
    property bool interactive: true
    property bool pressedLong: false
    property bool fillContainer: false
    // Fix the decode/layer size while party mode changes the cover geometry.
    property int artSize: 0
    readonly property int textureResolution: artSize > 0 ? artSize
        : Math.max(1, Math.ceil(Math.min(width, height) * 4))
    readonly property alias angle: art.rotation
    readonly property bool rotating: spin.running && !spin.paused

    signal clicked()
    signal longPressed()

    implicitWidth: 180 * s
    implicitHeight: implicitWidth
    scale: pressArea.pressed && !root.pressedLong ? 0.975 : 1

    Behavior on scale {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        objectName: "albumRing"
        anchors.centerIn: parent
        width: root.fillContainer ? root.width : Math.min(root.width, root.height)
        height: root.fillContainer ? root.height : width
        radius: Math.min(width, height) / 2
        antialiasing: true
        color: root.theme.withAlpha(root.theme.tileBg, 0.35)
        border.width: 4 * root.s
        border.color: root.ringColor

        Item {
            id: disc
            anchors.fill: parent
            anchors.margins: 8 * root.s
            Image {
                id: art
                objectName: "albumArtwork"
                anchors.centerIn: parent
                width: Math.max(parent.width, parent.height)
                height: width
                visible: false
                source: root.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                sourceSize.width: root.textureResolution
                sourceSize.height: root.textureResolution
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
            ShaderEffect {
                objectName: "coverMask"
                anchors.fill: parent
                // Sample the cached Image directly. Rotation, crop and capsule
                // coverage need no source capture, mask texture or outer layer.
                property var source: art
                property vector2d shapeSize: Qt.vector2d(width, height)
                property vector2d cropScale: Qt.vector2d(
                    Math.min(1, art.implicitHeight / Math.max(1, art.implicitWidth)),
                    Math.min(1, art.implicitWidth / Math.max(1, art.implicitHeight)))
                property real rotationRadians: art.rotation * Math.PI / 180
                fragmentShader: "../shaders/album-cover.frag.qsb"
                visible: art.status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                visible: art.status !== Image.Ready
                radius: Math.min(width, height) / 2
                antialiasing: true
                color: root.theme.withAlpha(root.theme.cream, 0.06)
                Text {
                    anchors.centerIn: parent
                    text: "󰎆"
                    color: root.theme.faint
                    font.family: root.theme.iconFont
                    font.pixelSize: parent.width * 0.32
                }
            }
        }
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onPressed: {
            root.pressedLong = false;
            holdTimer.restart();
        }
        onReleased: {
            holdTimer.stop();
            if (!root.pressedLong && pressArea.containsMouse)
                root.clicked();
        }
        onCanceled: {
            holdTimer.stop();
            root.pressedLong = false;
        }

        Timer {
            id: holdTimer
            interval: root.longPressDuration
            onTriggered: {
                if (!root.visible || !pressArea.pressed || !pressArea.containsMouse)
                    return;
                root.pressedLong = true;
                root.longPressed();
            }
        }
    }
}
