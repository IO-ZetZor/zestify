pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../singletons"

Scope {
    id: root

    property bool active: false
    property bool secure: false
    property alias generation: persisted.generation
    property string error: ""
    property alias authScreen: persisted.authScreen
    property string userName: Quickshell.env("USER") || "Welcome back"
    property string keyboardLayout: ""
    property bool capsLocked: false
    // Keep the grab result alive: its in-memory image URL expires with it.
    property var handoffFrame: null
    property string handoffScreen: ""
    property bool unlocking: false
    property int unlockSerial: 0
    property var lockSurfaces: []
    property var pendingUnlockScreens: []
    signal unlockFrameReady(string screenName, var frame, int serial)
    signal unlockReleased(int serial)
    signal unlockCancelled()

    PersistentProperties {
        id: persisted
        reloadableId: "zestifySessionLockState"
        property bool requested: false
        property int generation: 0
        property string authScreen: ""
    }

    function syncState() {
        active = nativeLock.locked;
        secure = active && nativeLock.secure;
        if (!active) {
            if (unlocking) cancelUnlock();
            handoffFrame = null;
            handoffScreen = "";
        }
        Session.locking = active && !secure;
        if (Session.locked !== secure)
            Session.handleLockState(secure);
        if (!active && persisted.requested) {
            persisted.requested = false;
            error = "Could not acquire the Wayland session lock";
            Session.handleLockState(false);
            Notifications.notify("Lock did not start", error, "normal", "Zestify", 5000);
        }
    }

    function requestLock(screenName, frame) {
        cancelUnlock();
        if (nativeLock.locked)
            return generation;
        generation++;
        error = "";
        authFlow.clear();
        authScreen = screenName || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
            || Config.monitor.activePrimary;
        handoffScreen = screenName || "";
        handoffFrame = frame || null;
        ShellState.close();
        ShellState.closeNotifications();
        ShellState.closePower();
        ShellState.closeShortcuts();
        ShellState.closeParty();
        Session.locking = true;
        persisted.requested = true;
        syncState();
        return generation;
    }

    function addSurface(surface) {
        lockSurfaces = lockSurfaces.concat([surface]);
    }

    function removeSurface(surface) {
        lockSurfaces = lockSurfaces.filter(item => item !== surface);
    }

    function beginUnlock() {
        if (!nativeLock.secure || unlocking)
            return;
        unlockSerial++;
        pendingUnlockScreens = lockSurfaces.map(surface => surface.screenName);
        unlocking = true;
        unlockDeadline.restart();
        if (!pendingUnlockScreens.length) finishUnlock(false);
    }

    function cancelUnlock() {
        unlockSerial++;
        unlockDeadline.stop();
        unlocking = false;
        pendingUnlockScreens = [];
        unlockCancelled();
    }

    function capturedUnlock(screenName, frame, serial) {
        if (!unlocking || serial !== unlockSerial)
            return;
        if (!frame) {
            finishUnlock(false);
            return;
        }
        unlockFrameReady(screenName, frame, serial);
    }

    function unlockOverlayReady(screenName, serial) {
        if (!unlocking || serial !== unlockSerial)
            return;
        pendingUnlockScreens = pendingUnlockScreens.filter(name => name !== screenName);
        if (!pendingUnlockScreens.length) finishUnlock(true);
    }

    function finishUnlock(animated) {
        if (!unlocking || !nativeLock.secure)
            return;
        unlockDeadline.stop();
        const serial = unlockSerial;
        if (!animated) unlockCancelled();
        // Only a current successful PAM attempt starts this path. Keep native
        // ownership until every output's exit overlay has committed a buffer.
        unlocking = false;
        pendingUnlockScreens = [];
        persisted.requested = false;
        active = false;
        secure = false;
        handoffFrame = null;
        handoffScreen = "";
        Session.locking = false;
        Session.handleLockState(false);
        authFlow.clear();
        if (animated) unlockReleased(serial);
    }

    function status() {
        return JSON.stringify({generation: generation, active: nativeLock.locked,
            secure: nativeLock.locked && nativeLock.secure, error: error});
    }

    Component.onCompleted: {
        Session.locker = root;
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { root.syncState(); }
        function onScreensChanged() {
            if (root.unlocking) root.finishUnlock(false);
            const screens = Quickshell.screens;
            if (!screens.some(screen => screen.name === root.authScreen))
                root.authScreen = screens.length ? screens[0].name : "";
        }
    }

    Process {
        command: [Session.python, Session.scriptsDir + "/lock.py", "--status", "user"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: if (text.trim()) root.userName = text.trim()
        }
    }

    PamContext {
        id: pamContext
        // The system's login policy supplies password/fingerprint/MFA and delays.
        // Empty user authenticates the actual UID, regardless of $USER.
        config: "login"
        onPamMessage: authFlow.message()
        onCompleted: result => authFlow.complete(result === PamResult.Success,
            result === PamResult.MaxTries ? "Too many attempts. Try again later."
            : result === PamResult.Failed ? "Authentication failed. Try again."
            : "Authentication unavailable. Try again.")
    }

    LockAuth {
        id: authFlow
        pam: pamContext
        available: root.secure && root.active && !root.unlocking
        onAuthenticated: root.beginUnlock()
    }

    WlSessionLock {
        id: nativeLock
        reloadableId: "zestifyNativeSessionLock"
        // Restore the target before WlSessionLock transfers its old manager.
        // A default false target would unlock the session during a QML reload.
        locked: persisted.requested
        onLockStateChanged: Qt.callLater(root.syncState)
        onSecureChanged: Qt.callLater(root.syncState)

        LockSurface {
            id: lockSurface
            unlocking: root.unlocking
            unlockSerial: root.unlockSerial
            Component.onCompleted: root.addSurface(lockSurface)
            Component.onDestruction: root.removeSurface(lockSurface)
            onUnlockCaptured: (name, frame, serial) => root.capturedUnlock(name, frame, serial)
            handoffFrame: root.handoffFrame
            handoffScreen: root.handoffScreen
            auth: authFlow
            authScreen: root.authScreen
            userName: root.userName
            layoutText: root.keyboardLayout
            capsLocked: root.capsLocked
            onScreenSelected: name => root.authScreen = name
        }
    }

    Timer {
        id: unlockDeadline
        interval: 1200
        // Capture/map failure must not strand an authenticated user.
        onTriggered: root.finishUnlock(false)
    }

    Timer {
        interval: 500
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.syncState();
            if (!keyboard.running) keyboard.running = true;
        }
    }

    Process {
        id: keyboard
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devices = JSON.parse(text).keyboards || [];
                    const device = devices.find(item => item.main) || devices[0];
                    root.keyboardLayout = device ? device.active_keymap || "" : "";
                    root.capsLocked = device ? Boolean(device.capsLock) : false;
                } catch (error) { }
            }
        }
    }
}
