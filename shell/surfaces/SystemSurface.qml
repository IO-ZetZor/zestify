pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

SurfaceFrame {
    id: root

    property var screen
    property var stats
    property var motion
    property var processes: []
    property real uptimeSeconds: 0

    title: "System"

    function formatBytes(value) {
        if (!value || value <= 0)
            return "0 B";
        if (value >= 1048576)
            return (value / 1048576).toFixed(1) + " MB";
        if (value >= 1024)
            return (value / 1024).toFixed(1) + " KB";
        return Math.round(value) + " B";
    }

    function formatRate(value) {
        return root.formatBytes(value) + "/s";
    }

    function formatUptime(seconds) {
        if (!seconds || seconds <= 0)
            return "--";
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (days > 0)
            return days + "d " + hours + "h";
        if (hours > 0)
            return hours + "h " + minutes + "m";
        return minutes + "m";
    }

    function parseProcesses(text) {
        const result = [];
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length && result.length < 7; i++) {
            const match = lines[i].match(/^\s*(.+?)\s+([\d.]+)\s+([\d.]+)\s*$/);
            if (!match)
                continue;
            result.push({
                name: match[1].trim(),
                cpu: Number(match[2]),
                mem: Number(match[3])
            });
        }
        return result;
    }

    component Sparkline: Item {
        id: spark

        property var values: []
        property real maxValue: 100
        property color colour
        property int capacity: 48

        function valueAt(index) {
            const start = Math.max(0, spark.values.length - spark.capacity);
            return spark.values[start + index] || 0;
        }

        Repeater {
            model: spark.capacity

            delegate: Rectangle {
                required property int index
                x: index * (spark.width / spark.capacity)
                width: Math.max(1, spark.width / spark.capacity - 1)
                height: Math.max(1, Math.min(1, spark.valueAt(index) / Math.max(0.0001, spark.maxValue)) * spark.height)
                anchors.bottom: parent.bottom
                radius: 0.5
                color: spark.colour
            }
        }
    }

    component StatCard: Rectangle {
        id: card

        property string label
        property string value
        property string detail: ""
        property var values: []
        property real maxValue: 100
        property color tint

        Layout.fillWidth: true
        Layout.preferredHeight: 78 * root.s
        radius: root.theme.r.tile * root.s
        color: root.theme.tileBg
        border.width: 1
        border.color: root.theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.theme.sp.m * root.s
            spacing: 1 * root.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 4 * root.s

                Text {
                    Layout.fillWidth: true
                    text: card.label
                    color: root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                Text {
                    text: card.value
                    color: root.theme.cream
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.meta * root.s
                }
            }

            Text {
                visible: card.detail.length > 0
                text: card.detail
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Sparkline {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 14 * root.s
                values: card.values
                maxValue: card.maxValue
                colour: card.tint
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 7 * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: 7 * root.s

            StatCard {
                label: "CPU"
                value: root.stats ? Math.round(root.stats.cpuPercent) + "%" : "--"
                values: root.stats ? root.stats.historyCpu : []
                maxValue: 100
                tint: root.theme.accent
            }

            StatCard {
                label: "Memory"
                value: root.stats && root.stats.ramTotal > 0
                    ? (root.stats.ramUsed / 1073741824).toFixed(1) + " / " + (root.stats.ramTotal / 1073741824).toFixed(1) + " GB"
                    : "--"
                values: root.stats ? root.stats.historyRam : []
                maxValue: root.stats && root.stats.ramTotal > 0 ? root.stats.ramTotal : 1
                tint: root.theme.accentDim
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 7 * root.s

            StatCard {
                label: "Network"
                value: root.stats ? root.formatRate(root.stats.netRate) : "--"
                detail: root.stats
                    ? "received " + root.formatBytes(root.stats.rxBytes) + " since boot"
                    : ""
                values: root.stats ? root.stats.historyNet : []
                maxValue: {
                    if (!root.stats || !root.stats.historyNet || root.stats.historyNet.length === 0)
                        return 1;
                    return Math.max(1, Math.max.apply(null, root.stats.historyNet));
                }
                tint: root.theme.accent
            }

            StatCard {
                label: "Package temp"
                value: root.stats && root.stats.gpuTemp > 0
                    ? root.stats.gpuTemp.toFixed(0) + "°C"
                    : "--"
                values: []
                tint: root.theme.accentDim
            }

            StatCard {
                label: "Battery"
                value: root.stats && root.stats.batteryPercent > 0
                    ? Math.round(root.stats.batteryPercent) + "%"
                    : "--"
                detail: root.stats ? root.stats.batteryTime : ""
                values: []
                tint: root.theme.accent
            }

            StatCard {
                label: "Uptime"
                value: root.formatUptime(root.uptimeSeconds)
                values: []
                tint: root.theme.accentDim
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * root.s

            Text {
                Layout.fillWidth: true
                text: "Top processes"
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.title * root.s
                font.weight: Font.Medium
            }

            Text {
                text: "CPU %   RAM %"
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.label * root.s
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.theme.r.tile * root.s
            color: root.theme.tileBg
            border.width: 1
            border.color: root.theme.border
            clip: true

            ListView {
                anchors.fill: parent
                anchors.margins: root.theme.sp.m * root.s
                model: root.processes
                spacing: 3 * root.s
                clip: true

                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 6 * root.s

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: root.theme.cream
                        font.family: root.theme.monoFont
                        font.pixelSize: root.theme.fs.meta * root.s
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.cpu.toFixed(1) + "%"
                        color: root.theme.dim
                        font.family: root.theme.monoFont
                        font.pixelSize: root.theme.fs.meta * root.s
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 52 * root.s
                    }

                    Text {
                        text: modelData.mem.toFixed(1) + "%"
                        color: root.theme.faint
                        font.family: root.theme.monoFont
                        font.pixelSize: root.theme.fs.meta * root.s
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 52 * root.s
                    }
                }
            }
        }
    }

    FileView {
        path: "/proc/uptime"
        blockLoading: true
        printErrors: false
        onLoaded: root.uptimeSeconds = parseFloat(text()) || 0
    }

    Process {
        id: processList
        command: ["sh", "-c", "ps -eo comm=,%cpu=,%mem= --sort=-%cpu | head -7"]
        stdout: StdioCollector {
            onStreamFinished: root.processes = root.parseProcesses(text)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: if (!processList.running) processList.running = true
    }

    Component.onCompleted: processList.running = true
}
