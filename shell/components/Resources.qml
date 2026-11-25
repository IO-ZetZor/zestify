import QtQuick

Item {
    id: root

    property var theme
    property var stats
    property var motion
    property real s: 1
    property real pulse: 0
    readonly property bool overloaded: !!stats && Number.isFinite(stats.cpuPercent) && stats.cpuPercent > 90
    readonly property bool animating: overloaded && visible && enabled
        && !(motion && motion.calm)

    signal clicked()

    implicitWidth: 22 * s
    implicitHeight: 22 * s
    visible: overloaded
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "High CPU usage: open System"
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    onAnimatingChanged: if (!animating) pulse = 0

    Text {
        objectName: "resourceCpuIcon"
        anchors.centerIn: parent
        text: "󰻠"
        color: root.theme.danger
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s
        scale: 1 + 0.12 * root.pulse
        opacity: root.animating ? 0.55 + 0.45 * root.pulse : 1
    }

    SequentialAnimation {
        running: root.animating
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "pulse"; from: 0; to: 1; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "pulse"; from: 1; to: 0; duration: 650; easing.type: Easing.InOutSine }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler {
        onTapped: root.clicked()
    }
}
