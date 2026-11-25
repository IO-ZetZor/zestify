pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    objectName: "powerRemControl"

    property var theme
    property var motion
    property real s: 1
    property real angle: 0
    readonly property bool dragging: grip.pressed
    readonly property bool settling: flip.running
    readonly property bool calm: !!(motion && motion.calm)
    readonly property real radians: angle * Math.PI / 180
    readonly property real faceCosine: Math.cos(radians)
    readonly property real sideExposure: Math.abs(Math.sin(radians))
    readonly property real thickness: 4 * s
    readonly property real rimDiameter: width + 4 * s
    readonly property int textureResolution: Math.max(1, Math.ceil(width * Math.max(4, Screen.devicePixelRatio)))

    implicitWidth: 92 * s
    implicitHeight: implicitWidth
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Flip Rem portrait"
    Accessible.description: "Drag left or right, then release to settle to the closest face. Arrow keys flip; Home resets."

    function canonicalFace(value) {
        return ((Math.round(value / 180) % 2) + 2) % 2 * 180;
    }
    function turnTo(targetAngle) {
        flip.stop();
        if (calm || !visible || !enabled || Math.abs(targetAngle - angle) < 0.01) {
            angle = canonicalFace(targetAngle);
            return;
        }
        flip.from = angle;
        flip.to = targetAngle;
        flip.duration = Math.min(460, 220 + Math.abs(targetAngle - angle) * 1.2);
        flip.start();
    }
    function settleToFace() { turnTo(Math.round(angle / 180) * 180); }
    function flipFace(direction) {
        const targetAngle = (flip.running ? flip.to : Math.round(angle / 180) * 180) + direction * 180;
        turnTo(targetAngle);
    }
    function resetFace() { turnTo(Math.round(angle / 360) * 360); }
    function resetImmediately() { flip.stop(); angle = 0; }

    onVisibleChanged: if (!visible) resetImmediately()
    onEnabledChanged: if (!enabled) resetImmediately()
    onCalmChanged: if (calm && flip.running) {
        const targetAngle = flip.to;
        flip.stop();
        angle = canonicalFace(targetAngle);
    }
    Keys.onLeftPressed: flipFace(-1)
    Keys.onRightPressed: flipFace(1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
            resetFace();
            event.accepted = true;
        }
    }

    NumberAnimation {
        id: flip
        target: root
        property: "angle"
        easing.type: Easing.OutBack
        easing.overshoot: 0.85
        onFinished: root.angle = root.canonicalFace(to)
    }

    Rectangle {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 5 * root.s
        width: root.rimDiameter
        height: width
        radius: width / 2
        color: "black"
        opacity: 0.22
        antialiasing: true
        transform: Scale {
            origin.x: root.rimDiameter / 2
            origin.y: root.rimDiameter / 2
            xScale: Math.max(0.025, Math.abs(root.faceCosine)) + root.sideExposure * root.thickness / root.rimDiameter
        }
    }

    // Parallel elliptical slices form an extruded circular rim. Their small
    // overlap keeps the side solid even when the artwork is exactly edge-on.
    Repeater {
        model: 13
        delegate: Rectangle {
            required property int index
            readonly property real depth: (index / 12 - 0.5) * root.thickness
            objectName: "powerRemRim" + index
            x: (root.width - width) / 2 + Math.sin(root.radians) * depth
            y: (root.height - height) / 2
            width: root.rimDiameter
            height: width
            radius: width / 2
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(root.theme.accent, 1.65) }
                GradientStop { position: 0.18; color: root.theme.accent }
                GradientStop { position: 0.5; color: Qt.darker(root.theme.accent, 1.6) }
                GradientStop { position: 0.78; color: Qt.darker(root.theme.accent, 2.2) }
                GradientStop { position: 1; color: Qt.lighter(root.theme.accent, 1.25) }
            }
            transform: Scale {
                origin.x: root.rimDiameter / 2
                origin.y: root.rimDiameter / 2
                xScale: Math.max(0.012, Math.abs(root.faceCosine))
            }
        }
    }

    Item {
        id: coin
        objectName: "powerRemCoin"
        x: Math.sin(root.radians) * root.thickness / 2 * (root.faceCosine >= 0 ? 1 : -1)
        width: root.width
        height: root.height
        transform: Rotation {
            origin.x: coin.width / 2
            origin.y: coin.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: root.angle
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2 * root.s
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(root.theme.accent, 1.6) }
                GradientStop { position: 0.35; color: root.theme.accent }
                GradientStop { position: 1; color: Qt.darker(root.theme.accent, 1.8) }
            }
            border.width: 1
            border.color: root.theme.withAlpha(root.theme.cream, root.activeFocus ? 0.8 : 0.35)
            antialiasing: true
        }

        AnimatedImage {
            id: animation
            objectName: "powerRemAnimation"
            // Render the crop at texture resolution before it reaches the mask;
            // capturing a 92px item and enlarging that texture softened the art.
            width: root.textureResolution
            height: width
            source: root.visible ? "../assets/rem-smile.gif" : ""
            // Decode the full asset, including on scaled displays.
            fillMode: Image.PreserveAspectCrop
            visible: false
            playing: root.visible && !root.calm
            cache: false
            smooth: true
            mipmap: true
            Accessible.ignored: true
        }

        ShaderEffectSource {
            id: artworkTexture
            sourceItem: animation
            textureSize: Qt.size(root.textureResolution, root.textureResolution)
            hideSource: true
            live: root.visible
            smooth: true
            mipmap: true
            visible: false
        }

        ShaderEffect {
            objectName: "powerRemPortrait"
            anchors.fill: parent
            property var source: artworkTexture
            property real faceShade: 1 - root.sideExposure * 0.16
            property real sheen: root.sideExposure * 0.1
            fragmentShader: "../shaders/power-portrait.frag.qsb"
            visible: animation.status === Image.Ready
        }
    }

    // Keep input in an untransformed plane so the pointer grab remains stable,
    // even when the coin is edge-on or the pointer leaves the portrait.
    MouseArea {
        id: grip
        objectName: "powerRemGrip"
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pressX: 0
        property real startAngle: 0
        property bool resetClick: false
        onPressed: mouse => {
            root.forceActiveFocus();
            flip.stop();
            resetClick = false;
            pressX = mouse.x;
            startAngle = root.angle;
        }
        onPositionChanged: mouse => {
            if (pressed && !resetClick)
                root.angle = startAngle + (mouse.x - pressX) / Math.max(1, width) * 180;
        }
        onReleased: {
            if (!resetClick) root.settleToFace();
            resetClick = false;
        }
        onCanceled: {
            if (root.visible && root.enabled) root.settleToFace();
            else root.resetImmediately();
            resetClick = false;
        }
        onDoubleClicked: {
            resetClick = true;
            root.resetFace();
        }
    }
}
