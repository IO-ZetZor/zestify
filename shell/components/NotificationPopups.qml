pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root

    property var targetScreen
    property var theme
    property real uiScale: 1
    property var motion
    property bool enabled: true

    readonly property real s: targetScreen
        ? LayoutLib.pillScale(targetScreen.width, targetScreen.height) * uiScale
        : 1
    readonly property real cardWidth: targetScreen
        ? Math.min(380 * s, targetScreen.width - 32 * s)
        : 320

    screen: targetScreen
    visible: enabled && Notifications.popups.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.top: true
    anchors.right: true

    implicitWidth: cardWidth
    implicitHeight: column.implicitHeight
    margins.top: 14 * s
    margins.right: 14 * s

    function iconSource(entry) {
        const icon = entry && entry.appIcon ? String(entry.appIcon) : "";
        if (icon.length === 0)
            return "";
        if (icon.indexOf("/") >= 0 || icon.indexOf("file:") === 0)
            return icon;
        if (Quickshell.hasThemeIcon(icon))
            return Quickshell.iconPath(icon);
        return "";
    }

    Column {
        id: column

        width: parent.width
        spacing: 8 * root.s

        Repeater {
            model: Notifications.popups

            delegate: Rectangle {
                id: card
                required property var modelData

                width: column.width
                height: cardContent.implicitHeight + 20 * root.s
                radius: root.theme.r.tile * root.s
                color: root.theme.withAlpha(root.theme.surfaceHigh, 0.92)
                border.width: 1
                border.color: {
                    const urgency = String(card.modelData.urgency);
                    if (urgency === "Critical")
                        return root.theme.danger;
                    if (urgency === "Low")
                        return root.theme.withAlpha(root.theme.outline, 0.5);
                    return root.theme.border;
                }

                TapHandler {
                    onTapped: Notifications.dismiss(card.modelData.id)
                }

                Column {
                    id: cardContent

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10 * root.s
                    spacing: 4 * root.s

                    RowLayout {
                        width: parent.width
                        spacing: 7 * root.s

                        Item {
                            Layout.preferredWidth: 24 * root.s
                            Layout.preferredHeight: 24 * root.s

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: root.iconSource(card.modelData)
                                visible: source.toString().length > 0
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: "󰂚"
                                color: root.theme.accent
                                font.family: root.theme.iconFont
                                font.pixelSize: 19 * root.s
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1 * root.s

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.appName
                                color: root.theme.faint
                                elide: Text.ElideRight
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fs.label * root.s
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary
                                color: root.theme.cream
                                elide: Text.ElideRight
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fs.body * root.s
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 18 * root.s
                            Layout.preferredHeight: 18 * root.s
                            radius: width / 2
                            color: closeArea.containsMouse
                                ? root.theme.withAlpha(root.theme.danger, 0.2)
                                : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: closeArea.containsMouse ? root.theme.danger : root.theme.faint
                                font.family: root.theme.iconFont
                                font.pixelSize: 12 * root.s
                            }

                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifications.dismiss(card.modelData.id)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: card.modelData.body
                        color: root.theme.dim
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fs.meta * root.s
                    }
                }

                Timer {
                    interval: card.modelData.expires > 0 ? card.modelData.expires : 5000
                    running: true
                    onTriggered: Notifications.expirePopup(card.modelData.id)
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.motion ? root.motion.fast : 140
                    }
                }
            }
        }
    }
}
