import QtQuick

Text {
    id: root

    property var theme
    property real s: 1
    property date now: new Date()

    signal clicked()

    text: Qt.formatDateTime(now, "HH:mm")
    color: theme.cream
    font.family: theme.fontFamily
    font.pixelSize: theme.fs.title * s
    font.weight: Font.Medium
    onVisibleChanged: if (visible) root.now = new Date()

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Timer {
        interval: Math.max(1, 60000 - root.now.getTime() % 60000)
        repeat: true
        running: root.visible
        onTriggered: root.now = new Date()
    }
}
