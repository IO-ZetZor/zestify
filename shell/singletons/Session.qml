pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../lib/session.js" as SessionLib

Singleton {
    id: root

    readonly property string cli: Quickshell.env("ZESTI_BIN") || Quickshell.env("ZESTIFY_BIN") || "zesti"
    readonly property string python: Quickshell.env("PYTHON") || "python3"
    readonly property string scriptsDir: Quickshell.env("ZESTIFY_SCRIPTS")
        || (Quickshell.shellDir + "/../scripts")

    property bool locked: false
    property bool dpmsActive: true
    property bool idleResetHeld: false
    property int lastBatteryWarning: 100
    property bool _hibernating: false

    signal lockStateReceived(bool value)

    readonly property bool charging: {
        const device = UPower.displayDevice;
        if (!device)
            return false;
        return device.state === UPowerDeviceState.Charging
            || device.state === UPowerDeviceState.FullyCharged;
    }
    readonly property bool idleInhibited: shouldInhibitAudio(Players.isPlaying, Config.session.inhibitWhenAudio)
        || shouldInhibitCharging(root.charging, Config.session.inhibitWhenCharging)
    readonly property bool idleEnabled: !locked && dpmsActive && !idleInhibited && !idleResetHeld

    function shouldInhibitAudio(isPlaying, inhibitWhenAudio) {
        return SessionLib.shouldInhibitAudio(isPlaying, inhibitWhenAudio);
    }

    function shouldInhibitCharging(isCharging, inhibitWhenCharging) {
        return SessionLib.shouldInhibitCharging(isCharging, inhibitWhenCharging);
    }

    function shouldLock(idleSeconds, lockAfter) {
        return SessionLib.shouldLock(idleSeconds, lockAfter);
    }

    function nextBatteryWarning(percent, lastWarned, warnings) {
        return SessionLib.nextBatteryWarning(percent, lastWarned, warnings);
    }

    function lock(wait) {
        if (locked)
            return;
        const command = [root.cli, "lock"];
        if (wait)
            command.push("--wait");
        Quickshell.execDetached(command);
    }

    function sleep() {
        Quickshell.execDetached([root.cli, "sleep"]);
    }

    function dpmsOff() {
        if (!dpmsActive)
            return;
        dpmsActive = false;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.dpms({ off = true })"]);
    }

    function dpmsOn() {
        if (dpmsActive)
            return;
        dpmsActive = true;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.dpms({ off = false })"]);
        resetIdleMonitors();
    }

    function resetIdleMonitors() {
        idleResetHeld = true;
        idleResetTimer.restart();
    }

    function handleLockState(value) {
        locked = Boolean(value);
        lockStateReceived(locked);
        if (!locked)
            resetIdleMonitors();
    }

    function handleDpmsState(off) {
        if (off)
            dpmsOff();
        else
            dpmsOn();
    }

    function handleAboutToSleep(value) {
        if (value) {
            if (Config.session.lockBeforeSleep)
                lock(false);
            return;
        }
        dpmsActive = true;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.dpms({ off = false })"]);
        resetIdleMonitors();
    }

    function notifyLowBattery(threshold) {
        Quickshell.execDetached([
            "notify-send", "-a", "Zestify", "-u", "normal",
            "Battery low", String(threshold) + "% remaining"
        ]);
    }

    function checkBattery() {
        const device = UPower.displayDevice;
        if (!device || !device.isPresent)
            return;
        if (root.charging) {
            root.lastBatteryWarning = 100;
            root._hibernating = false;
            return;
        }
        const percent = Math.round(Number(device.percentage) * 100);
        if (!Number.isFinite(percent))
            return;
        if (percent <= Config.session.criticalBattery) {
            if (root._hibernating)
                return;
            root._hibernating = true;
            Quickshell.execDetached([
                "notify-send", "-a", "Zestify", "-u", "critical", "-t", "5000",
                "Battery critical", "Hibernating in 5 seconds"
            ]);
            Quickshell.execDetached([
                "sh", "-c", "sleep 5; systemctl hibernate"
            ]);
            return;
        }
        const next = SessionLib.nextBatteryWarning(
            percent, root.lastBatteryWarning, Config.session.batteryWarnings);
        if (next !== null && percent <= next) {
            root.lastBatteryWarning = next;
            root.notifyLowBattery(next);
        }
    }

    Component.onCompleted: {
        checkBattery();
        batteryTimer.start();
    }

    Timer {
        id: batteryTimer
        interval: 30000
        repeat: true
        onTriggered: root.checkBattery()
    }

    Timer {
        id: idleResetTimer
        interval: 120
        onTriggered: root.idleResetHeld = false
    }

    Timer {
        id: logindRestartTimer
        interval: 2000
        onTriggered: logind.running = true
    }

    IdleMonitor {
        id: lockIdle
        timeout: Config.session.lockAfter
        enabled: Config.session.lockAfter > 0 && root.idleEnabled
        onIsIdleChanged: {
            if (isIdle && lockIdle.enabled)
                root.lock(false);
        }
    }

    IdleMonitor {
        id: dpmsIdle
        timeout: Config.session.dpmsOffAfter
        enabled: Config.session.dpmsOffAfter > 0 && root.dpmsActive && !root.idleInhibited && !root.idleResetHeld
        onIsIdleChanged: {
            if (isIdle && dpmsIdle.enabled)
                root.dpmsOff();
        }
    }

    IdleMonitor {
        id: suspendIdle
        timeout: Config.session.suspendAfter
        enabled: Config.session.suspendAfter > 0 && !root.idleInhibited && !root.idleResetHeld
        onIsIdleChanged: {
            if (isIdle && suspendIdle.enabled)
                Quickshell.execDetached(Config.session.suspendCommand);
        }
    }

    IdleMonitor {
        id: wakeIdle
        timeout: 1
        enabled: !root.dpmsActive
        respectInhibitors: false
        onIsIdleChanged: {
            if (!isIdle && !root.dpmsActive)
                root.dpmsOn();
        }
    }

    Process {
        id: logind
        command: [root.python, root.scriptsDir + "/logind-watch.py"]
        running: true

        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const message = JSON.parse(line);
                    if (message && message.aboutToSleep !== undefined)
                        root.handleAboutToSleep(Boolean(message.aboutToSleep));
                } catch (error) {
                    // Ignore malformed watcher output.
                }
            }
        }

        onExited: logindRestartTimer.restart()
    }
}
