pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/merge.js" as Merge
import "../lib/config.js" as ConfigLib
import "../lib/monitors.js" as MonitorLib
import "."

Singleton {
    id: root

    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/zestify/config.json"

    property var data: Defaults.data
    property int revision: 0
    property bool _warned: false

    function value(path, fallback) {
        return ConfigLib.getValue(root.data, path, fallback);
    }

    function setValue(path, value) {
        const next = JSON.parse(JSON.stringify(root.data));
        ConfigLib.setValue(next, path, value);
        root.data = next;
        root.revision++;
        configFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function reset() {
        const next = JSON.parse(JSON.stringify(Defaults.data));
        root.data = next;
        root.revision++;
        configFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function load(text) {
        try {
            const user = JSON.parse(text);
            const next = Merge.merge(Defaults.data, user);
            root.data = next;
            root.revision++;
            root._warned = false;
        } catch (error) {
            if (!root._warned) {
                root._warned = true;
                console.warn("zestify: ignoring invalid config at", root.configPath, "-", error);
            }
        }
    }

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        blockLoading: true
        printErrors: false

        onLoaded: root.load(text())
        onFileChanged: reload()
        onLoadFailed: {
            if (!root._warned) {
                root._warned = true;
                console.warn("zestify: no config at", root.configPath, "- using defaults");
            }
        }
    }

    readonly property QtObject monitor: QtObject {
        readonly property string primary: root.value("monitor.primary", "eDP-1")
        readonly property string activePrimary: MonitorLib.primaryName(Quickshell.screens, primary)
        readonly property string secondaryMode: root.value("monitor.secondaryMode", "focus")
        readonly property var overrides: root.value("monitor.overrides", {})

        function modeFor(screenName) {
            return MonitorLib.widgetMode(screenName, activePrimary, secondaryMode, overrides);
        }
    }

    readonly property QtObject focus: QtObject {
        readonly property string task: root.value("focus.task", "")
        readonly property string mode: root.value("focus.mode", "countdown") === "stopwatch" ? "stopwatch" : "countdown"
        readonly property int minutes: {
            const value = Number(root.value("focus.minutes", 25));
            return Number.isFinite(value) ? Math.max(1, Math.min(240, Math.round(value))) : 25;
        }
        readonly property bool dnd: root.value("focus.dnd", false) === true
    }

    readonly property QtObject bar: QtObject {
        readonly property int height: root.value("bar.height", 34)
        readonly property int topGap: root.value("bar.topGap", 8)
        readonly property real opacity: root.value("bar.opacity", 1.0)
        readonly property real scale: root.value("bar.scale", 1.0)
        readonly property bool showTray: root.value("bar.showTray", true)
        readonly property string trayOn: root.value("bar.trayOn", "primary")
    }

    readonly property QtObject theme: QtObject {
        readonly property string mode: root.value("theme.mode", "dark")
        readonly property bool smartScheme: root.value("theme.smartScheme", true)
        readonly property real transparency: root.value("theme.transparency", 0.88)
        readonly property string fontFamily: root.value("theme.font", "SF Pro")
        readonly property string monoFont: root.value("theme.mono", "SF Mono")
        readonly property string iconFont: root.value("theme.iconFont", "CaskaydiaCove Nerd Font")
    }

    readonly property QtObject wallpaper: QtObject {
        readonly property string dir: root.value("wallpaper.dir", "~/Pictures/Wallpapers")
        readonly property bool pauseOnFullscreen: root.value("wallpaper.pauseOnFullscreen", true)
        readonly property string pauseWhenObscured: root.value("wallpaper.pauseWhenObscured", "fullscreen")
        readonly property int pauseOnBatteryBelow: root.value("wallpaper.pauseOnBatteryBelow", 20)
        readonly property bool pauseOnPowerSaver: root.value("wallpaper.pauseOnPowerSaver", true)
        readonly property int pauseUnfocusedAfter: root.value("wallpaper.pauseUnfocusedAfter", 0)
        readonly property bool muted: root.value("wallpaper.muted", true)

        readonly property QtObject proxy: QtObject {
            readonly property bool enabled: root.value("wallpaper.proxy.enabled", true)
            readonly property string resolution: root.value("wallpaper.proxy.resolution", "monitor")
            readonly property string codec: root.value("wallpaper.proxy.codec", "h264")
            readonly property int crf: root.value("wallpaper.proxy.crf", 20)
            readonly property int maxFps: {
                const fps = Number(root.value("wallpaper.proxy.maxFps", 24));
                return Number.isFinite(fps) ? Math.max(1, Math.min(60, Math.round(fps))) : 24;
            }
        }
    }

    readonly property QtObject system: QtObject {
        readonly property int pollInterval: {
            const interval = Number(root.value("system.pollInterval", 1000));
            return Number.isFinite(interval) ? Math.max(250, Math.min(60000, interval)) : 1000;
        }
        readonly property int graphSeconds: root.value("system.graphSeconds", 60)
    }

    readonly property QtObject notifications: QtObject {
        readonly property bool dnd: root.value("notifications.dnd", false)
        readonly property int timeout: root.value("notifications.timeout", 5000)
    }

    readonly property QtObject osd: QtObject {
        readonly property bool enabled: root.value("osd.enabled", true)
        readonly property string position: root.value("osd.position", "bottom-center")
        readonly property int timeout: root.value("osd.timeout", 1500)
    }

    readonly property QtObject power: QtObject {
        readonly property int confirmHoldMs: root.value("power.confirmHoldMs", 700)
    }

    readonly property QtObject session: QtObject {
        readonly property int lockAfter: root.value("session.lockAfter", 180)
        readonly property int dpmsOffAfter: root.value("session.dpmsOffAfter", 300)
        readonly property int suspendAfter: root.value("session.suspendAfter", 600)
        readonly property var suspendCommand: root.value("session.suspendCommand", ["systemctl", "suspend-then-hibernate"])
        readonly property bool lockBeforeSleep: root.value("session.lockBeforeSleep", true)
        readonly property bool inhibitWhenAudio: root.value("session.inhibitWhenAudio", true)
        readonly property bool inhibitWhenCharging: root.value("session.inhibitWhenCharging", false)
        readonly property var batteryWarnings: root.value("session.batteryWarnings", [20, 10, 5])
        readonly property int criticalBattery: root.value("session.criticalBattery", 3)
    }
}
