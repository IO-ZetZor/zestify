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
    readonly property string widgetMode: Config.monitor.modeFor(root.screen ? root.screen.name : "")
    readonly property bool powerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property var wallpaperPreview: Wallpapers.previewFor(root.screen ? root.screen.name : "")
    readonly property var previewScheme: Wallpapers.previewSchemeFor(root.screen ? root.screen.name : "")

    Component.onCompleted: Stats.start()

    Theme {
        id: globalTheme
        scheme: Colours.globalScheme
        mode: Config.theme.mode
    }

    Theme {
        id: themeObject
        shellAccent: root.previewScheme ? accent : globalTheme.accent
        scheme: root.previewScheme || Colours.schemeFor(root.screen ? root.screen.name : "")
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
        previewing: root.wallpaperPreview !== null
        holdChanges: ShellState.surface === "wallpaper" && ShellState.owner === root.screen.name
        wallpaperThumb: {
            const item = Wallpapers.items.find(item => item.path === backgroundWindow.wallpaperPath);
            return item ? item.thumb : "";
        }
        motion: Motion
        effects: WallpaperEffects
        transitionInk: root.theme.cream
        transitionEmber: root.theme.accent
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
        showRest: root.widgetMode === "pill"
        partyVisible: partyWindow.visible
    }

    FocusWindow {
        targetScreen: root.screen
        theme: root.theme
        uiScale: Config.bar.scale
        topGap: Config.bar.topGap
        enabled: root.widgetMode === "focus"
        fullscreen: pillWindow.pill.fullscreen
    }

    NotificationPopups {
        targetScreen: root.screen
        theme: root.theme
        uiScale: Config.bar.scale
        motion: Motion
        enabled: root.screen ? root.screen.name === Config.monitor.activePrimary : false
    }

    NotificationDrawerWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
        backgroundOpacity: Config.bar.opacity
    }

    PowerDrawerWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
        backgroundOpacity: Config.bar.opacity
    }

    ShortcutDrawerWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
        backgroundOpacity: Config.bar.opacity
    }

    WallpaperPickerWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
    }

    LockPullWindow {
        targetScreen: root.screen
        theme: root.theme
        motion: Motion
        uiScale: Config.bar.scale
        backgroundOpacity: Config.bar.opacity
    }

    PartyWindow {
        id: partyWindow
        sourcePill: pillWindow.pill
        targetScreen: root.screen
        theme: root.theme
        players: Players
        motion: Motion
        uiScale: Config.bar.scale
        topGap: Config.bar.topGap
        restWidth: pillWindow.pill.restWidth
        restHeight: pillWindow.pill.restHeight
    }

    Connections {
        target: pillWindow.pill
        function onSurfaceChanged() {
            if (root.screen && pillWindow.pill.surface.length > 0)
                ShellState.closeOtherSurfaces(root.screen.name);
        }
    }
}
