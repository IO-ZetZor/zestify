import QtQuick
import Quickshell.Io
import "../lib/visualiser.js" as Visualiser

// One shared cava stream. Consumers subscribe to `values`; this avoids
// spawning a separate cava process for every visualiser on screen.
Item {
    id: root

    property string scriptsDir: ""
    property string python: "python3"
    property bool active: true
    property bool processRequested: true
    property bool transients: false

    readonly property int barCount: 32
    readonly property int animationDuration: 400

    property var values: []
    property bool cavaActive: false
    property bool settled: true
    property var rawLevels: []
    // Party bins retain fixed gain; ordinary visualisers retain byte levels.
    property var spectrum: []
    property var frame: null
    property real displayReference: 0.24

    visible: false
    width: 0
    height: 0

    onRawLevelsChanged: {
        if (rawLevels.length !== values.length || rawLevels.some((value, index) => value !== values[index]))
            root.settled = false;
    }

    onActiveChanged: {
        if (root.active) {
            root.processRequested = true;
            return;
        }

        restartTimer.stop();
        root.processRequested = false;
        root.cavaActive = false;
        root.values = [];
        root.rawLevels = [];
        root.spectrum = [];
        root.frame = null;
        root.displayReference = 0.24;
        root.settled = true;
    }

    Timer {
        id: advanceTimer
        interval: 16
        repeat: true
        running: root.active && !root.settled
        triggeredOnStart: true
        onTriggered: {
            const result = Visualiser.advance(
                root.values, root.rawLevels, 16.0, root.animationDuration);
            root.values = result.values;
            root.settled = result.settled;
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
            root.rawLevels = next;
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
            .concat(root.transients ? ["--party"] : [])
        running: root.active && root.processRequested && root.scriptsDir.length > 0

        stdout: SplitParser {
            onRead: line => {
                const packet = Visualiser.parseFrame(line, root.barCount, root.transients);
                if (!packet)
                    return;
                let bars = packet.levels;
                if (root.transients) {
                    if (root.frame && (packet.sequence <= root.frame.sequence || packet.time <= root.frame.time))
                        return;
                    const dt = root.frame ? Math.max(0, packet.time - root.frame.time) : 16.67;
                    const result = Visualiser.displayLevels(root.displayReference, bars, dt);
                    root.displayReference = result.reference;
                    bars = result.values;
                }
                root.cavaActive = true;
                root.rawLevels = Visualiser.monstercatSides(bars);
                root.spectrum = packet.levels;
                root.frame = root.transients ? packet : null;
            }
        }

        onExited: {
            root.cavaActive = false;
            root.spectrum = [];
            root.frame = null;
            root.displayReference = 0.24;
            root.processRequested = false;
            if (root.active && root.scriptsDir.length > 0)
                restartTimer.restart();
        }
    }
}
