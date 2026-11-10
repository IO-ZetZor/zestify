import QtQuick

Item {
    id: root

    property var theme
    property real s: 1
    property date now: new Date()
    property string userName: ""
    property string batteryText: ""
    property string prompt: "Pull down to lock"
    property bool ready: false
    property bool requestingLock: false
    property real handoffProgress: 0

    readonly property color foreground: theme ? theme.cream : "#e6e4f0"
    readonly property color dim: theme ? theme.dim : "#abaab5"
    readonly property color accent: theme ? theme.accent : "#bfc4ee"

    function fontPixels(size) {
        // Match the integer point sizes used by Hyprlock/Pango at 96 DPI.
        return Math.max(1, Math.round(size * s * 0.75)) * 4 / 3;
    }

    Text {
        x: 36 * root.s
        y: 32 * root.s
        text: "Z E S T I F Y"
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(11)
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 36 * root.s
        y: 32 * root.s
        text: root.batteryText
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(12)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - 300 * root.s - height / 2
        text: "󰌾"
        color: root.accent
        font.family: root.theme ? root.theme.iconFont : ""
        font.pixelSize: root.fontPixels(24)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - 200 * root.s - height / 2
        text: Qt.formatDateTime(root.now, "HH:mm")
        color: root.foreground
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(88)
        font.weight: Font.Light
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - 120 * root.s - height / 2
        text: Qt.formatDateTime(root.now, "dddd, MMMM d")
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(17)
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 + 35 * root.s - height / 2
        width: Math.min(380 * root.s, root.width - 32 * root.s)
        height: 180 * root.s
        radius: 28 * root.s
        color: "transparent"
        border.width: 1
        border.color: root.theme ? root.theme.withAlpha(root.theme.outline, 0.3) : "#4d74757f"

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 40 * root.s - height / 2
            text: root.userName
            color: root.foreground
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(17)
            font.weight: Font.Medium
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 74 * root.s
            width: card.width - 70 * root.s
            height: 52 * root.s
            radius: 14 * root.s
            color: "transparent"
            border.width: 2
            border.color: root.theme ? root.theme.withAlpha(root.accent, 0.6) : root.accent

            Text {
                anchors.centerIn: parent
                text: "Pull to lock"
                opacity: 1 - root.handoffProgress
                color: root.dim
                font.family: root.theme ? root.theme.fontFamily : ""
                font.pixelSize: 13 * root.s
            }

            Text {
                anchors.centerIn: parent
                text: "Password"
                opacity: root.handoffProgress
                color: root.dim
                font.family: root.theme ? root.theme.fontFamily : ""
                font.pixelSize: 13 * root.s
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 155 * root.s - height / 2
            text: root.prompt
            opacity: 1 - root.handoffProgress
            color: root.ready ? root.accent : root.dim
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(11)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 155 * root.s - height / 2
            text: "Enter to unlock · Esc to clear"
            opacity: root.handoffProgress
            color: root.dim
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(11)
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 36 * root.s
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28 * root.s
        width: 90 * root.s
        height: 36 * root.s
        radius: 18 * root.s
        color: "transparent"
        border.width: 1
        border.color: root.theme ? root.theme.withAlpha(root.theme.outline, 0.3) : "#4d74757f"
        opacity: root.handoffProgress

        Text {
            anchors.centerIn: parent
            text: "Sleep"
            color: root.dim
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(12)
        }
    }
}
