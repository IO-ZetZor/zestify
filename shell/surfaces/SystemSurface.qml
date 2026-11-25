pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components"
import "../lib/usage.js" as Usage

SurfaceFrame {
    id: root

    property var screen
    property var stats
    property var motion
    property var processes: []
    property real uptimeSeconds: 0
    property string sortBy: "cpu"
    property bool sampling: true
    property var _gpuStats: null

    function syncGpuSampling() {
        const next = root.sampling && root.visible && root.stats
            && typeof root.stats.setGpuConsumer === "function" ? root.stats : null;
        if (root._gpuStats === next)
            return;
        if (root._gpuStats)
            root._gpuStats.setGpuConsumer(root, false);
        root._gpuStats = next;
        if (next)
            next.setGpuConsumer(root, true);
    }

    onStatsChanged: syncGpuSampling()
    onSamplingChanged: syncGpuSampling()
    onVisibleChanged: syncGpuSampling()
    Component.onDestruction: if (root._gpuStats) root._gpuStats.setGpuConsumer(root, false)

    readonly property real memoryPercent: stats ? Usage.percent(stats.ramUsed, stats.ramTotal) : 0
    readonly property var cpuHistory: stats ? stats.historyCpu : []
    readonly property var ramHistory: stats ? stats.historyRam : []
    readonly property var downloadHistory: stats ? stats.historyRx : []
    readonly property var uploadHistory: stats ? stats.historyTx : []
    readonly property int capacity: stats ? stats.historyCapacity : 60
    readonly property int sampleInterval: stats ? stats.interval : 1000
    readonly property real networkScale: Usage.scaleFor(downloadHistory, uploadHistory)
    readonly property var gpuDevices: stats ? stats.gpuDevices : []
    readonly property real processCpuScale: Math.max(100, Usage.peak(processes.map(item => item.cpu)))
    readonly property color uploadColour: root.theme.pick("tertiary", "c3c5dd")

    title: "System"

    function formatBytes(value) {
        if (!(value > 0))
            return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const index = Math.min(units.length - 1, Math.floor(Math.log(value) / Math.log(1024)));
        return (value / Math.pow(1024, index)).toFixed(index > 0 ? 1 : 0) + " " + units[index];
    }

    function formatRate(value) { return root.formatBytes(value) + "/s"; }

    function formatUptime(seconds) {
        if (!(seconds > 0)) return "—";
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        return days > 0 ? days + "d " + hours + "h" : (hours > 0 ? hours + "h " + minutes + "m" : minutes + "m");
    }

    function parseProcesses(text) {
        const result = [];
        for (const line of String(text || "").split("\n")) {
            const match = line.match(/^\s*(.+?)\s+([\d.]+)\s+([\d.]+)\s*$/);
            if (match && result.length < 6)
                result.push({ name: match[1].trim(), cpu: Number(match[2]), mem: Number(match[3]) });
        }
        return result;
    }

    function refreshProcesses() {
        if (root.sampling && !processList.running)
            processList.running = true;
    }

    onSortByChanged: refreshProcesses()

    component MetricCard: Rectangle {
        id: card
        property string label
        property string glyph
        property string value
        property string detail
        property bool memory: false
        property var values: []
        property real maximum: 100
        property int hoveredCore: -1
        readonly property var cores: root.stats ? root.stats.cpuCores : []

        Layout.fillWidth: true
        Layout.preferredHeight: 228 * root.s
        radius: 15 * root.s
        color: root.theme.withAlpha(root.theme.surfaceHigh, 0.78)
        border.width: 1
        border.color: root.theme.withAlpha(root.theme.outline, 0.16)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12 * root.s
            spacing: 5 * root.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 6 * root.s
                Text {
                    text: card.glyph
                    color: root.theme.accent
                    font.family: root.theme.iconFont
                    font.pixelSize: 15 * root.s
                }
                Text {
                    Layout.fillWidth: true
                    text: card.label
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                }
                Text {
                    text: "peak " + (card.memory ? Math.round(Usage.percent(Usage.peak(card.values), card.maximum)) : Math.round(Usage.peak(card.values))) + "%"
                    color: root.theme.faint
                    font.family: root.theme.monoFont
                    font.pixelSize: 9 * root.s
                }
            }

            Text {
                text: card.value
                color: root.theme.cream
                font.family: root.theme.monoFont
                font.pixelSize: 32 * root.s
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: card.detail
                color: root.theme.dim
                font.family: root.theme.fontFamily
                font.pixelSize: 10 * root.s
                elide: Text.ElideRight
            }

            UsageChart {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 70 * root.s
                theme: root.theme
                s: root.s
                values: card.values
                maximum: card.maximum
                capacity: root.capacity
                sampleInterval: root.sampleInterval
                seriesName: card.label
                colour: root.theme.accent
                topLabel: card.memory ? root.formatBytes(card.maximum) : "100%"
                bottomLabel: card.memory ? "0" : "0%"
                formatter: card.memory ? root.formatBytes : null
            }

            RowLayout {
                visible: !card.memory
                Layout.fillWidth: true
                Layout.preferredHeight: 20 * root.s
                spacing: 3 * root.s
                Repeater {
                    model: card.cores.slice(0, 24)
                    delegate: Rectangle {
                        id: core
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 3 * root.s
                        color: root.theme.withAlpha(root.theme.outline, 0.12)
                        clip: true
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(root.s, parent.height * core.modelData.percent / 100)
                            radius: parent.radius
                            color: root.theme.withAlpha(root.theme.accent, 0.65)
                            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: core.modelData.name.slice(3)
                            color: root.theme.dim
                            font.family: root.theme.monoFont
                            font.pixelSize: 7 * root.s
                        }
                        HoverHandler {
                            onHoveredChanged: card.hoveredCore = hovered ? core.index : -1
                        }
                    }
                }
            }

            Rectangle {
                visible: card.memory
                Layout.fillWidth: true
                Layout.preferredHeight: 8 * root.s
                radius: height / 2
                color: root.theme.withAlpha(root.theme.outline, 0.2)
                Rectangle {
                    width: parent.width * root.memoryPercent / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.theme.accent
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.memory
                    ? (root.stats ? root.formatBytes(Math.max(0, root.stats.ramTotal - root.stats.ramUsed)) + " available · " + root.formatBytes(root.stats.swapUsed) + " swap" : "Waiting for memory data")
                    : (card.hoveredCore >= 0 ? "Thread " + card.cores[card.hoveredCore].name.slice(3) + " · " + Math.round(card.cores[card.hoveredCore].percent) + "%"
                        : card.cores.length + " logical threads" + (card.cores.length > 24 ? " · showing first 24" : ""))
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: 9 * root.s
                elide: Text.ElideRight
            }
        }
    }

    component DetailTile: Rectangle {
        id: tile
        property string label
        property string value
        property string glyph
        Layout.fillWidth: true
        Layout.preferredHeight: 47 * root.s
        radius: 10 * root.s
        color: root.theme.withAlpha(root.theme.surfaceHigh, 0.6)
        RowLayout {
            anchors.fill: parent
            anchors.margins: 9 * root.s
            spacing: 9 * root.s
            Text {
                text: tile.glyph
                font.family: root.theme.iconFont
                font.pixelSize: 20 * root.s
                color: root.theme.accentDim
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1 * root.s
                Text {
                    text: tile.label
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: 9 * root.s
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.value
                    elide: Text.ElideRight
                    color: root.theme.cream
                    font.family: root.theme.monoFont
                    font.pixelSize: 13 * root.s
                }
            }
        }
    }

    component GpuCard: Rectangle {
        id: card
        property var gpu
        readonly property bool hasUsage: gpu.utilization !== null
        readonly property bool hasMemory: gpu.memoryUsed !== null && gpu.memoryTotal > 0
        readonly property bool hasTemperature: gpu.temperature !== null
        readonly property bool compact: !hasTemperature && !hasMemory

        Layout.fillWidth: true
        Layout.preferredHeight: (compact ? 116 : hasTemperature && hasMemory ? 164 : 142) * root.s
        radius: 15 * root.s
        color: root.theme.withAlpha(root.theme.surfaceHigh, 0.78)
        border.width: 1
        border.color: root.theme.withAlpha(root.theme.outline, 0.16)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12 * root.s
            spacing: 8 * root.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 7 * root.s
                Text {
                    text: "󰢮"
                    color: root.theme.accent
                    font.family: root.theme.iconFont
                    font.pixelSize: 15 * root.s
                }
                Text {
                    Layout.fillWidth: true
                    text: card.gpu.name
                    elide: Text.ElideRight
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                }
                Text {
                    text: card.gpu.driver || card.gpu.vendor
                    color: root.theme.faint
                    font.family: root.theme.monoFont
                    font.pixelSize: 9 * root.s
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15 * root.s
                ColumnLayout {
                    Layout.preferredWidth: (card.compact ? 150 : 190) * root.s
                    Layout.maximumWidth: (card.compact ? 150 : 190) * root.s
                    spacing: 5 * root.s
                    Text {
                        text: card.gpu.status === "suspended" ? "Sleeping"
                            : card.hasUsage ? Math.round(card.gpu.utilization) + "%" : "Unavailable"
                        color: root.theme.cream
                        font.family: root.theme.monoFont
                        font.pixelSize: (card.hasUsage ? (card.compact ? 26 : 30) : 18) * root.s
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: card.gpu.status === "suspended" ? "Power saving"
                            : card.gpu.source || "Usage telemetry unavailable"
                        color: root.theme.faint
                        font.family: root.theme.fontFamily
                        font.pixelSize: 9 * root.s
                    }
                    Text {
                        visible: card.hasTemperature
                        text: "Temperature  " + Math.round(card.gpu.temperature) + "°C"
                        color: root.theme.dim
                        font.family: root.theme.monoFont
                        font.pixelSize: 9 * root.s
                    }
                    Text {
                        visible: card.hasMemory
                        Layout.fillWidth: true
                        text: root.formatBytes(card.gpu.memoryUsed) + " / " + root.formatBytes(card.gpu.memoryTotal)
                        color: root.theme.dim
                        font.family: root.theme.monoFont
                        font.pixelSize: 9 * root.s
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: card.hasMemory
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4 * root.s
                        radius: height / 2
                        color: root.theme.withAlpha(root.theme.outline, 0.16)
                        Rectangle {
                            width: parent.width * Usage.percent(card.gpu.memoryUsed, card.gpu.memoryTotal) / 100
                            height: parent.height
                            radius: parent.radius
                            color: root.uploadColour
                        }
                    }
                }
                UsageChart {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    theme: root.theme
                    s: root.s
                    values: card.gpu.history
                    maximum: 100
                    capacity: root.capacity
                    sampleInterval: root.sampleInterval
                    seriesName: card.gpu.name
                    colour: root.theme.accent
                }
            }
        }
    }

    component SortChip: Rectangle {
        id: chip
        property string key
        property string label
        implicitWidth: chipLabel.implicitWidth + 14 * root.s
        implicitHeight: 22 * root.s
        radius: height / 2
        color: root.theme.withAlpha(root.sortBy === chip.key ? root.theme.accent : root.theme.outline, root.sortBy === chip.key ? 0.2 : 0.08)
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            color: root.sortBy === chip.key ? root.theme.accent : root.theme.faint
            font.family: root.theme.fontFamily
            font.pixelSize: 9 * root.s
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.sortBy = chip.key }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: dashboard.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: dashboard
            width: parent.width
            spacing: 9 * root.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 9 * root.s
                MetricCard {
                    label: "Processor"
                    glyph: "󰍛"
                    value: root.stats ? Math.round(root.stats.cpuPercent) + "%" : "—"
                    detail: "Total CPU usage"
                    values: root.cpuHistory
                }
                MetricCard {
                    label: "Memory"
                    glyph: "󰘚"
                    value: root.stats && root.stats.ramTotal > 0 ? Math.round(root.memoryPercent) + "%" : "—"
                    detail: root.stats ? root.formatBytes(root.stats.ramUsed) + " of " + root.formatBytes(root.stats.ramTotal) : "Waiting for memory data"
                    memory: true
                    values: root.ramHistory
                    maximum: root.stats ? Math.max(1, root.stats.ramTotal) : 1
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 133 * root.s + speedTest.implicitHeight
                radius: 15 * root.s
                color: root.theme.withAlpha(root.theme.surfaceHigh, 0.78)
                border.width: 1
                border.color: root.theme.withAlpha(root.theme.outline, 0.16)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12 * root.s
                    spacing: 7 * root.s
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16 * root.s
                        Text {
                            Layout.fillWidth: true
                            text: "Network traffic"
                            color: root.theme.cream
                            font.family: root.theme.fontFamily
                            font.pixelSize: 12 * root.s
                            font.weight: Font.Medium
                        }
                        Text {
                            text: "↓ " + (root.stats ? root.formatRate(root.stats.rxRate) : "—")
                            color: root.theme.accent
                            font.family: root.theme.monoFont
                            font.pixelSize: 12 * root.s
                        }
                        Text {
                            text: "↑ " + (root.stats ? root.formatRate(root.stats.txRate) : "—")
                            color: root.uploadColour
                            font.family: root.theme.monoFont
                            font.pixelSize: 12 * root.s
                        }
                    }
                    UsageChart {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: root.theme
                        s: root.s
                        values: root.downloadHistory
                        secondaryValues: root.uploadHistory
                        maximum: root.networkScale
                        capacity: root.capacity
                        sampleInterval: root.sampleInterval
                        colour: root.theme.accent
                        secondaryColour: root.uploadColour
                        seriesName: "↓"
                        secondaryName: "↑"
                        topLabel: root.formatRate(root.networkScale)
                        bottomLabel: "0"
                        formatter: root.formatRate
                    }
                    SpeedTestControl {
                        id: speedTest
                        Layout.fillWidth: true
                        theme: root.theme
                        s: root.s
                    }
                }
            }

            Text {
                text: "Graphics"
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: 12 * root.s
                font.weight: Font.Medium
            }

            Repeater {
                model: root.gpuDevices.length
                delegate: GpuCard {
                    required property int index
                    gpu: root.gpuDevices[index]
                }
            }

            Text {
                visible: root.gpuDevices.length === 0
                text: root.stats ? root.stats.gpuStatus : "Detecting GPUs…"
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: 10 * root.s
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 9 * root.s
                DetailTile {
                    label: "CPU temperature"
                    value: root.stats && root.stats.cpuTemp > 0 ? Math.round(root.stats.cpuTemp) + "°C" : "Unavailable"
                    glyph: "󰔏"
                }
                DetailTile {
                    label: "Battery"
                    value: root.stats && root.stats.batteryPercent > 0 ? Math.round(root.stats.batteryPercent) + "%" : "Unavailable"
                    glyph: "󰁹"
                }
                DetailTile {
                    label: "Uptime"
                    value: root.formatUptime(root.uptimeSeconds)
                    glyph: "󰥔"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5 * root.s
                Text {
                    Layout.fillWidth: true
                    text: "Busy processes"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                }
                SortChip { key: "cpu"; label: "CPU avg" }
                SortChip { key: "mem"; label: "Memory" }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2 * root.s
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "PROCESS"
                        color: root.theme.faint
                        font.family: root.theme.monoFont
                        font.pixelSize: 8 * root.s
                    }
                    Text {
                        Layout.preferredWidth: 124 * root.s
                        text: "CPU AVG"
                        color: root.theme.faint
                        font.family: root.theme.monoFont
                        font.pixelSize: 8 * root.s
                    }
                    Text {
                        Layout.preferredWidth: 124 * root.s
                        text: "MEMORY"
                        color: root.theme.faint
                        font.family: root.theme.monoFont
                        font.pixelSize: 8 * root.s
                    }
                }
                Repeater {
                    model: root.processes
                    delegate: RowLayout {
                        id: processRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 23 * root.s
                        spacing: 10 * root.s
                        Text {
                            Layout.fillWidth: true
                            text: processRow.modelData.name
                            color: root.theme.dim
                            font.family: root.theme.monoFont
                            font.pixelSize: 10 * root.s
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: ["cpu", "mem"]
                            delegate: RowLayout {
                                id: meter
                                required property string modelData
                                readonly property real value: processRow.modelData[meter.modelData]
                                Layout.preferredWidth: 124 * root.s
                                Layout.minimumWidth: 124 * root.s
                                Layout.maximumWidth: 124 * root.s
                                Layout.fillWidth: false
                                spacing: 7 * root.s
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 4 * root.s
                                    radius: height / 2
                                    color: root.theme.withAlpha(root.theme.outline, 0.16)
                                    Rectangle {
                                        width: parent.width * Math.min(1, meter.value / (meter.modelData === "cpu" ? root.processCpuScale : 100))
                                        height: parent.height
                                        radius: parent.radius
                                        color: meter.modelData === "cpu" ? root.theme.accent : root.uploadColour
                                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    }
                                }
                                Text {
                                    Layout.preferredWidth: 48 * root.s
                                    text: meter.value.toFixed(1) + "%"
                                    color: root.theme.dim
                                    horizontalAlignment: Text.AlignRight
                                    font.family: root.theme.monoFont
                                    font.pixelSize: 10 * root.s
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: root.processes.length === 0
                    text: "Waiting for process data…"
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: 10 * root.s
                }
            }
        }
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        blockLoading: true
        printErrors: false
        onLoaded: root.uptimeSeconds = parseFloat(text()) || 0
    }

    Process {
        id: processList
        command: ["ps", "-eo", "comm=,%cpu=,%mem=", root.sortBy === "mem" ? "--sort=-%mem" : "--sort=-%cpu"]
        stdout: StdioCollector { onStreamFinished: root.processes = root.parseProcesses(text) }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.sampling && root.visible
        onTriggered: { root.refreshProcesses(); uptimeFile.reload(); }
    }

    Component.onCompleted: { syncGpuSampling(); refreshProcesses(); }
}
