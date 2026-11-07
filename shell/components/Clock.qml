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

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }
}
