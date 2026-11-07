import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property var theme
    property var screen
    property var stats
    property real s: 1
    property bool showTitle: true
    property bool showTray: true
    property bool locked: false
    property var windowObject

    signal calendarRequested()
    signal systemRequested()
    signal networkRequested()
    signal bluetoothRequested()
    signal batteryRequested()
    signal powerRequested()
    signal launcherRequested()
    signal configRequested()

    spacing: theme.sp.m * s

    Text {
        id: launcherGlyph
        text: "󰀻"
        color: launcherHover.hovered ? root.theme.accent : root.theme.iconDim
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s
        Layout.alignment: Qt.AlignVCenter

        HoverHandler {
            id: launcherHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.launcherRequested()
        }
    }

    Workspaces {
        theme: root.theme
        screen: root.screen
        s: root.s
        Layout.alignment: Qt.AlignVCenter
    }

    ActiveTitle {
        theme: root.theme
        screen: root.screen
        s: root.s
        visible: root.showTitle
        Layout.alignment: Qt.AlignVCenter
    }

    Item {
        Layout.fillWidth: true
    }

    Clock {
        theme: root.theme
        s: root.s
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.calendarRequested()
    }

    Item {
        Layout.fillWidth: true
    }

    Resources {
        theme: root.theme
        stats: root.stats
        s: root.s
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.systemRequested()
    }

    StatusIcons {
        theme: root.theme
        s: root.s
        Layout.alignment: Qt.AlignVCenter
        onWifiClicked: root.networkRequested()
        onBluetoothClicked: root.bluetoothRequested()
        onBatteryClicked: root.batteryRequested()
    }

    Text {
        id: configGlyph
        text: "󰒓"
        color: configHover.hovered ? root.theme.accent : root.theme.iconDim
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s
        Layout.alignment: Qt.AlignVCenter

        HoverHandler {
            id: configHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.configRequested()
        }
    }

    Text {
        id: powerGlyph
        text: "󰐥"
        color: powerHover.hovered ? root.theme.accent : root.theme.iconDim
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s
        Layout.alignment: Qt.AlignVCenter

        HoverHandler {
            id: powerHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.powerRequested()
        }
    }

    Tray {
        visible: root.showTray
        theme: root.theme
        s: root.s
        anchorWindow: root.windowObject
        Layout.alignment: Qt.AlignVCenter
    }

    Text {
        visible: root.locked
        text: "󰌾"
        color: root.theme.accent
        font.family: root.theme.iconFont
        font.pixelSize: root.theme.fs.title * root.s
        Layout.alignment: Qt.AlignVCenter
    }
}
