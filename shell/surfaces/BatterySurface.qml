pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../lib/format.js" as Format

SurfaceFrame {
    id: root

    property var screen
    property var motion

    title: "Battery"

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent
    readonly property int percent: device ? Math.round(device.percentage * 100) : -1
    readonly property bool charging: device
        && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged)
    readonly property bool low: percent >= 0 && percent <= 20
    readonly property color levelColour: low
        ? root.theme.danger
        : (charging ? root.theme.accent : root.theme.cream)

    function stateLabel() {
        if (!root.device)
            return "No battery";
        const value = UPowerDeviceState.toString(root.device.state);
        if (value === "FullyCharged")
            return "Fully charged";
        if (value === "PendingCharge")
            return "Pending charge";
        if (value === "PendingDischarge")
            return "Pending discharge";
        return value;
    }

    function timeLabel() {
        if (!root.device)
            return "—";
        if (root.device.state === UPowerDeviceState.Charging && root.device.timeToFull > 0)
            return Format.duration(root.device.timeToFull) + " until full";
        if (root.device.state === UPowerDeviceState.Discharging && root.device.timeToEmpty > 0)
            return Format.duration(root.device.timeToEmpty) + " remaining";
        if (root.device.state === UPowerDeviceState.FullyCharged)
            return "Plugged in";
        return "—";
    }

    function healthLabel() {
        if (!root.device || !root.device.healthSupported)
            return "—";
        const value = root.device.healthPercentage <= 1
            ? root.device.healthPercentage * 100
            : root.device.healthPercentage;
        return Math.round(value) + "%";
    }

    function powerLabel() {
        if (!root.device || Math.abs(root.device.changeRate) < 0.01)
            return "—";
        return Format.watts(root.device.changeRate);
    }

    function capacityLabel() {
        if (!root.device || root.device.energyCapacity <= 0)
            return "—";
        return Format.energy(root.device.energy) + " / " + Format.energy(root.device.energyCapacity);
    }

    component DetailCard: Rectangle {
        id: card

        property string label
        property string value

        Layout.fillWidth: true
        Layout.preferredHeight: 52 * root.s
        radius: root.theme.r.tile * root.s
        color: root.theme.tileBg
        border.width: 1
        border.color: root.theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.theme.sp.m * root.s
            spacing: 2 * root.s

            Text {
                Layout.fillWidth: true
                text: card.label
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
            }

            Text {
                Layout.fillWidth: true
                text: card.value
                color: root.theme.cream
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.body * root.s
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * root.s

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.present
            text: "No battery detected"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.present
            spacing: 8 * root.s

            Text {
                text: root.charging ? "󰂄" : (root.low ? "󰁺" : "󰁹")
                color: root.levelColour
                font.family: root.theme.iconFont
                font.pixelSize: 34 * root.s
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1 * root.s

                Text {
                    text: root.percent >= 0 ? root.percent + "%" : "—"
                    color: root.levelColour
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.display * root.s
                }

                Text {
                    Layout.fillWidth: true
                    text: root.stateLabel()
                    color: root.theme.dim
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8 * root.s
            visible: root.present
            radius: height / 2
            color: root.theme.withAlpha(root.theme.outline, 0.35)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, root.percent / 100))
                radius: parent.radius
                color: root.levelColour

                Behavior on width {
                    NumberAnimation {
                        duration: root.motion ? root.motion.standard : 300
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.present
            text: root.timeLabel()
            color: root.theme.cream
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
        }

        GridLayout {
            Layout.fillWidth: true
            visible: root.present
            columns: 2
            rowSpacing: 6 * root.s
            columnSpacing: 6 * root.s

            DetailCard {
                label: "State"
                value: root.stateLabel()
            }

            DetailCard {
                label: "Remaining"
                value: root.timeLabel()
            }

            DetailCard {
                label: "Health"
                value: root.healthLabel()
            }

            DetailCard {
                label: "Power draw"
                value: root.powerLabel()
            }

            DetailCard {
                label: "Capacity"
                value: root.capacityLabel()
            }

            DetailCard {
                label: "Model"
                value: root.device && root.device.model ? root.device.model : "—"
            }
        }
    }
}
