pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../lib/visualiser.js" as Visualiser

Item {
    id: root

    property var theme
    property real s: 1
    property var motion
    property string scriptsDir: ""
    property string python: "python3"
    property bool active: true
    property var levels: []
    property bool cavaActive: false
    property bool processRequested: true

    readonly property int barCount: 32
    readonly property real barSpacing: 3 * root.s
    readonly property real minHeight: 2 * root.s
    readonly property real maxHeight: Math.max(root.minHeight, root.height - 2 * root.s)

    // Exponential interpolation, matching Caelestia's VisualiserBars.
    // tau = animationDuration / 3 gives the same attack curve Caelestia uses.
    // Caelestia feeds Tokens.anim.durations.normal (400 ms) here.
    readonly property int animationDuration: 400
    property var displayLevels: []
    property bool settled: true

    implicitWidth: 320 * root.s
    implicitHeight: 64 * root.s

    onActiveChanged: {
        if (root.active) {
            root.processRequested = true;
        } else {
            restartTimer.stop();
            root.processRequested = false;
            root.cavaActive = false;
            root.levels = [];
            root.displayLevels = [];
            for (let i = 0; i < root.barCount; i++) {
                const bar = barsRepeater.itemAt(i);
                if (bar)
                    bar.level = 0;
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.barSpacing

        Repeater {
            id: barsRepeater
            model: root.barCount

            Item {
                id: barItem
                required property int index
                property real level: 0

                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.minHeight + barItem.level * (root.maxHeight - root.minHeight)
                    radius: Math.min(width, height) / 2
                    color: root.theme.accent
                }
            }
        }
    }

    // Advance display values toward the current targets and push them straight
    // into each bar. We deliberately avoid bindings on the var arrays here:
    // replacing a var array does not reliably re-evaluate derived delegate
    // bindings under Quickshell, which left every bar stuck at minHeight.
    Timer {
        id: advanceTimer
        interval: 16
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            const result = Visualiser.advance(
                root.displayLevels, root.levels, 16.0, root.animationDuration);

            root.displayLevels = result.values;
            root.settled = result.settled;

            for (let i = 0; i < root.barCount; i++) {
                const bar = barsRepeater.itemAt(i);
                if (bar)
                    bar.level = i < result.values.length ? result.values[i] : 0;
            }
        }
    }

    // Fallback animation while cava has no live data (e.g. silent output).
    // Real cava data replaces it as soon as the first frame arrives.
    Timer {
        interval: 100
        running: root.active && !root.cavaActive
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now() / 1000;
            const next = [];
            for (let i = 0; i < root.barCount; i++)
                next.push(0.16 + 0.22 * Math.abs(Math.sin(now * 1.3 + i * 0.9)));
            root.levels = next;
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: root.processRequested = true
    }

    Process {
        id: cavaMonitor
        command: [root.python, root.scriptsDir + "/cava-monitor.py"]
        running: root.active && root.processRequested && root.scriptsDir.length > 0

        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";");
                if (parts.length !== root.barCount)
                    return;
                const raw = [];
                for (let i = 0; i < parts.length; i++) {
                    const value = Number(parts[i]);
                    if (!Number.isFinite(value))
                        return;
                    raw.push(Math.min(1, Math.max(0, value / 255)));
                }

                // Stereo: first half is the left channel, second half the
                // right channel. Smooth each side independently.
                root.levels = Visualiser.monstercatSides(raw);
                root.cavaActive = true;
            }
        }

        onExited: {
            root.cavaActive = false;
            root.processRequested = false;
            if (root.active && root.scriptsDir.length > 0)
                restartTimer.restart();
        }
    }
}
