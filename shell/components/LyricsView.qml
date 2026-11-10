pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var theme
    property var provider
    property var players
    property real s: 1
    color: theme.withAlpha(theme.cream, 0.035)
    radius: theme.r.tile * s
    border.width: 1
    border.color: theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12 * root.s
        spacing: 8 * root.s
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Lyrics"
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.body * root.s
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.provider.attribution + (root.provider.synced ? " · Synced" : "")
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
                id: list
                objectName: "lyricsList"
                anchors.fill: parent
                clip: true
                model: root.provider.lines
                spacing: 10 * root.s
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.provider.currentIndex
                function followCurrent() {
                    Qt.callLater(() => {
                        if (currentIndex >= 0 && !moving && !dragging)
                            positionViewAtIndex(currentIndex, ListView.Center);
                    });
                }
                onCurrentIndexChanged: followCurrent()
                onHeightChanged: followCurrent()
                onCountChanged: followCurrent()
                onMovementEnded: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Center)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Text {
                    required property var modelData
                    required property int index
                    width: list.width - 10 * root.s
                    text: modelData.text || "♪"
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.provider.synced && index === list.currentIndex ? root.theme.accent : root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.title * root.s
                    font.weight: index === list.currentIndex ? Font.DemiBold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.provider.synced && root.provider.player && root.provider.player.canSeek
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.players.seek(parent.modelData.time)
                    }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                visible: root.provider.status !== "ready"
                Text {
                    Layout.fillWidth: true
                    text: root.provider.status === "loading" ? "Finding lyrics…"
                        : root.provider.status === "instrumental" ? "Instrumental · Enjoy the music"
                        : root.provider.status === "error" ? "Couldn't load lyrics"
                        : root.provider.status === "idle" ? "Play a song to see its lyrics" : "No lyrics found for this track"
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.provider.status === "error"
                    text: "Try again"
                    color: root.theme.accent
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.provider.refresh() }
                }
            }
        }
    }
}
