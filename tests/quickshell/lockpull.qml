// Run with tests/quickshell/run-lockpull.sh so imports stay inside Quickshell's config root.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../shell/components"
import "../../shell/singletons"

ShellRoot {
    id: root
    property var gesture: null
    property int lockCount: 0

    Theme { id: themeObject }

    PillBody {
        id: pillReference
        theme: themeObject
        backgroundOpacity: panel.backgroundOpacity
        visible: false
    }

    LockPullWindow {
        id: panel
        targetScreen: Quickshell.screens[0]
        theme: themeObject
    }

    Window {
        visible: (Quickshell.env("LOCK_PULL_PREVIEW") || "").length > 0
        width: 960
        height: 640
        color: "#41485e"

        LockPull {
            id: preview
            width: 960
            height: 640
            theme: themeObject
            userName: Quickshell.env("USER") || "Zestify"
            batteryText: "78% · On battery"
        }
    }

    function findGesture(item) {
        if (item.edgeHeight !== undefined && item.lockRequested !== undefined)
            return item;
        for (const child of item.children || []) {
            const found = findGesture(child);
            if (found)
                return found;
        }
        return null;
    }

    function findCurtain(item) {
        if (item.gradient !== undefined && item.backgroundOpacity !== undefined)
            return item;
        for (const child of item.children || []) {
            const found = findCurtain(child);
            if (found)
                return found;
        }
        return null;
    }

    Connections {
        target: root.gesture
        function onLockRequested() { root.lockCount++; }
    }

    IpcHandler {
        target: "lockPullTest"
        function state(): string {
            const g = root.gesture;
            return JSON.stringify({
                dragging: g.dragging, pull: g.pull, ready: g.ready,
                requestingLock: g.requestingLock, active: g.active,
                triggerDistance: g.triggerDistance, height: g.height,
                lockCount: root.lockCount
            });
        }
        function unlock(): void {
            Session.handleLockState(true);
            Session.handleLockState(false);
        }
    }

    Process {
        id: pointerTest
        command: ["python3", Quickshell.env("LOCK_PULL_TEST_SCRIPT"),
            Quickshell.shellDir + "/shell.qml", panel.targetScreen.name]
        stdout: StdioCollector { onStreamFinished: console.log(text.trim()) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) console.error(text.trim()); } }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                Qt.exit(exitCode);
                return;
            }
            console.log("LOCK PULL PASS: actual Wayland drag, release threshold, animation, Escape, lock handoff");
            const output = Quickshell.env("LOCK_PULL_PREVIEW") || "";
            if (output.length > 0) {
                preview.dragging = true;
                preview.pull = preview.height;
                captureTimer.start();
            } else {
                Qt.quit();
            }
        }
    }

    Timer {
        id: captureTimer
        interval: 300
        onTriggered: preview.grabToImage(result => {
            result.saveToFile(Quickshell.env("LOCK_PULL_PREVIEW"));
            Qt.quit();
        })
    }

    Timer {
        interval: 250
        running: true
        onTriggered: {
            try {
                const gesture = root.findGesture(panel.contentItem);
                root.gesture = gesture;
                if (!gesture || panel.mask.height !== gesture.edgeHeight)
                    throw new Error("Idle input mask is not limited to the top edge");
                const curtain = root.findCurtain(gesture);
                if (!curtain)
                    throw new Error("Curtain does not use pill chrome");
                panel.backgroundOpacity = 0.8;
                for (const opacity of [0.25, 0.75, 1]) {
                    themeObject.transparency = opacity;
                    if (curtain.gradient.stops[0].color.a !== pillReference.gradient.stops[0].color.a
                            || curtain.gradient.stops[1].color.a !== pillReference.gradient.stops[1].color.a)
                        throw new Error("Curtain did not follow pill transparency live");
                }
                panel.backgroundOpacity = 1;
                themeObject.transparency = 1;
                gesture.dragging = true;
                gesture.pull = gesture.height * 0.75;
                if (panel.mask.height !== gesture.height
                        || panel.WlrLayershell.keyboardFocus !== WlrKeyboardFocus.OnDemand)
                    throw new Error("Dragging does not capture input and Escape");
                gesture.dragging = false;
                gesture.requestingLock = true;
                if (panel.WlrLayershell.keyboardFocus !== WlrKeyboardFocus.OnDemand)
                    throw new Error("Keyboard input escapes while waiting for the locker");
                Session.handleLockState(true);
                if (gesture.active || panel.mask.height !== 0 || panel.visible)
                    throw new Error("Lock state does not clear the curtain and input mask");
                Session.handleLockState(false);
                if (panel.mask.height !== gesture.edgeHeight || !panel.visible)
                    throw new Error("Top-edge gesture was not restored after unlock");
                pointerTest.running = true;
            } catch (error) {
                console.error("LOCK PULL FAIL: " + error);
                Qt.exit(1);
            }
        }
    }
}
