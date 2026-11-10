pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "idle"
    property string error: ""
    property real download: 0
    property real upload: 0
    property real latency: 0
    property bool _requested: false
    readonly property bool busy: root._requested || process.running
    readonly property string status: {
        if (root.state === "latency") return "Measuring latency…";
        if (root.state === "download") return "Testing download…";
        if (root.state === "upload") return "Testing upload…";
        if (root.state === "error") return root.error;
        if (root.state === "cancelled") return "Test cancelled";
        if (root.state === "done") return "Cloudflare · estimated internet speed";
        return "Measure internet speed";
    }

    function start() {
        if (root.busy)
            return;
        root.error = "";
        root.download = 0;
        root.upload = 0;
        root.latency = 0;
        root.state = "latency";
        root._requested = true;
    }

    function cancel() {
        if (!root.busy)
            return;
        root.state = "cancelled";
        root._requested = false;
    }

    function fail(message) {
        root.error = message;
        root.state = "error";
    }

    function receive(text) {
        if (!root._requested || root.state === "cancelled")
            return;
        try {
            const data = JSON.parse(text);
            if (data.type === "progress" && ["latency", "download", "upload"].includes(data.stage)) {
                root.state = data.stage;
            } else if (data.type === "result" && [data.download, data.upload, data.latency]
                    .every(value => typeof value === "number" && Number.isFinite(value) && value >= 0)) {
                root.download = data.download;
                root.upload = data.upload;
                root.latency = data.latency;
                root.state = "done";
            } else if (data.type === "error" && typeof data.error === "string") {
                root.fail(data.error);
            } else {
                root.fail("Invalid speed test result. Try again.");
            }
        } catch (error) {
            root.fail("Invalid speed test result. Try again.");
        }
    }

    Process {
        id: process
        command: [Quickshell.env("PYTHON") || "python3",
            (Quickshell.env("ZESTIFY_SCRIPTS") || Quickshell.shellDir + "/../scripts") + "/speed-test.py"]
        running: root._requested
        stdout: SplitParser { onRead: data => root.receive(data) }
        onRunningChanged: {
            if (!running && root._requested) {
                root._requested = false;
                if (root.state !== "done" && root.state !== "error")
                    root.fail("Speed test could not finish. Try again.");
            }
        }
    }

    Timer {
        interval: 60000
        running: root._requested
        onTriggered: {
            root.fail("Speed test timed out. Try again.");
            root._requested = false;
        }
    }
}
