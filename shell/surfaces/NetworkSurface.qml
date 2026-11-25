pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../components"
import "../lib/format.js" as Format

SurfaceFrame {
    id: root

    property var screen
    property var motion

    title: "Network"

    readonly property var devices: Networking.devices.values
    property var wifiDevice: {
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i];
        }
        return null;
    }
    readonly property var networks: wifiDevice
        ? wifiDevice.networks.values.filter(network => network.name && network.name.length > 0)
        : []
    readonly property var sortedNetworks: {
        const copy = networks.slice();
        copy.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.known !== b.known)
                return a.known ? -1 : 1;
            return (b.signalStrength || 0) - (a.signalStrength || 0);
        });
        return copy;
    }
    readonly property var connectedNetwork: sortedNetworks.find(network => network.connected) || null
    readonly property string statusText: {
        if (!Networking.wifiEnabled)
            return "Wi-Fi is off";
        if (!Networking.wifiHardwareEnabled)
            return "Wi-Fi hardware is disabled";
        if (connectedNetwork)
            return connectedNetwork.name;
        return wifiDevice && wifiDevice.address ? "Not connected" : "No Wi-Fi device";
    }

    property var pendingNetwork: null
    property string password: ""
    property string errorText: ""
    property var scanDevice: null
    property bool ownsScan: false

    function releaseScan() {
        if (scanDevice && ownsScan)
            scanDevice.scannerEnabled = false;
        scanDevice = null;
        ownsScan = false;
    }

    function syncScan() {
        if (scanDevice === wifiDevice)
            return;
        releaseScan();
        cancelPassword();
        scanDevice = wifiDevice;
        if (scanDevice) {
            ownsScan = !scanDevice.scannerEnabled;
            scanDevice.scannerEnabled = true;
        }
    }
    onWifiDeviceChanged: syncScan()

    function securityName(network) {
        return WifiSecurityType.toString(network.security);
    }

    function isOpen(network) {
        return network.security === WifiSecurityType.Open;
    }

    function requestConnect(network) {
        if (!network)
            return;
        root.errorText = "";
        if (network.connected) {
            network.disconnect();
            return;
        }
        if (!network.known && !root.isOpen(network)) {
            root.pendingNetwork = network;
            root.password = "";
            passwordField.forceActiveFocus();
            return;
        }
        network.connect();
    }

    function submitPassword() {
        if (!root.pendingNetwork)
            return;
        if (root.password.length === 0) {
            root.errorText = "Password required";
            return;
        }
        root.pendingNetwork.connectWithPsk(root.password);
        root.pendingNetwork = null;
        root.password = "";
    }

    function cancelPassword() {
        root.pendingNetwork = null;
        root.password = "";
    }

    Component.onCompleted: syncScan()
    Component.onDestruction: releaseScan()

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
                    text: "Wi-Fi"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                    font.weight: Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    text: root.statusText
                    color: root.connectedNetwork ? root.theme.accent : root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                    elide: Text.ElideRight
                }
            }

            ToggleSwitch {
                checked: Networking.wifiEnabled
                onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            color: root.theme.danger
            wrapMode: Text.Wrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        ListView {
            id: networkList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Networking.wifiEnabled
            clip: true
            model: root.sortedNetworks
            spacing: 2 * root.s
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: networkRow
                required property var modelData
                required property int index

                readonly property bool busy: modelData.stateChanging
                    || modelData.state === ConnectionState.Connecting
                    || modelData.state === ConnectionState.Disconnecting

                width: networkList.width
                height: 44 * root.s
                radius: root.theme.r.s * root.s
                color: modelData.connected
                    ? root.theme.withAlpha(root.theme.accent, 0.13)
                    : (rowHover.hovered ? root.theme.withAlpha(root.theme.cream, 0.05) : "transparent")

                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.requestConnect(networkRow.modelData)
                }

                Connections {
                    target: networkRow.modelData

                    function onConnectionFailed(reason) {
                        root.errorText = Format.failureLabel(ConnectionFailReason.toString(reason));
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 * root.s
                    anchors.rightMargin: 8 * root.s
                    spacing: 8 * root.s

                    Text {
                        text: "\uf1eb"
                        color: networkRow.modelData.connected ? root.theme.accent : root.theme.iconDim
                        font.family: root.theme.iconFont
                        font.pixelSize: root.theme.fs.title * root.s
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1 * root.s

                        Text {
                            Layout.fillWidth: true
                            text: networkRow.modelData.name
                            color: root.theme.cream
                            elide: Text.ElideRight
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.body * root.s
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                let label = Format.securityLabel(root.securityName(networkRow.modelData));
                                if (label.length === 0)
                                    label = "Secured";
                                if (networkRow.modelData.connected && root.wifiDevice && root.wifiDevice.address)
                                    label += "  ·  " + root.wifiDevice.address;
                                return label;
                            }
                            color: root.theme.faint
                            elide: Text.ElideRight
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.label * root.s
                        }
                    }

                    Text {
                        text: Format.signalPercent(networkRow.modelData.signalStrength) + "%"
                        color: root.theme.dim
                        font.family: root.theme.monoFont
                        font.pixelSize: root.theme.fs.meta * root.s
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        id: busyGlyph
                        visible: networkRow.busy
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
                        visible: networkRow.modelData.connected && !networkRow.busy
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
            visible: !Networking.wifiEnabled
            text: "Turn on Wi-Fi to see nearby networks"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        Text {
            Layout.fillWidth: true
            visible: Networking.wifiEnabled && root.sortedNetworks.length === 0
            text: "Scanning for networks…"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        SpeedTestControl {
            Layout.fillWidth: true
            theme: root.theme
            s: root.s
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 76 * root.s
            visible: root.pendingNetwork !== null
            radius: root.theme.r.tile * root.s
            color: root.theme.withAlpha(root.theme.surfaceHigh, 0.55)
            border.width: 1
            border.color: root.theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8 * root.s
                spacing: 4 * root.s

                Text {
                    Layout.fillWidth: true
                    text: root.pendingNetwork
                        ? "Password for " + root.pendingNetwork.name
                        : ""
                    color: root.theme.cream
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6 * root.s

                    TextField {
                        id: passwordField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26 * root.s
                        echoMode: TextInput.Password
                        placeholderText: "Password"
                        placeholderTextColor: root.theme.faint
                        color: root.theme.cream
                        selectionColor: root.theme.accent
                        selectedTextColor: root.theme.onAccent
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fs.meta * root.s
                        leftPadding: 8 * root.s
                        rightPadding: 8 * root.s
                        verticalAlignment: TextInput.AlignVCenter
                        background: Rectangle {
                            radius: root.theme.r.s * root.s
                            color: root.theme.withAlpha(root.theme.surfaceHigh, 0.7)
                            border.width: 1
                            border.color: root.theme.withAlpha(root.theme.outline, 0.5)
                        }
                        onAccepted: root.submitPassword()

                        Keys.onEscapePressed: root.cancelPassword()
                    }

                    Rectangle {
                        Layout.preferredWidth: 58 * root.s
                        Layout.preferredHeight: 26 * root.s
                        radius: root.theme.r.s * root.s
                        color: connectArea.containsMouse
                            ? root.theme.accent
                            : root.theme.withAlpha(root.theme.surfaceHigh, 0.8)
                        border.width: 1
                        border.color: root.theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "Connect"
                            color: connectArea.containsMouse ? root.theme.onAccent : root.theme.cream
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.label * root.s
                        }

                        MouseArea {
                            id: connectArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submitPassword()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 24 * root.s
                        Layout.preferredHeight: 26 * root.s
                        radius: root.theme.r.s * root.s
                        color: cancelArea.containsMouse
                            ? root.theme.withAlpha(root.theme.danger, 0.18)
                            : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: cancelArea.containsMouse ? root.theme.danger : root.theme.dim
                            font.family: root.theme.iconFont
                            font.pixelSize: root.theme.fs.meta * root.s
                        }

                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelPassword()
                        }
                    }
                }
            }
        }
    }
}
