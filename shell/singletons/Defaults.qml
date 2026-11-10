pragma Singleton
import QtQuick

QtObject {
    readonly property var data: ({
        monitor: {
            primary: "eDP-1"
        },
        bar: {
            height: 34,
            topGap: 8,
            opacity: 1.0,
            scale: 1.0,
            showTray: true,
            showTitle: true,
            trayOn: "primary",
            titleOn: "focused"
        },
        theme: {
            mode: "dark",
            transparency: 0.88,
            font: "SF Pro",
            mono: "SF Mono",
            iconFont: "CaskaydiaCove Nerd Font",
            apply: true
        },
        wallpaper: {
            dir: "~/Pictures/Wallpapers",
            pauseOnFullscreen: true,
            pauseWhenObscured: "fullscreen",
            pauseOnBatteryBelow: 20,
            pauseOnPowerSaver: true,
            pauseUnfocusedAfter: 0,
            muted: true,
            proxy: {
                enabled: true,
                resolution: "monitor",
                codec: "h264",
                crf: 20
            }
        },
        system: {
            pollInterval: 1000,
            graphSeconds: 60
        },
        notifications: {
            dnd: false,
            timeout: 5000
        },
        osd: {
            enabled: true,
            position: "bottom-center",
            timeout: 1500
        },
        power: {
            confirmHoldMs: 700
        },
        session: {
            lockAfter: 180,
            dpmsOffAfter: 300,
            suspendAfter: 600,
            suspendCommand: ["systemctl", "suspend-then-hibernate"],
            lockBeforeSleep: true,
            inhibitWhenAudio: true,
            inhibitWhenCharging: false,
            batteryWarnings: [20, 10, 5],
            criticalBattery: 3
        }
    })
}
