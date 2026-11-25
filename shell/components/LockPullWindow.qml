pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../singletons"

PanelWindow {
    id: root

    property var targetScreen: null
    property var theme
    property var motion
    property real uiScale: 1
    property real backgroundOpacity: 1
    property string userName: Quickshell.env("USER") || "Welcome back"

    screen: targetScreen
    // Unmap the gesture buffer while locked; map it again only to preload
    // an authenticated exit frame before fading back to the desktop.
    visible: !Session.locked || exitFade.active
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-lock-pull"
    // A click focuses this surface without changing its focus mode mid-drag.
    // Switching to Exclusive while the button is held loses pointer motion.
    WlrLayershell.keyboardFocus: exitFade.active ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: exitFade.active || !gesture.enabled ? emptyMask : (gesture.active ? fullMask : edgeMask)

    Region {
        id: emptyMask
        width: 0
        height: 0
    }

    Connections {
        target: Session
        function onLockStateReceived(value) {
            gesture.reset();
            if (value) exitFade.reset();
        }
    }

    Connections {
        target: Session.locker
        function onUnlockFrameReady(name, frame, serial) {
            if (root.targetScreen && name === root.targetScreen.name) {
                gesture.reset();
                exitFade.prepare(frame, serial);
            }
        }
        function onUnlockReleased(serial) {
            if (exitFade.serial === serial) exitFade.reveal();
        }
        function onUnlockCancelled() { exitFade.reset(); }
    }

    Connections {
        target: exitFade.Window.window
        function onFrameSwapped() {
            if (exitFade.ready && root.width > 0 && root.height > 0
                    && !exitFade.reported && Session.locker) {
                exitFade.reported = true;
                Session.locker.unlockOverlayReady(root.targetScreen.name, exitFade.serial);
            }
        }
    }

    UnlockFade {
        id: exitFade
        objectName: "unlockFade"
        property bool reported: false
        anchors.fill: parent
        motion: root.motion || Motion
        onActiveChanged: if (!active) reported = false
    }

    Process {
        command: [Session.python, Session.scriptsDir + "/lock.py", "--status", "user"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim()) root.userName = text.trim(); }
        }
    }

    Region {
        id: edgeMask
        width: gesture.width
        height: gesture.edgeHeight
    }

    Region {
        id: fullMask
        width: gesture.width
        height: gesture.height
    }

    LockPull {
        id: gesture
        anchors.fill: parent
        theme: root.theme
        motion: root.motion
        uiScale: root.uiScale
        backgroundOpacity: root.backgroundOpacity
        wallpaper: Component {
            LockWallpaper {
                path: Wallpapers.currentFor(root.targetScreen ? root.targetScreen.name : "")
            }
        }
        userName: root.userName
        batteryText: Stats.batteryPercent > 0
            ? Math.round(Stats.batteryPercent) + "% · " + (Session.charging ? "Charging" : "On battery")
            : ""
        enabled: !Session.locked && Session.dpmsActive
        onActiveChanged: if (active) {
            ShellState.closeNotifications();
            ShellState.closePower();
            ShellState.closeShortcuts();
        }
        onLockRequested: frame => {
            ShellState.close();
            Session.lock(false, root.targetScreen ? root.targetScreen.name : "", frame);
        }
        onLockTimedOut: Notifications.notify(
            "Lock did not start", "Try locking from the power menu.", "normal", "Zestify", 5000)
    }
}
