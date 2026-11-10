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
    // Unmap the old buffer while Hyprlock owns the screen. Merely resetting
    // the item can leave its last frame visible when Wayland resumes drawing.
    visible: !Session.locked
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-lock-pull"
    // A click focuses this surface without changing its focus mode mid-drag.
    // Switching to Exclusive while the button is held loses pointer motion.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: !gesture.enabled ? emptyMask : (gesture.active ? fullMask : edgeMask)

    Region {
        id: emptyMask
        width: 0
        height: 0
    }

    Connections {
        target: Session
        function onLockStateReceived(value) {
            gesture.reset();
        }
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
        userName: root.userName
        batteryText: Stats.batteryPercent > 0
            ? Math.round(Stats.batteryPercent) + "% · " + (Session.charging ? "Charging" : "On battery")
            : ""
        enabled: !Session.locked && Session.dpmsActive
        onActiveChanged: if (active) ShellState.closeNotifications()
        onLockRequested: {
            ShellState.close();
            Session.lock(false);
        }
        onLockTimedOut: Notifications.notify(
            "Lock did not start", "Try locking from the power menu.", "normal", "Zestify", 5000)
    }
}
