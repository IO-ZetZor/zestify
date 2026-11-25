pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
    id: root
    property bool recording: false
    property bool statusPending: false
    property int commandGeneration: 0
    property bool recordingDirectoryReady: false
    readonly property alias busy: command.running
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")

    function refreshStatus() {
        if (command.running || status.running) {
            root.statusPending = true;
            return;
        }
        root.statusPending = false;
        status.generation = root.commandGeneration;
        status.running = true;
    }

    function run(action) {
        if (root.busy || (action !== "screenshot" && action !== "record")) return false;
        root.commandGeneration++;
        command.action = action;
        command.launchPending = true;
        command.didStart = false;
        command.command = action === "screenshot"
            ? [Session.cli, "capture", "screenshot"]
            : [Session.cli, "capture", "record", "toggle"];
        command.running = true;
        return true;
    }

    function announceRecording(value, path, error, saved) {
        root.recording = value;
        Notifications.notify(value ? "Recording started" : "Recording stopped",
            error || (value ? "Screen recording is active." : saved
                ? "Video saved" + (path ? " to " + path : ".") : "Screen recording is no longer active."),
            "normal", "Zestify", 5000);
    }

    Component.onCompleted: prepareState.running = true

    Process {
        id: prepareState
        command: ["mkdir", "-p", root.stateHome + "/zestify/record"]
        onExited: (exitCode, exitStatus) => {
            // FileView needs an existing parent to watch the first recording.
            root.recordingDirectoryReady = exitCode === 0 && exitStatus === 0;
            root.refreshStatus();
        }
    }

    FileView {
        path: root.recordingDirectoryReady ? root.stateHome + "/zestify/record/recording" : ""
        preload: root.recordingDirectoryReady
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); root.refreshStatus(); }
    }
    Timer {
        interval: 1000
        repeat: true
        // Watch the marker for starts; poll a live PID for unexpected exits.
        running: !Session.locked && Session.dpmsActive
            && (root.recording || ShellState.shortcutsOwner.length > 0)
        onTriggered: root.refreshStatus()
    }
    Connections {
        target: Session
        function onDpmsActiveChanged() { if (Session.dpmsActive) root.refreshStatus(); }
        function onLockedChanged() { if (!Session.locked) root.refreshStatus(); }
    }
    Process {
        id: status
        property int generation: 0
        command: [Session.cli, "capture", "record", "status"]
        stdout: StdioCollector { id: statusOutput }
        onExited: (exitCode, exitStatus) => {
            if (generation !== root.commandGeneration) root.statusPending = true;
            else if (!root.busy && exitCode === 0 && exitStatus === 0) {
                try {
                    const result = JSON.parse(statusOutput.text);
                    if (typeof result.recording === "boolean" && root.recording !== result.recording)
                        root.announceRecording(result.recording, result.path, result.error, false);
                } catch (error) {}
            }
            if (root.statusPending && !root.busy) root.refreshStatus();
        }
    }
    Process {
        id: command
        property string action: ""
        property bool launchPending: false
        property bool didStart: false
        onStarted: didStart = true
        onRunningChanged: {
            // Quickshell emits no exited signal when the executable cannot start.
            if (!running && launchPending && !didStart) {
                launchPending = false;
                Notifications.notify("Capture failed", "Could not start " + Session.cli + ".",
                    "normal", "Zestify", 5000);
            }
        }
        stderr: StdioCollector { id: errors }
        stdout: StdioCollector { id: output }
        onExited: (exitCode, exitStatus) => {
            launchPending = false;
            let result = null;
            try { result = JSON.parse(output.text); } catch (error) {}
            if (exitCode !== 0 || exitStatus !== 0 || !result || result.ok !== true) {
                Notifications.notify("Capture failed", (result && result.error) || errors.text.trim()
                    || "Could not run the capture command.", "normal", "Zestify", 5000);
            } else if (!result.cancelled) {
                if (action === "screenshot") {
                    Notifications.notify("Screenshot taken", "Copied to clipboard"
                        + (result.path ? " and saved to " + result.path : "."), "normal", "Zestify", 5000);
                } else if (typeof result.recording === "boolean") {
                    root.announceRecording(result.recording, result.path, "", !result.recording);
                }
            }
            root.refreshStatus();
        }
    }
}
