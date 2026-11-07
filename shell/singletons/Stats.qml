pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../lib/proc.js" as Proc

Singleton {
    id: root

    property real cpuPercent: 0
    property real ramUsed: 0
    property real ramTotal: 0
    property real swapUsed: 0
    property real rxBytes: 0
    property real txBytes: 0
    property real netRate: 0
    property real gpuTemp: 0
    property real batteryPercent: 0
    property string batteryTime: ""
    property var historyCpu: []
    property var historyRam: []
    property var historyNet: []
    property int interval: 1000
    property bool running: false

    property var _previousCpu: null
    property var _previousNet: null
    property string _gpuPath: ""

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
        _sampleGpuTemp();
    }

    function _push(list, value) {
        const next = list.slice();
        next.push(value);
        while (next.length > 60)
            next.shift();
        return next;
    }

    function _onStat(text) {
        const sample = Proc.parseCpu(text);
        if (root._previousCpu)
            root.cpuPercent = Proc.cpuPercent(root._previousCpu, sample);
        root._previousCpu = sample;
        root.historyCpu = root._push(root.historyCpu, root.cpuPercent);
    }

    function _onMeminfo(text) {
        const info = Proc.parseMeminfo(text);
        root.ramTotal = info.memTotal;
        root.ramUsed = info.used;
        root.swapUsed = info.swapUsed;
        root.historyRam = root._push(root.historyRam, info.used);
    }

    function _onNetdev(text) {
        const net = Proc.parseNetdev(text);
        root.rxBytes = net.rx;
        root.txBytes = net.tx;
        root.netRate = Proc.netRate(root._previousNet, net, root.interval / 1000);
        root.historyNet = root._push(root.historyNet, root.netRate);
        root._previousNet = net;
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

    function _sampleGpuTemp() {
        if (!root._gpuPath.length)
            return;
        gpuFile.reload();
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

    property var gpuFile: FileView {
        path: root._gpuPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            const milli = parseInt(text().trim(), 10);
            if (!isNaN(milli))
                root.gpuTemp = milli / 1000;
        }
    }

    Process {
        id: gpuFinder
        running: true
        command: ["sh", "-c", "for z in /sys/class/hwmon/hwmon*; do [ \"$(cat $z/name 2>/dev/null)\" = coretemp ] && { echo $z/temp1_input; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root._gpuPath = text.trim()
        }
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
