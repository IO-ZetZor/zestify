pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property var theme
    property var entry
    property real s: 1
    property var motion
    property string iconSource: ""
    property bool popup: false
    readonly property bool hovered: hover.hovered
    readonly property bool critical: String(entry.urgency).toLowerCase() === "critical"
    readonly property color accent: critical ? theme.danger : theme.accent
    readonly property var actions: entry.notification ? entry.notification.actions : []
    property real progress: 1
    signal dismissed()
    signal expired()
    signal actionActivated(string identifier)
    signal linkActivated(string link)

    implicitHeight: content.implicitHeight + 28 * s
    radius: theme.r.tile * s
    color: theme.withAlpha(theme.surfaceHigh, hovered ? 0.98 : 0.92)
    border.width: 1
    border.color: critical || hovered ? accent : theme.border
    Behavior on border.color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }
    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const action = root.actions.find(item => item.identifier === "default");
            if (action) root.actionActivated("default");
            else if (root.popup) root.dismissed();
        }
    }

    component ActionButton: Rectangle {
        id: button
        property string label
        property bool danger: false
        signal clicked()
        implicitWidth: Math.min(root.width - 28 * root.s, labelText.implicitWidth + 20 * root.s)
        implicitHeight: 28 * root.s
        radius: 8 * root.s
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        color: area.containsMouse || activeFocus
            ? root.theme.withAlpha(danger ? root.theme.danger : root.accent, 0.18) : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: root.accent
        Text {
            id: labelText
            anchors.centerIn: parent
            text: button.label
            textFormat: Text.PlainText
            width: Math.max(0, button.width - 16 * root.s)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: button.danger && area.containsMouse ? root.theme.danger : root.accent
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }
        Keys.onSpacePressed: event => { if (!event.isAutoRepeat) button.clicked(); }
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) button.clicked(); }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.clicked() }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14 * root.s
        spacing: 8 * root.s
        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * root.s
            Rectangle {
                Layout.preferredWidth: 34 * root.s
                Layout.preferredHeight: 34 * root.s
                radius: 10 * root.s
                color: root.theme.withAlpha(root.accent, 0.12)
                Image {
                    id: icon
                    anchors.fill: parent
                    anchors.margins: 6 * root.s
                    source: root.iconSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    anchors.centerIn: parent
                    visible: icon.status !== Image.Ready
                    text: root.critical ? "󰀪" : "󰂚"
                    color: root.accent
                    font.family: root.theme.iconFont
                    font.pixelSize: 18 * root.s
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2 * root.s
                Text {
                    Layout.fillWidth: true
                    text: root.entry.appName
                    textFormat: Text.PlainText
                    color: root.theme.dim
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                }
                Text {
                    Layout.fillWidth: true
                    text: (root.critical ? "Important · " : "") + Qt.formatDateTime(new Date(root.entry.time), "hh:mm")
                    color: root.critical ? root.accent : root.theme.faint
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.label * root.s
                }
            }
            ActionButton {
                objectName: "dismissNotification"
                label: "×"
                Accessible.name: "Dismiss notification"
                danger: true
                implicitWidth: 28 * root.s
                onClicked: root.dismissed()
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.entry.summary
            textFormat: Text.PlainText
            color: root.theme.cream
            wrapMode: Text.Wrap
            maximumLineCount: root.popup ? 3 : 5
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.entry.body
            textFormat: Text.StyledText
            onLinkActivated: link => root.linkActivated(link)
            linkColor: root.accent
            color: root.theme.dim
            wrapMode: Text.Wrap
            maximumLineCount: root.popup ? 5 : 12
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            lineHeight: 1.15
        }
        Image {
            Layout.fillWidth: true
            Layout.preferredHeight: 110 * root.s
            visible: status === Image.Ready
            source: root.entry.image || ""
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 720
        }
        Flow {
            Layout.fillWidth: true
            spacing: 4 * root.s
            visible: root.actions.length > 0
            Repeater {
                model: root.actions.filter(action => action.identifier !== "default")
                delegate: ActionButton {
                    required property var modelData
                    label: modelData.text
                    onClicked: root.actionActivated(modelData.identifier)
                }
            }
        }
    }
    Rectangle {
        visible: root.popup && root.entry.expires > 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5 * root.s
        anchors.left: parent.left
        anchors.leftMargin: 14 * root.s
        width: Math.max(0, (root.width - 28 * root.s) * root.progress)
        height: 2 * root.s
        radius: height / 2
        color: root.theme.withAlpha(root.accent, 0.55)
    }
    NumberAnimation on progress {
        from: 1
        to: 0
        duration: Math.max(1, root.entry.expires || 1)
        running: root.popup && root.entry.expires > 0
        paused: root.hovered
        onFinished: root.expired()
    }
}
