import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root

    property string currentKind: "volume"
    property real currentValue: 0
    property bool showing: false

    readonly property var primaryScreen: {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === Config.monitor.primary)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }
    readonly property real s: primaryScreen
        ? LayoutLib.pillScale(primaryScreen.width, primaryScreen.height) * Config.bar.scale
        : 1

    screen: primaryScreen
    visible: showing && Config.osd.enabled
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.bottom: true
    anchors.left: true

    implicitWidth: 280 * s
    implicitHeight: 58 * s
    margins.bottom: 42 * s
    margins.left: primaryScreen
        ? Math.max(0, (primaryScreen.width - implicitWidth) / 2)
        : 0

    Theme {
        id: themeObject
        scheme: Colours.schemeFor(root.primaryScreen ? root.primaryScreen.name : "")
        fontFamily: Config.theme.fontFamily
        monoFont: Config.theme.monoFont
        iconFont: Config.theme.iconFont
    }

    Timer {
        id: hideTimer
        interval: Config.osd.timeout
        onTriggered: root.showing = false
    }

    function labelFor(kind) {
        if (kind === "brightness")
            return "Brightness";
        if (kind === "mic")
            return "Microphone";
        return "Volume";
    }

    function glyphFor(kind, value) {
        if (kind === "brightness")
            return "󰃠";
        if (kind === "mic")
            return value <= 0 ? "󰍭" : "󰍬";
        return value <= 0 ? "󰖁" : "󰕾";
    }

    function show(kind, value) {
        if (!Config.osd.enabled)
            return;
        root.currentKind = kind;
        root.currentValue = Math.max(0, Math.min(1, value));
        root.showing = true;
        hideTimer.restart();
    }

    Rectangle {
        anchors.fill: parent
        radius: themeObject.r.pill * s
        color: themeObject.withAlpha(themeObject.surfaceHigh, 0.94)
        border.width: 1
        border.color: themeObject.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 9 * root.s

            Text {
                text: root.glyphFor(root.currentKind, root.currentValue)
                color: themeObject.accent
                font.family: themeObject.iconFont
                font.pixelSize: 20 * root.s
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4 * root.s

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6 * root.s

                    Text {
                        Layout.fillWidth: true
                        text: root.labelFor(root.currentKind)
                        color: themeObject.cream
                        font.family: themeObject.fontFamily
                        font.pixelSize: themeObject.fs.meta * root.s
                    }

                    Text {
                        text: Math.round(root.currentValue * 100) + "%"
                        color: themeObject.dim
                        font.family: themeObject.monoFont
                        font.pixelSize: themeObject.fs.label * root.s
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 5 * root.s
                    radius: height / 2
                    color: themeObject.withAlpha(themeObject.outline, 0.35)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * root.currentValue
                        radius: parent.radius
                        color: themeObject.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }
}
