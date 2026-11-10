import QtQuick
import QtQuick.Layouts

/**
 * Common chrome for expanded surfaces: title and optional back button.
 * Surfaces declare their content as ordinary children; the default property
 * forwards them into the body, directly on the pill surface.
 */
Item {
    id: root

    property var theme
    property real s: 1
    property string title: ""
    property bool showBack: false

    default property alias content: body.data

    signal closeRequested()
    signal backRequested()

    implicitWidth: 420
    implicitHeight: 340

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10 * root.s
        spacing: 8 * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * root.s

            Rectangle {
                visible: root.showBack
                Layout.preferredWidth: 22 * root.s
                Layout.preferredHeight: 22 * root.s
                radius: 6 * root.s
                color: backArea.containsMouse
                    ? (root.theme ? root.theme.withAlpha(root.theme.accent, 0.18) : "transparent")
                    : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰁍"
                    color: root.theme ? root.theme.dim : "#ffffff"
                    font.family: root.theme ? root.theme.iconFont : ""
                    font.pixelSize: 12 * root.s
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.backRequested()
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.title
                color: root.theme ? root.theme.cream : "#ffffff"
                font.family: root.theme ? root.theme.fontFamily : ""
                font.pixelSize: root.theme ? root.theme.fs.title * root.s : 15
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
        }
    }
}
