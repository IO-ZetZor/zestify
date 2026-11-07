pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

SurfaceFrame {
    id: root

    property var screen
    property var motion

    // qmllint disable missing-property
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sink: {
        const device = Pipewire.defaultAudioSink;
        if (!device)
            return null;
        return nodes.find(node => node.id === device.id) || device;
    }
    readonly property var source: {
        const device = Pipewire.defaultAudioSource;
        if (!device)
            return null;
        return nodes.find(node => node.id === device.id) || device;
    }
    readonly property var sinks: nodes.filter(node => node.isSink && !node.isStream && node.audio)
    readonly property var sources: nodes.filter(node => !node.isSink && !node.isStream && node.audio)
    readonly property var streams: nodes.filter(node => node.isStream && node.audio)

    title: "Audio"

    function volumeText(node) {
        return node && node.audio ? Math.round(node.audio.volume * 100) + "%" : "--";
    }

    function streamName(node) {
        if (!node)
            return "Unknown application";
        return node.properties["application.name"]
            || node.properties["application.process.binary"]
            || node.description
            || node.name
            || "Unknown application";
    }

    component VolumeSlider: Item {
        id: slider

        property real value: 0

        signal moved(real value)

        Layout.fillWidth: true
        Layout.preferredHeight: 14 * root.s

        function updateFromX(x) {
            const next = Math.max(0, Math.min(1, x / Math.max(1, slider.width)));
            slider.moved(next);
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4 * root.s
            radius: height / 2
            color: root.theme.withAlpha(root.theme.outline, 0.35)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, slider.width * slider.value)
            height: 4 * root.s
            radius: height / 2
            color: root.theme.accent
        }

        Rectangle {
            x: Math.max(0, Math.min(slider.width - width, slider.width * slider.value - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 10 * root.s
            height: 10 * root.s
            radius: width / 2
            color: root.theme.accent
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => slider.updateFromX(mouse.x)
            onPositionChanged: (mouse) => {
                if (pressed)
                    slider.updateFromX(mouse.x);
            }
        }
    }

    component MuteButton: Rectangle {
        id: mute

        property var node
        property bool active: node && node.audio ? node.audio.muted : false

        Layout.preferredWidth: 26 * root.s
        Layout.preferredHeight: 26 * root.s
        radius: 7 * root.s
        color: mute.active
            ? root.theme.withAlpha(root.theme.danger, 0.18)
            : (muteArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.06) : "transparent")
        border.width: 1
        border.color: mute.active ? root.theme.withAlpha(root.theme.danger, 0.5) : root.theme.border

        Text {
            anchors.centerIn: parent
            text: mute.active ? "󰝟" : "󰕾"
            color: mute.active ? root.theme.danger : root.theme.dim
            font.family: root.theme.iconFont
            font.pixelSize: 13 * root.s
        }

        MouseArea {
            id: muteArea
            anchors.fill: parent
            enabled: mute.node && mute.node.audio
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (mute.node && mute.node.audio) mute.node.audio.muted = !mute.node.audio.muted
        }
    }

    component DeviceCard: Rectangle {
        id: card

        property var node
        property string label

        Layout.fillWidth: true
        Layout.preferredHeight: 68 * root.s
        radius: root.theme.r.tile * root.s
        color: root.theme.tileBg
        border.width: 1
        border.color: root.theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.theme.sp.m * root.s
            spacing: 2 * root.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 6 * root.s

                Text {
                    text: card.label
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                Text {
                    Layout.fillWidth: true
                    text: card.node ? (card.node.description || card.node.name) : "No device"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                    elide: Text.ElideRight
                }

                Text {
                    text: root.volumeText(card.node)
                    color: root.theme.dim
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.meta * root.s
                }

                MuteButton { node: card.node }
            }

            VolumeSlider {
                value: card.node && card.node.audio ? card.node.audio.volume : 0
                onMoved: function(value) {
                    if (card.node && card.node.audio)
                        card.node.audio.volume = value;
                }
            }
        }
    }

    component DeviceChip: Rectangle {
        id: chip

        property var node
        property bool current: false

        Layout.fillWidth: true
        Layout.preferredHeight: 24 * root.s
        radius: 6 * root.s
        color: chip.current
            ? root.theme.withAlpha(root.theme.accent, 0.2)
            : (chipArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.06) : "transparent")
        border.width: 1
        border.color: chip.current ? root.theme.accent : root.theme.hairline

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 7 * root.s
            anchors.rightMargin: 7 * root.s
            text: chip.node ? (chip.node.description || chip.node.name) : ""
            color: chip.current ? root.theme.cream : root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
            elide: Text.ElideRight
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!chip.node)
                    return;
                if (chip.node.isSink)
                    Pipewire.preferredDefaultAudioSink = chip.node;
                else
                    Pipewire.preferredDefaultAudioSource = chip.node;
            }
        }
    }

    component StreamRow: Rectangle {
        id: stream

        property var node

        Layout.fillWidth: true
        Layout.preferredHeight: 34 * root.s
        implicitHeight: 34 * root.s
        height: 34 * root.s
        radius: 6 * root.s
        color: root.theme.tileBg

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.theme.sp.m * root.s
            anchors.rightMargin: root.theme.sp.m * root.s
            spacing: 6 * root.s

            Text {
                Layout.fillWidth: true
                text: root.streamName(stream.node)
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
                elide: Text.ElideRight
            }

            VolumeSlider {
                Layout.fillWidth: false
                Layout.preferredWidth: 120 * root.s
                value: stream.node && stream.node.audio ? stream.node.audio.volume : 0
                onMoved: function(value) {
                    if (stream.node && stream.node.audio)
                        stream.node.audio.volume = value;
                }
            }

            Text {
                text: root.volumeText(stream.node)
                color: root.theme.dim
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.label * root.s
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 34 * root.s
            }

            MuteButton { node: stream.node }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * root.s

        DeviceCard {
            label: "Output"
            node: root.sink
        }

        DeviceCard {
            label: "Input"
            node: root.source
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * root.s

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3 * root.s

                Text {
                    text: "Output devices"
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                Repeater {
                    model: root.sinks
                    delegate: DeviceChip {
                        required property var modelData
                        node: modelData
                        current: root.sink === modelData
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3 * root.s

                Text {
                    text: "Input devices"
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                Repeater {
                    model: root.sources
                    delegate: DeviceChip {
                        required property var modelData
                        node: modelData
                        current: root.source === modelData
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * root.s

            Text {
                Layout.fillWidth: true
                text: "Applications"
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.title * root.s
                font.weight: Font.Medium
            }

            Text {
                visible: root.streams.length === 0
                text: "No active streams"
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4 * root.s
            clip: true
            model: root.streams

            delegate: StreamRow {
                required property var modelData
                width: ListView.view.width
                node: modelData
            }
        }
    }
}
