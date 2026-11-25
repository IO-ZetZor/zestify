import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray

Row {
    id: root

    property var theme
    property real s: 1
    property var anchorWindow

    readonly property var items: SystemTray.items.values

    visible: items.length > 0
    spacing: 6 * s

    function iconSource(item) {
        const icon = item && item.icon ? String(item.icon) : "";
        if (icon.length === 0)
            return "";
        if (icon.indexOf("://") >= 0)
            return icon;
        if (icon.charAt(0) === "/")
            return "file://" + icon;
        if (Quickshell.hasThemeIcon(icon))
            return Quickshell.iconPath(icon);
        return "";
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: trayItem
            required property var modelData

            width: 18 * root.s
            height: 18 * root.s

            Image {
                id: trayIcon
                objectName: "pillTrayIcon"
                anchors.fill: parent
                source: root.iconSource(trayItem.modelData)
                visible: source.toString().length > 0
                fillMode: Image.PreserveAspectFit
                // Let the icon provider select a bitmap for the rendered size.
                sourceSize.width: Math.ceil(width)
                sourceSize.height: Math.ceil(height)
                smooth: true
                mipmap: true
            }

            Text {
                anchors.centerIn: parent
                visible: !trayIcon.visible
                text: "󰀻"
                color: root.theme.iconDim
                font.family: root.theme.iconFont
                font.pixelSize: 13 * root.s
            }

            MouseArea {
                id: trayMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton) {
                        trayItem.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.LeftButton) {
                        if (trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)
                            trayMenu.open();
                        else
                            trayItem.modelData.activate();
                    } else if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu) {
                        trayMenu.open();
                    }
                }

                onWheel: (wheel) => {
                    trayItem.modelData.scroll(wheel.angleDelta.y, wheel.angleDelta.x);
                }
            }

            ToolTip.visible: trayMouse.containsMouse
                && (trayItem.modelData.tooltipTitle.length > 0
                    || trayItem.modelData.tooltipDescription.length > 0)
            ToolTip.delay: 500
            ToolTip.text: {
                const title = trayItem.modelData.tooltipTitle || trayItem.modelData.title || "";
                const description = trayItem.modelData.tooltipDescription || "";
                if (title.length > 0 && description.length > 0)
                    return title + "\n" + description;
                return title.length > 0 ? title : description;
            }

            TrayMenu {
                id: trayMenu
                trayItem: trayItem.modelData
                anchorItem: trayItem
                anchorWindow: root.anchorWindow
            }
        }
    }
}
