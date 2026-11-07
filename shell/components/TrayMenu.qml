import QtQuick
import Quickshell

QsMenuAnchor {
    id: root

    property var trayItem
    property var anchorItem
    property var anchorWindow

    anchor.window: root.anchorWindow
    anchor.item: root.anchorItem
    menu: root.trayItem ? root.trayItem.menu : null
}
