import QtQuick
import QtQuick.Layouts
import "../singletons"

ColumnLayout {
    id: root
    property var theme
    property real s: 1
    spacing: 5 * s

    RowLayout {
        Layout.fillWidth: true
        spacing: 8 * root.s
        Text {
            Layout.fillWidth: true
            text: SpeedTest.status
            color: SpeedTest.state === "error" ? root.theme.danger : root.theme.faint
            font.family: root.theme.fontFamily
            font.pixelSize: 10 * root.s
            wrapMode: Text.Wrap
        }
        Rectangle {
            objectName: "speedTestButton"
            implicitWidth: label.implicitWidth + 20 * root.s
            implicitHeight: 26 * root.s
            radius: 7 * root.s
            color: root.theme.withAlpha(root.theme.accent, buttonArea.containsMouse ? 0.24 : 0.12)
            border.width: 1
            border.color: root.theme.withAlpha(root.theme.accent, 0.2)
            Text {
                id: label
                anchors.centerIn: parent
                text: SpeedTest.busy ? "Cancel" : SpeedTest.state === "done" ? "Test again" : "Speed test"
                color: root.theme.accent
                font.family: root.theme.fontFamily
                font.pixelSize: 10 * root.s
            }
            MouseArea {
                id: buttonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SpeedTest.busy ? SpeedTest.cancel() : SpeedTest.start()
            }
        }
    }

    RowLayout {
        visible: SpeedTest.state === "done"
        Layout.fillWidth: true
        spacing: 12 * root.s
        Repeater {
            model: [
                {label: "Download", value: SpeedTest.download.toFixed(1) + " Mbps"},
                {label: "Upload", value: SpeedTest.upload.toFixed(1) + " Mbps"},
                {label: "Latency", value: SpeedTest.latency.toFixed(1) + " ms"}
            ]
            delegate: ColumnLayout {
                id: metric
                required property var modelData
                Layout.fillWidth: true
                spacing: 2 * root.s
                Text {
                    text: metric.modelData.label
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: 9 * root.s
                }
                Text {
                    text: metric.modelData.value
                    color: root.theme.cream
                    font.family: root.theme.monoFont
                    font.pixelSize: 12 * root.s
                }
            }
        }
    }
}
