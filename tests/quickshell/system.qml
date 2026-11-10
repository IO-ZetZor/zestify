import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/surfaces"

ShellRoot {
    id: root
    property var fixtureGpus: []
    property int hotplugPhase: 0
    Theme { id: theme }

    QtObject {
        id: stats
        property real cpuPercent: 38
        property real ramUsed: 8.4 * 1073741824
        property real ramTotal: 16 * 1073741824
        property real swapUsed: 256 * 1048576
        property real cpuTemp: 54
        property string gpuStatus: ""
        property var gpuDevices: [
            {id: "0000:00:02.0", name: "Intel Iris Xe Graphics", vendor: "Intel", driver: "i915", status: "active",
                utilization: 24, temperature: null, memoryUsed: null, memoryTotal: null, source: "Visible clients",
                history: Array.from({length: 60}, (_, i) => 10 + 20 * Math.abs(Math.sin(i / 7)))},
            {id: "0000:03:00.0", name: "NVIDIA GeForce RTX 4060", vendor: "NVIDIA", driver: "nvidia", status: "active",
                utilization: 62, temperature: 58, memoryUsed: 2.6 * 1073741824, memoryTotal: 8 * 1073741824, source: "GPU usage",
                history: Array.from({length: 60}, (_, i) => 20 + 50 * Math.abs(Math.sin(i / 10)))}
        ]
        property real batteryPercent: 76
        property real rxRate: 1.6 * 1048576
        property real txRate: 180 * 1024
        property int historyCapacity: 60
        property int interval: 1000
        property var cpuCores: Array.from({length: 12}, (_, i) => ({name: "cpu" + i, percent: 5 + i * 7}))
        property var historyCpu: Array.from({length: 60}, (_, i) => 15 + 30 * Math.abs(Math.sin(i / 8)) + 10 * Math.sin(i / 2))
        property var historyRam: Array.from({length: 60}, (_, i) => (7.3 + i / 55 + Math.sin(i / 9) * 0.3) * 1073741824)
        property var historyRx: Array.from({length: 60}, (_, i) => (0.2 + Math.pow(Math.sin(i / 12), 4) * 1.4) * 1048576)
        property var historyTx: Array.from({length: 60}, (_, i) => (0.05 + Math.pow(Math.sin(i / 7), 2) * 0.15) * 1048576)
    }

    Window {
        id: window
        visible: true
        width: 820
        height: 1080
        color: theme.surface
        SystemSurface {
            id: surface
            anchors.fill: parent
            theme: theme
            stats: stats
            sampling: false
            processes: [
                {name: "firefox", cpu: 38.2, mem: 17.4},
                {name: "quickshell", cpu: 12.1, mem: 3.2},
                {name: "code", cpu: 7.6, mem: 8.1},
                {name: "Hyprland", cpu: 4.5, mem: 1.1},
                {name: "pipewire", cpu: 1.7, mem: 0.4},
                {name: "kitty", cpu: 0.8, mem: 0.7}
            ]
        }
    }

    function charts(item, result) {
        if (item.seriesName !== undefined && item.sampleInterval !== undefined)
            result.push(item);
        for (const child of item.children || []) root.charts(child, result);
    }

    function gpuCards(item, result) {
        if (item.compact !== undefined && item.gpu !== undefined)
            result.push(item);
        for (const child of item.children || []) root.gpuCards(child, result);
    }

    function hasText(item, text) {
        if (item.text === text)
            return true;
        for (const child of item.children || []) {
            if (root.hasText(child, text))
                return true;
        }
        return false;
    }

    Timer {
        id: hotplugTimer
        interval: 50
        repeat: true
        onTriggered: {
            try {
                const graphs = [];
                root.charts(surface, graphs);
                if (root.hotplugPhase === 0) {
                    stats.gpuDevices = root.fixtureGpus.map(gpu => Object.assign({}, gpu,
                        {status: "suspended", utilization: null, temperature: null, memoryUsed: null, history: []}));
                } else if (root.hotplugPhase === 1) {
                    if (!root.hasText(surface, "Sleeping") || graphs[3].values.length !== 0)
                        throw new Error("Suspended GPU state did not update");
                    stats.gpuDevices = [root.fixtureGpus[0]];
                } else if (root.hotplugPhase === 2) {
                    if (graphs.length !== 4)
                        throw new Error("GPU removal did not remove its chart");
                    stats.gpuDevices = [];
                    stats.gpuStatus = "No GPUs detected";
                } else if (root.hotplugPhase === 3) {
                    if (graphs.length !== 3 || !root.hasText(surface, "No GPUs detected"))
                        throw new Error("Empty GPU state did not load");
                    stats.gpuDevices = root.fixtureGpus;
                } else {
                    if (graphs.length !== 5)
                        throw new Error("GPU hotplug did not restore charts");
                    console.log("SYSTEM PASS: live integrated/discrete GPU charts, unavailable readings, sleep and hotplug");
                    Qt.quit();
                }
                root.hotplugPhase++;
            } catch (error) {
                console.error("SYSTEM FAIL: " + error);
                Qt.quit();
            }
        }
    }

    Timer {
        interval: 250
        running: true
        onTriggered: {
            try {
                const graphs = [];
                root.charts(surface, graphs);
                if (graphs.length !== 5 || surface.memoryPercent !== 52.5)
                    throw new Error("Usage graphs did not load");
                const gpuGraphs = graphs.slice(3);
                const cards = [];
                root.gpuCards(surface, cards);
                if (cards.length !== 2 || !cards[0].compact || cards[1].compact || cards[0].height >= cards[1].height)
                    throw new Error("GPU cards do not shrink for missing temperature/memory");
                if (cards[0].hasMemory || cards[0].hasTemperature)
                    throw new Error("Missing GPU telemetry is still displayed");
                stats.gpuDevices = stats.gpuDevices.map((gpu, index) => Object.assign({}, gpu,
                    {utilization: 80 + index, history: [20, 40, 80 + index]}));
                if (gpuGraphs[0].values[2] !== 80 || gpuGraphs[1].values[2] !== 81)
                    throw new Error("Integrated/discrete GPU history did not update live");
                stats.gpuDevices = stats.gpuDevices.map(gpu => Object.assign({}, gpu,
                    {history: Array.from({length: 60}, (_, i) => 20 + 50 * Math.abs(Math.sin(i / 10)))}));
                stats.historyCpu = [10, 30, 70];
                if (graphs[0].values[2] !== 70)
                    throw new Error("CPU history did not update live");
                stats.historyCpu = Array.from({length: 60}, (_, i) => 15 + 30 * Math.abs(Math.sin(i / 8)) + 10 * Math.sin(i / 2));
                if (surface.formatBytes(1073741824) !== "1.0 GiB")
                    throw new Error("Memory formatting is incorrect");
                stats.historyTx = [8 * 1048576];
                if (surface.networkScale < 8 * 1048576)
                    throw new Error("Upload history is clipped");
                stats.historyTx = Array.from({length: 60}, (_, i) => (0.05 + Math.pow(Math.sin(i / 7), 2) * 0.15) * 1048576);
                surface.grabToImage(result => {
                    result.saveToFile(Quickshell.env("SYSTEM_PREVIEW"));
                    root.fixtureGpus = stats.gpuDevices;
                    hotplugTimer.start();
                });
            } catch (error) {
                console.error("SYSTEM FAIL: " + error);
                Qt.quit();
            }
        }
    }
}
