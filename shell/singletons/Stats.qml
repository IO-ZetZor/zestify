pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../lib/proc.js" as Proc
import "."

Singleton {
    id: root

    property real cpuPercent: 0
    property var cpuCores: []
    property real ramUsed: 0
    property real ramTotal: 0
    property real swapUsed: 0
    property real swapTotal: 0
    property real rxBytes: 0
    property real txBytes: 0
    property real netRate: 0
    property real rxRate: 0
    property real txRate: 0
    property real cpuTemp: 0
    property var gpuDevices: []
    property string gpuStatus: "Detecting GPUs…"
    property real batteryPercent: 0
    property string batteryTime: ""
    property var historyCpu: []
    property var historyRam: []
    property var historyNet: []
    property var historyRx: []
    property var historyTx: []
    property int interval: Config.system.pollInterval
    readonly property int historyCapacity: Proc.historyCapacity(Config.system.graphSeconds, root.interval)
    property bool running: false

    property var _previousCpu: null
    property var _previousCores: null
    property var _previousNet: null
    property real _previousNetTime: 0
    property string _cpuTempPath: ""
    property bool _gpuRequested: true
    property bool _gpuStarted: false
    property bool _gpuPending: false

    function start() {
        if (running)
            return;
        running = true;
        _sampleBattery();
        sample();
    }

    function stop() {
        running = false;
    }

    function sample() {
        statFile.reload();
        memFile.reload();
        netFile.reload();
        if (root._cpuTempPath.length)
            cpuTempFile.reload();
        _sampleGpus();
    }

    function _push(list, value) {
        const next = list.slice();
        next.push(value);
        while (next.length > root.historyCapacity)
            next.shift();
        return next;
    }

    function _onStat(text) {
        const sample = Proc.parseCpu(text);
        if (root._previousCpu)
            root.cpuPercent = Proc.cpuPercent(root._previousCpu, sample);
        root._previousCpu = sample;
        const cores = Proc.parseCpuCores(text);
        root.cpuCores = Proc.corePercents(root._previousCores, cores);
        root._previousCores = cores;
        root.historyCpu = root._push(root.historyCpu, root.cpuPercent);
    }

    function _onMeminfo(text) {
        const info = Proc.parseMeminfo(text);
        root.ramTotal = info.memTotal;
        root.ramUsed = info.used;
        root.swapUsed = info.swapUsed;
        root.swapTotal = info.swapTotal;
        root.historyRam = root._push(root.historyRam, info.used);
    }

    function _onNetdev(text) {
        const net = Proc.parseNetdev(text);
        root.rxBytes = net.rx;
        root.txBytes = net.tx;
        const now = Date.now();
        const rates = Proc.networkRates(root._previousNet, net, (now - root._previousNetTime) / 1000);
        root.rxRate = rates.rx;
        root.txRate = rates.tx;
        root.netRate = rates.rx + rates.tx;
        root.historyNet = root._push(root.historyNet, root.netRate);
        root.historyRx = root._push(root.historyRx, root.rxRate);
        root.historyTx = root._push(root.historyTx, root.txRate);
        root._previousNet = net;
        root._previousNetTime = now;
    }

    function _sampleBattery() {
        const device = UPower.displayDevice;
        if (!device) {
            root.batteryPercent = 0;
            root.batteryTime = "";
            return;
        }
        root.batteryPercent = device.percentage * 100;
        let secs = device.timeToEmpty;
        if (device.state === UPowerDeviceState.Charging)
            secs = device.timeToFull;
        if (secs > 0 && secs < 86400) {
            const h = Math.floor(secs / 3600);
            const m = Math.floor((secs % 3600) / 60);
            root.batteryTime = h + "h " + m + "m";
        } else if (device.state === UPowerDeviceState.FullyCharged) {
            root.batteryTime = "full";
        } else if (UPower.onBattery) {
            root.batteryTime = "estimating";
        } else {
            root.batteryTime = "";
        }
    }

    function _sampleGpus() {
        if (!root._gpuStarted || root._gpuPending)
            return;
        root._gpuPending = true;
        gpuMonitor.write("sample\n");
    }

    function _onGpus(text) {
        root._gpuPending = false;
        try {
            const devices = JSON.parse(text);
            if (!Array.isArray(devices))
                throw new Error("Invalid GPU sample");
            root.gpuDevices = devices.map(device => {
                const previous = root.gpuDevices.find(item => item.id === device.id);
                device.history = device.utilization === null ? []
                    : root._push(previous ? previous.history : [], device.utilization);
                return device;
            });
            root.gpuStatus = devices.length ? "" : "No GPUs detected";
        } catch (error) {
            root.gpuDevices = [];
            root.gpuStatus = "GPU telemetry unavailable";
        }
    }

    function _gpuStopped() {
        root._gpuStarted = false;
        root._gpuPending = false;
        root.gpuDevices = [];
        if (root.running && root._gpuRequested) {
            root._gpuRequested = false;
            root.gpuStatus = "GPU telemetry unavailable";
            gpuRestartTimer.restart();
        }
    }

    property var statFile: FileView {
        path: "/proc/stat"
        blockLoading: true
        printErrors: false
        onLoaded: root._onStat(text())
        onFileChanged: reload()
    }

    property var memFile: FileView {
        path: "/proc/meminfo"
        blockLoading: true
        printErrors: false
        onLoaded: root._onMeminfo(text())
        onFileChanged: reload()
    }

    property var netFile: FileView {
        path: "/proc/net/dev"
        blockLoading: true
        printErrors: false
        onLoaded: root._onNetdev(text())
        onFileChanged: reload()
    }

    property var cpuTempFile: FileView {
        path: root._cpuTempPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            const milli = parseInt(text().trim(), 10);
            if (!isNaN(milli))
                root.cpuTemp = milli / 1000;
        }
    }

    Process {
        id: cpuTempFinder
        running: true
        command: ["sh", "-c", "for z in /sys/class/hwmon/hwmon*; do [ \"$(cat $z/name 2>/dev/null)\" = coretemp ] && { echo $z/temp1_input; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root._cpuTempPath = text.trim()
        }
    }

    Process {
        id: gpuMonitor
        command: [Quickshell.env("PYTHON") || "python3",
            (Quickshell.env("ZESTIFY_SCRIPTS") || Quickshell.shellDir + "/../scripts") + "/gpu-monitor.py"]
        running: root.running && root._gpuRequested
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root._onGpus(data) }
        onStarted: {
            root._gpuStarted = true;
            root._sampleGpus();
        }
        onRunningChanged: if (!running) root._gpuStopped()
    }

    Timer {
        id: gpuRestartTimer
        interval: 5000
        onTriggered: root._gpuRequested = true
    }

    property var timer: Timer {
        interval: root.interval
        repeat: true
        running: root.running
        onTriggered: root.sample()
    }

    property var batteryTimer: Timer {
        interval: 30000
        repeat: true
        running: root.running
        onTriggered: root._sampleBattery()
    }

    Connections {
        target: UPower.displayDevice
        function onPercentageChanged() { root._sampleBattery(); }
        function onStateChanged() { root._sampleBattery(); }
        function onTimeToEmptyChanged() { root._sampleBattery(); }
        function onTimeToFullChanged() { root._sampleBattery(); }
    }
}
