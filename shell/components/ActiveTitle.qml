import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Text {
    id: root

    property var theme
    property var screen
    property real s: 1

    readonly property string title: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""
    readonly property bool monitorFocused: {
        const monitor = screen ? Hyprland.monitorFor(screen) : null;
        return monitor ? monitor.focused : false;
    }

    visible: monitorFocused && title.length > 0
    text: title
    color: theme.dim
    font.family: theme.fontFamily
    font.pixelSize: theme.fs.meta * s
    elide: Text.ElideRight
    maximumLineCount: 1
    Layout.maximumWidth: 240 * s
}
