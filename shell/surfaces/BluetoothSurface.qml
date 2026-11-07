pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth

SurfaceFrame {
    id: root

    property var screen
    property var motion

    title: "Bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter
        ? adapter.devices.values.filter(device => {
            const name = device.deviceName || device.name || "";
            return name.length > 0;
        })
        : []
    readonly property var sortedDevices: {
        const copy = devices.slice();
        copy.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1;
            return deviceName(a).localeCompare(deviceName(b));
        });
        return copy;
    }

    function deviceName(device) {
        return device.deviceName || device.name || device.address || "Unknown device";
    }

    function deviceStatus(device) {
        if (device.pairing)
            return "Pairing…";
        if (device.connected)
            return "Connected";
        if (device.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (device.paired)
            return "Paired";
        return "Available";
    }

    function batteryText(device) {
        if (!device.batteryAvailable)
            return "";
        const value = device.battery <= 1 ? device.battery * 100 : device.battery;
        return Math.round(value) + "%";
    }

    function busyFor(device) {
        return device.pairing
            || device.state === BluetoothDeviceState.Connecting
            || device.state === BluetoothDeviceState.Disconnecting;
    }

    function toggleDevice(device) {
        if (!device)
            return;
        if (device.pairing) {
            device.cancelPair();
            return;
        }
        if (!device.paired) {
            device.pair();
            return;
        }
        if (device.connected)
            device.disconnect();
        else
            device.connect();
    }

    Component.onCompleted: {
        if (root.adapter)
            root.adapter.discovering = true;
    }

    Component.onDestruction: {
        if (root.adapter)
            root.adapter.discovering = false;
    }

    component ToggleSwitch: Rectangle {
        id: toggle

        property bool checked

        signal toggled()

        implicitWidth: 38 * root.s
        implicitHeight: 20 * root.s
        radius: height / 2
        color: toggle.checked ? root.theme.accent : root.theme.surfaceHigh
        border.width: 1
        border.color: toggle.checked ? root.theme.accent : root.theme.border

        Rectangle {
            width: 14 * root.s
            height: width
            radius: width / 2
            y: (parent.height - height) / 2
            x: toggle.checked ? parent.width - width - 3 * root.s : 3 * root.s
            color: toggle.checked ? root.theme.onAccent : root.theme.dim

            Behavior on x {
                NumberAnimation {
                    duration: root.motion ? root.motion.fast : 140
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * root.s

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1 * root.s

                Text {
                    text: "Bluetooth"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                    font.weight: Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    text: root.adapter
                        ? (root.adapter.enabled
                            ? (root.adapter.discovering ? "Scanning for devices…" : "Ready")
                            : "Bluetooth is off")
                        : "No Bluetooth adapter"
                    color: root.theme.faint
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                }
            }

            Rectangle {
                visible: root.adapter && root.adapter.enabled
                Layout.preferredWidth: 56 * root.s
                Layout.preferredHeight: 20 * root.s
                radius: root.theme.r.s * root.s
                color: scanArea.containsMouse
                    ? root.theme.withAlpha(root.theme.accent, 0.18)
                    : "transparent"
                border.width: 1
                border.color: root.theme.border

                Text {
                    anchors.centerIn: parent
                    text: root.adapter && root.adapter.discovering ? "Scanning" : "Scan"
                    color: root.adapter && root.adapter.discovering ? root.theme.accent : root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                MouseArea {
                    id: scanArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.adapter)
                            root.adapter.discovering = !root.adapter.discovering;
                    }
                }
            }

            ToggleSwitch {
                visible: root.adapter !== null
                checked: root.adapter ? root.adapter.enabled : false
                onToggled: {
                    if (root.adapter)
                        root.adapter.enabled = !root.adapter.enabled;
                }
            }
        }

        ListView {
            id: deviceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.adapter !== null && root.adapter.enabled
            clip: true
            model: root.sortedDevices
            spacing: 2 * root.s
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: deviceRow
                required property var modelData
                required property int index

                readonly property bool busy: root.busyFor(modelData)

                width: deviceList.width
                height: 44 * root.s
                radius: root.theme.r.s * root.s
                color: modelData.connected
                    ? root.theme.withAlpha(root.theme.accent, 0.13)
                    : (deviceHover.hovered ? root.theme.withAlpha(root.theme.cream, 0.05) : "transparent")

                HoverHandler {
                    id: deviceHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.toggleDevice(deviceRow.modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 * root.s
                    anchors.rightMargin: 8 * root.s
                    spacing: 8 * root.s

                    Text {
                        text: "󰂯"
                        color: deviceRow.modelData.connected ? root.theme.accent : root.theme.iconDim
                        font.family: root.theme.iconFont
                        font.pixelSize: root.theme.fs.title * root.s
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1 * root.s

                        Text {
                            Layout.fillWidth: true
                            text: root.deviceName(deviceRow.modelData)
                            color: root.theme.cream
                            elide: Text.ElideRight
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.body * root.s
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.deviceStatus(deviceRow.modelData)
                            color: deviceRow.modelData.connected ? root.theme.accent : root.theme.faint
                            elide: Text.ElideRight
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.label * root.s
                        }
                    }

                    Text {
                        visible: root.batteryText(deviceRow.modelData).length > 0
                        text: root.batteryText(deviceRow.modelData)
                        color: root.theme.dim
                        font.family: root.theme.monoFont
                        font.pixelSize: root.theme.fs.meta * root.s
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        id: busyGlyph
                        visible: deviceRow.busy
                        text: "󰑐"
                        color: root.theme.accent
                        font.family: root.theme.iconFont
                        font.pixelSize: root.theme.fs.title * root.s
                        Layout.alignment: Qt.AlignVCenter

                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: busyGlyph.visible
                        }
                    }

                    Text {
                        visible: deviceRow.modelData.connected && !deviceRow.busy
                        text: "󰄬"
                        color: root.theme.accent
                        font.family: root.theme.iconFont
                        font.pixelSize: root.theme.fs.title * root.s
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.adapter === null || !root.adapter.enabled
            text: root.adapter === null
                ? "No Bluetooth adapter found"
                : "Turn on Bluetooth to see nearby devices"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        Text {
            Layout.fillWidth: true
            visible: root.adapter !== null && root.adapter.enabled && root.sortedDevices.length === 0
            text: "Scanning for devices…"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }
    }
}
