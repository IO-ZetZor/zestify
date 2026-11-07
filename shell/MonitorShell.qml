import QtQuick
import Quickshell
import "singletons"
import "components"
import "backgrounds"

Scope {
    id: root

    required property var screen

    readonly property alias theme: themeObject
    readonly property alias pill: pillWindow.pill
    readonly property alias background: backgroundWindow

    Component.onCompleted: Stats.start()

    Theme {
        id: themeObject
        scheme: Colours.schemeFor(root.screen ? root.screen.name : "")
        fontFamily: Config.theme.fontFamily
        monoFont: Config.theme.monoFont
        iconFont: Config.theme.iconFont
        transparency: Config.theme.transparency
    }

    BackgroundWindow {
        id: backgroundWindow
        targetScreen: root.screen
        wallpaperPath: Wallpapers.currentFor(root.screen ? root.screen.name : "")
        config: Config
        proxy: Proxy
        locked: Session.locked
        dpmsOn: Session.dpmsActive
        batteryLow: Stats.batteryPercent > 0
            && Stats.batteryPercent <= Config.wallpaper.pauseOnBatteryBelow
        powerSaver: false
    }

    PillWindow {
        id: pillWindow
        targetScreen: root.screen
        theme: root.theme
        stats: Stats
        players: Players
        motion: Motion
        wallpapers: Wallpapers
        wallpaperFolder: Config.wallpaper.dir
        uiScale: Config.bar.scale
        topGap: Config.bar.topGap
        showTitle: Config.bar.showTitle
    }

    NotificationPopups {
        targetScreen: root.screen
        theme: root.theme
        uiScale: Config.bar.scale
        motion: Motion
        enabled: root.screen ? root.screen.name === Config.monitor.primary : false
    }

    Connections {
        target: pillWindow.pill
        function onSurfaceChanged() {
            if (pillWindow.pill.surface.length > 0)
                ShellState.closeOtherSurfaces(root.screen.name);
        }
    }
}
