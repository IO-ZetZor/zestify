import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "singletons"
import "components"
import "backgrounds"

Scope {
    id: root

    required property var screen

    readonly property alias theme: themeObject
    readonly property alias pill: pillWindow.pill
    readonly property alias background: backgroundWindow
    readonly property bool powerSaving: PowerProfiles.profile === PowerProfile.PowerSaver

    Component.onCompleted: Stats.start()

    Theme {
        id: globalTheme
        scheme: Colours.globalScheme
        mode: Config.theme.mode
    }

    Theme {
        id: themeObject
        shellAccent: globalTheme.accent
        scheme: Colours.schemeFor(root.screen ? root.screen.name : "")
        mode: Config.theme.mode
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
        powerSaver: Config.wallpaper.pauseOnPowerSaver && root.powerSaving
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

    NotificationDrawerWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
        backgroundOpacity: Config.bar.opacity
    }

    LockPullWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
        backgroundOpacity: Config.bar.opacity
    }

    Connections {
        target: pillWindow.pill
        function onSurfaceChanged() {
            if (pillWindow.pill.surface.length > 0)
                ShellState.closeOtherSurfaces(root.screen.name);
        }
    }
}
