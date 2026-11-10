pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../lib/background.js" as BackgroundLib
import "../surfaces"
import "../singletons"

Item {
    id: root

    property var theme
    property var screen
    property var stats
    property var players
    property var motion
    property var wallpapers
    property string wallpaperFolder: ""
    property real uiScale: 1
    property var windowObject
    property real topGap: 8
    property bool showTitle: true
    property bool hovered: false
    property bool pinned: false
    property bool pointerInside: false

    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property var activeWorkspace: monitor ? monitor.activeWorkspace : null
    readonly property bool fullscreen: BackgroundLib.isFullscreen(activeWorkspace)

    readonly property var metrics: PillMetrics {
        screen: root.screen
        uiScale: root.uiScale
    }
    readonly property real s: metrics.s
    readonly property real restHeight: metrics.restHeight
    readonly property real hoverWidth: 1000 * s
    readonly property real hoverHeight: 320 * s
    readonly property string scriptsDir: Quickshell.shellDir ? Quickshell.shellDir + "/../scripts" : ""
    readonly property real maxWidth: screen ? screen.width - 2 * theme.inset.side * s : 800
    readonly property bool locked: Session.locked
    readonly property bool hovering: !locked && !fullscreen && (hovered || pinned || expanded)

    readonly property string surface: ShellState.isOpenOn(screen ? screen.name : "")
        ? ShellState.surface
        : ""
    readonly property bool expanded: surface.length > 0
    readonly property var currentSurface: {
        if (surface.length === 0)
            return null;
        const entry = surfaceRegistry[surface];
        return entry === undefined ? null : entry;
    }
    readonly property real restWidth: Math.max(modules.implicitWidth, hoverRow.implicitWidth)
        + 2 * theme.sp.l * s
    readonly property real surfaceWidth: currentSurface
        ? Math.max(280, Math.min(currentSurface.width * s, screen.width - 2 * 16))
        : 0
    readonly property real surfaceHeight: currentSurface
        ? Math.max(160, Math.min(currentSurface.height * s, screen.height - topGap - restHeight - 2 * 16))
        : 0
    readonly property real surfaceGap: 6 * s
    readonly property real surfaceBottom: 8 * s
    readonly property real surfaceTotalHeight: restHeight + surfaceGap + surfaceHeight + surfaceBottom

    readonly property var surfaceRegistry: ({
        "launcher": { title: "Launcher", width: 620, height: 620, component: launcherSurface },
        "wallpaper": { title: "Wallpaper", width: 760, height: 600, component: wallpaperSurface },
        "system": { title: "System", width: 820, height: 690, component: systemSurface },
        "media": { title: "Media", width: 640, height: 480, component: mediaSurface },
        "audio": { title: "Audio", width: 660, height: 560, component: audioSurface },
        "calendar": { title: "Calendar", width: 560, height: 540, component: calendarSurface },
        "network": { title: "Network", width: 620, height: 560, component: networkSurface },
        "bluetooth": { title: "Bluetooth", width: 620, height: 560, component: bluetoothSurface },
        "battery": { title: "Battery", width: 520, height: 500, component: batterySurface },
        "power": { title: "Power", width: 660, height: 420, component: powerSurface },
        "config": { title: "Settings", width: 760, height: 620, component: configSurface }
    })

    implicitWidth: restWidth
    width: currentSurface
        ? Math.max(restWidth, surfaceWidth)
        : (hovering
            ? Math.max(restWidth, Math.min(hoverWidth, maxWidth))
            : Math.min(restWidth, maxWidth))
    height: currentSurface ? Math.min(surfaceTotalHeight, screen.height - topGap) : (hovering ? hoverHeight : restHeight)
    clip: true
    opacity: fullscreen ? 0 : 1
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: root.motion ? root.motion.fast : 140
            easing.type: Easing.OutCubic
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: root.motion ? root.motion.morph : 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.motion ? root.motion.morphCurve : [0.16, 1, 0.3, 1, 1, 1]
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: root.motion ? root.motion.morph : 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.motion ? root.motion.morphCurve : [0.16, 1, 0.3, 1, 1, 1]
        }
    }

    function openSurface(name) {
        if (!name || !surfaceRegistry[name])
            return;
        if (surface === name) {
            closeSurface();
            return;
        }
        ShellState.open(name, screen ? screen.name : "");
    }

    function closeSurface() {
        ShellState.close(screen ? screen.name : "");
    }

    onSurfaceChanged: {
        openTimer.stop();
        closeTimer.stop();
        if (surface.length === 0)
            hovered = false;
    }

    onFullscreenChanged: {
        if (fullscreen) {
            hovered = false;
            openTimer.stop();
            closeTimer.stop();
            closeSurface();
        }
    }

    Component {
        id: launcherSurface

        Launcher {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            apps: Apps
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: wallpaperSurface

        SurfaceFrame {
            theme: root.theme
            s: root.s
            title: "Wallpaper"
            onCloseRequested: root.closeSurface()

            WallpaperStudio {
                anchors.fill: parent
                theme: root.theme
                screen: root.screen
                wallpapers: root.wallpapers
                motion: root.motion
                s: root.s
                folder: root.wallpaperFolder
            }
        }
    }

    Component {
        id: systemSurface

        SystemSurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            stats: root.stats
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: mediaSurface

        MediaSurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            players: root.players
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: audioSurface

        AudioSurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: calendarSurface

        CalendarSurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: networkSurface

        NetworkSurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: bluetoothSurface

        BluetoothSurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: batterySurface

        BatterySurface {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: powerSurface

        Power {
            theme: root.theme
            s: root.s
            screen: root.screen
            motion: root.motion
            session: Session
            confirmHoldMs: Config.power.confirmHoldMs
            onCloseRequested: root.closeSurface()
        }
    }

    Component {
        id: configSurface

        ConfigSurface {
            theme: root.theme
            s: root.s
            motion: root.motion
            onCloseRequested: root.closeSurface()
        }
    }

    HoverHandler {
        id: hoverHandler
        onHoveredChanged: {
            if (hoverHandler.hovered) {
                root.pointerInside = true;
                closeTimer.stop();
                openTimer.restart();
            } else {
                root.pointerInside = false;
                openTimer.stop();
                if (!root.pinned && !root.expanded)
                    closeTimer.restart();
            }
        }
    }

    Timer {
        id: openTimer
        interval: 120
        onTriggered: {
            if (root.pointerInside)
                root.hovered = true;
        }
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!root.pointerInside && !root.pinned && !root.expanded)
                root.hovered = false;
        }
    }

    PillBody {
        anchors.fill: parent
        theme: root.theme
        backgroundOpacity: Config.bar.opacity
        cornerRadius: root.metrics.pillRadius + (root.hovering ? 4 * root.s : 0)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    PillModules {
        id: modules
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.theme.sp.l * root.s
        anchors.rightMargin: root.theme.sp.l * root.s
        height: root.restHeight
        theme: root.theme
        screen: root.screen
        stats: root.stats
        s: root.s
        showTitle: root.showTitle
            && (Config.bar.titleOn === "all" || (root.monitor && root.monitor.focused))
        showTray: Config.bar.showTray && root.screen
            && (Config.bar.trayOn === "all"
                || (Config.bar.trayOn === "primary" && root.screen.name === Config.monitor.primary))
        locked: root.locked
        windowObject: root.windowObject
        onCalendarRequested: root.openSurface("calendar")
        onSystemRequested: root.openSurface("system")
        onNetworkRequested: root.openSurface("network")
        onBluetoothRequested: root.openSurface("bluetooth")
        onBatteryRequested: root.openSurface("battery")
        onPowerRequested: root.openSurface("power")
        onConfigRequested: root.openSurface("config")
        onLauncherRequested: root.openSurface("launcher")
    }

    RowLayout {
        id: hoverRow
        anchors.top: modules.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.theme.sp.l * root.s
        anchors.rightMargin: root.theme.sp.l * root.s
        height: root.hoverHeight - root.restHeight
        spacing: root.theme.sp.m * root.s
        visible: root.hovering && root.surface.length === 0
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.motion ? root.motion.fast : 140
                easing.type: Easing.OutCubic
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                onClicked: root.openSurface("media")
            }

            MediaCard {
                anchors.fill: parent
                anchors.topMargin: root.theme.sp.l * root.s
                anchors.bottomMargin: root.theme.sp.l * root.s
                theme: root.theme
                players: root.players
                s: root.s
                motion: root.motion
                scriptsDir: root.scriptsDir
                active: root.hovering && root.surface.length === 0
            }
        }

        QuickToggles {
            Layout.alignment: Qt.AlignTop | Qt.AlignRight
            Layout.topMargin: root.theme.sp.l * root.s
            theme: root.theme
            s: root.s
            motion: root.motion
            dnd: Notifications.dnd
            onDndToggled: Notifications.toggleDnd()
            onOpenWallpaper: function() { root.openSurface("wallpaper") }
        }
    }

    Loader {
        id: surfaceLoader
        anchors.top: modules.bottom
        anchors.topMargin: root.surfaceGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.surfaceWidth
        height: root.surfaceHeight
        active: root.currentSurface !== null && root.surfaceHeight > 0
        sourceComponent: root.currentSurface ? root.currentSurface.component : null
        visible: active
        clip: true
    }
}
