import QtQuick
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../lib/battery.js" as Battery

Row {
    id: root

    property var theme
    property real s: 1

    signal wifiClicked()
    signal bluetoothClicked()
    signal batteryClicked()

    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool wifiConnected: Networking.devices.values.some(device => device.connected === true)
    readonly property bool bluetoothOn: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
    readonly property bool bluetoothConnected: Bluetooth.devices.values.some(device => device.connected === true)
    readonly property int batteryLevel: UPower.displayDevice
        ? Math.round(UPower.displayDevice.percentage * 100)
        : -1
    readonly property bool charging: UPower.displayDevice
        && (UPower.displayDevice.state === UPowerDeviceState.Charging
            || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)

    function batteryColour() {
        switch (Battery.tone(root.batteryLevel, root.charging)) {
        case "charging": return root.theme.accent;
        case "danger": return root.theme.danger;
        case "warning": return "#f4b860";
        case "healthy": return "#79d2a6";
        default: return root.theme.dim;
        }
    }

    spacing: 7 * s

    Text {
        id: wifiIcon
        objectName: "pillWifiIcon"
        text: "\uf1eb"
        color: wifiHover.hovered
            ? root.theme.bright
            : (root.wifiOn ? (root.wifiConnected ? root.theme.cream : root.theme.dim) : root.theme.faint)
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s

        HoverHandler {
            id: wifiHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.wifiClicked()
        }
    }

    Text {
        id: bluetoothIcon
        objectName: "pillBluetoothIcon"
        text: "\uf293"
        color: bluetoothHover.hovered
            ? root.theme.bright
            : (root.bluetoothOn ? (root.bluetoothConnected ? root.theme.cream : root.theme.dim) : root.theme.faint)
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s

        HoverHandler {
            id: bluetoothHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.bluetoothClicked()
        }
    }

    Text {
        id: batteryIcon
        objectName: "pillBatteryIcon"
        text: Battery.icon(root.batteryLevel, root.charging)
        color: batteryHover.hovered
            ? root.theme.bright
            : root.batteryColour()
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s

        HoverHandler {
            id: batteryHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.batteryClicked()
        }
    }
}
