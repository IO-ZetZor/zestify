import QtQuick
import "../singletons"
import "../lib/layout.js" as Layout

QtObject {
    id: root

    property var screen: null
    property real uiScale: 1

    readonly property real s: screen ? Layout.pillScale(screen.width, screen.height) * uiScale : 1
    readonly property real restHeight: Config.bar.height * s
    readonly property real surfaceWidth: screen ? Layout.surfaceWidth(screen.width, s) : 460 * s
    readonly property real pillRadius: 18 * s
    readonly property real tileRadius: 13 * s
}
