import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: root

    property var theme
    property var screen
    property var wallpapers
    property var motion
    property real s: 1
    property string folder: ""

    property bool allMonitors: false
    property string selectedPath: ""

    readonly property string monitorName: screen ? screen.name : ""
    readonly property int columns: 2
    readonly property real cellWidth: width / columns
    readonly property real cellHeight: cellWidth * 0.5625  // 16:9
    readonly property bool empty: wallpapers !== null && wallpapers !== undefined
        && !wallpapers.listing && wallpapers.items.length === 0
    readonly property bool loading: wallpapers !== null && wallpapers !== undefined
        && (wallpapers.busy || wallpapers.listing)

    function applySelected(all) {
        if (!selectedPath.length || !wallpapers)
            return;
        if (all)
            wallpapers.applyAll(selectedPath);
        else
            wallpapers.apply(selectedPath, monitorName);
    }

    component Segment: Rectangle {
        id: segment

        property string label
        property bool selected
        signal clicked()

        implicitWidth: segmentLabel.implicitWidth + 20 * root.s
        implicitHeight: 24 * root.s
        radius: height / 2
        color: segment.selected
            ? root.theme.accent
            : (segmentArea.containsMouse
                ? root.theme.withAlpha(root.theme.cream, 0.08)
                : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: segmentLabel
            anchors.centerIn: parent
            text: segment.label
            color: segment.selected ? root.theme.onAccent : root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        MouseArea {
            id: segmentArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: segment.clicked()
        }
    }

    component ActionButton: Rectangle {
        id: button

        property string label
        property bool primary: false
        property bool active: true
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 24 * root.s
        implicitHeight: 26 * root.s
        radius: root.theme.r.s * root.s
        opacity: button.active ? 1 : 0.55
        color: !button.active || !button.primary
            ? (buttonArea.containsMouse && button.active
                ? root.theme.withAlpha(root.theme.cream, 0.10)
                : root.theme.tileBg)
            : (buttonArea.containsMouse ? root.theme.accentDim : root.theme.accent)
        border.width: 1
        border.color: button.primary && button.active ? button.color : root.theme.border
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            color: button.primary && button.active ? root.theme.onAccent : root.theme.cream
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            enabled: button.active
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.theme.sp.m * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: root.theme.sp.s * root.s

            Text {
                Layout.fillWidth: true
                text: root.folder
                color: root.theme.faint
                elide: Text.ElideMiddle
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.meta * root.s
            }

            Text {
                visible: root.loading
                text: "…"
                color: root.theme.accent
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.title * root.s
            }

            Rectangle {
                implicitWidth: monitorSegments.implicitWidth + 4 * root.s
                implicitHeight: 26 * root.s
                radius: height / 2
                color: root.theme.tileBg
                border.width: 1
                border.color: root.theme.border

                Row {
                    id: monitorSegments
                    anchors.centerIn: parent
                    spacing: 2 * root.s

                    Segment {
                        label: "This monitor"
                        selected: !root.allMonitors
                        onClicked: root.allMonitors = false
                    }

                    Segment {
                        label: "All monitors"
                        selected: root.allMonitors
                        onClicked: root.allMonitors = true
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid
                anchors.fill: parent
                clip: true
                cellWidth: root.cellWidth
                cellHeight: root.cellHeight
                model: root.wallpapers ? root.wallpapers.items : []

                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    readonly property bool selected: root.selectedPath === modelData.path
                    readonly property bool current: modelData.path === (root.wallpapers
                        ? root.wallpapers.currentFor(root.monitorName) : "")

                    Rectangle {
                        id: card
                        anchors.fill: parent
                        anchors.margins: 7 * root.s
                        radius: root.theme.r.tile * root.s
                        color: root.theme.tileBg
                        clip: true

                        Item {
                            id: cardContent
                            anchors.fill: parent
                            visible: false

                            Image {
                                id: thumb
                                anchors.fill: parent
                                source: modelData.thumb
                                asynchronous: true
                                cache: true
                                smooth: true
                                mipmap: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: Math.max(400, Math.round(Math.max(width, height) * 2))
                                sourceSize.height: Math.max(400, Math.round(Math.max(width, height) * 2))
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: thumb.status === Image.Error
                                    || String(thumb.source).length === 0
                                text: "󰸉"
                                color: root.theme.faint
                                font.family: root.theme.iconFont
                                font.pixelSize: 26 * root.s
                            }

                            Rectangle {
                                visible: modelData.isVideo
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 7 * root.s
                                width: 22 * root.s
                                height: 22 * root.s
                                radius: width / 2
                                color: root.theme.withAlpha(root.theme.surface, 0.72)
                                border.width: 1
                                border.color: root.theme.hairline

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰐊"
                                    color: root.theme.cream
                                    font.family: root.theme.iconFont
                                    font.pixelSize: 10 * root.s
                                }
                            }

                            Rectangle {
                                visible: current
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 7 * root.s
                                width: 18 * root.s
                                height: 18 * root.s
                                radius: width / 2
                                color: root.theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄬"
                                    color: root.theme.onAccent
                                    font.family: root.theme.iconFont
                                    font.pixelSize: 9 * root.s
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 42 * root.s
                                opacity: thumbArea.containsMouse ? 1 : 0
                                visible: opacity > 0
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0
                                        color: root.theme.withAlpha(root.theme.surface, 0)
                                    }
                                    GradientStop {
                                        position: 1
                                        color: root.theme.withAlpha(root.theme.surface, 0.72)
                                    }
                                }
                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 7 * root.s
                                    text: modelData.name
                                    color: root.theme.cream
                                    elide: Text.ElideMiddle
                                    font.family: root.theme.monoFont
                                    font.pixelSize: root.theme.fs.label * root.s
                                }
                            }
                        }

                        Rectangle {
                            id: roundedMask
                            anchors.fill: parent
                            radius: card.radius
                            color: "white"
                            visible: false
                            layer.enabled: true
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: cardContent
                            maskEnabled: true
                            maskSource: roundedMask
                        }

                        Rectangle {
                            anchors.fill: parent
                            z: 2
                            radius: card.radius
                            color: "transparent"
                            border.width: selected ? 2 * root.s : 1 * root.s
                            border.color: selected
                                ? root.theme.accent
                                : (thumbArea.containsMouse
                                    ? root.theme.withAlpha(root.theme.accent, 0.55)
                                    : root.theme.border)
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: thumbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedPath = modelData.path
                            onDoubleClicked: {
                                root.selectedPath = modelData.path;
                                root.applySelected(root.allMonitors);
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 6 * root.s
                visible: root.empty

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰸉"
                    color: root.theme.faint
                    font.family: root.theme.iconFont
                    font.pixelSize: 30 * root.s
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No wallpapers found"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.folder
                    color: root.theme.faint
                    elide: Text.ElideMiddle
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.meta * root.s
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 24 * root.s
                visible: grid.contentHeight > grid.height + 1
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: root.theme.withAlpha(root.theme.surfaceLow, 0)
                    }
                    GradientStop {
                        position: 1
                        color: root.theme.withAlpha(root.theme.surfaceLow, 0.9)
                    }
                }
            }
        }

        Text {
            visible: text.length > 0
            text: root.wallpapers ? root.wallpapers.lastError : ""
            color: root.theme.danger
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.theme.sp.s * root.s

            ActionButton {
                label: "Random"
                onClicked: root.wallpapers.random(root.allMonitors ? "" : root.monitorName)
            }

            Item { Layout.fillWidth: true }

            ActionButton {
                label: root.allMonitors ? "Apply to all" : "Apply"
                primary: true
                active: root.selectedPath.length > 0
                onClicked: root.applySelected(root.allMonitors)
            }
        }
    }

    Component.onCompleted: if (root.wallpapers) root.wallpapers.refresh()
}
