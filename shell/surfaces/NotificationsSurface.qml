pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../components"
import "../singletons"

SurfaceFrame {
    id: root
    property var motion
    title: "Notifications"

    component ActionButton: Button {
        id: button
        implicitHeight: 32 * root.s
        contentItem: Text {
            text: button.text
            color: button.checked || button.hovered ? root.theme.accent : root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9 * root.s
            color: button.checked || button.hovered ? root.theme.withAlpha(root.theme.accent, 0.14) : "transparent"
            border.width: 1
            border.color: button.activeFocus ? root.theme.accent : root.theme.border
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12 * root.s
        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                text: "Do not disturb"
                checkable: true
                checked: Notifications.dnd
                onClicked: Notifications.toggleDnd()
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: "Close"
                onClicked: root.closeRequested()
            }
            ActionButton {
                text: "Clear all"
                enabled: Notifications.history.length > 0
                opacity: enabled ? 1 : 0.4
                onClicked: Notifications.clear()
            }
        }
        Text {
            Layout.fillWidth: true
            text: Notifications.dnd ? "Popups paused · Notifications are saved here"
                : Notifications.history.length + (Notifications.history.length === 1 ? " notification" : " notifications")
            color: root.theme.faint
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
            wrapMode: Text.Wrap
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
                anchors.fill: parent
                clip: true
                spacing: 8 * root.s
                model: Notifications.history
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: NotificationCard {
                    required property var modelData
                    width: ListView.view.width - 10 * root.s
                    height: implicitHeight
                    theme: root.theme
                    motion: root.motion
                    s: root.s
                    entry: modelData
                    iconSource: {
                        const icon = modelData.appIcon || "";
                        if (!icon) return "";
                        return icon.indexOf("/") >= 0 ? icon
                            : (Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "");
                    }
                    onDismissed: Notifications.dismiss(modelData.id)
                    onActionActivated: identifier => Notifications.invokeAction(modelData.id, identifier)
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                visible: Notifications.history.length === 0
                spacing: 12 * root.s
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰂛"
                    color: root.theme.accent
                    font.family: root.theme.iconFont
                    font.pixelSize: 36 * root.s
                }
                Text {
                    text: "You're all caught up"
                    color: root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.title * root.s
                }
            }
        }
    }
}
