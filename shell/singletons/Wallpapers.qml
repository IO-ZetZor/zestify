pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/wallpapers.js" as WallpapersLib
import "."

Singleton {
    id: root

    property string globalPath: ""
    property var items: []
    property bool listing: false
    property bool refreshPending: false
    property bool busy: false
    property string lastError: ""
    property string actionFailure: ""
    readonly property string bin: Quickshell.env("ZESTI_BIN") || Quickshell.env("ZESTIFY_BIN") || "zesti"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/zestify"

    Component.onCompleted: refresh()

    readonly property var monitorPaths: {
        const paths = {};
        for (let i = 0; i < monitorInstances.count; i++) {
            const monitor = monitorInstances.objectAt(i);
            if (monitor && monitor.screenName)
                paths[monitor.screenName] = monitor.path;
        }
        return paths;
    }

    function currentFor(screenName) {
        return WallpapersLib.pick(root.globalPath, root.monitorPaths, screenName);
    }

    function refresh() {
        globalFile.reload();
        for (let i = 0; i < monitorInstances.count; i++) {
            const monitor = monitorInstances.objectAt(i);
            if (monitor)
                monitor.reload();
        }
        if (!listProcess.running) {
            root.listing = true;
            listProcess.running = true;
        } else {
            root.refreshPending = true;
        }
    }

    property var configChanges: Connections {
        target: Config.wallpaper
        function onDirChanged() { root.refresh(); }
    }

    function _parseList(text) {
        try {
            const parsed = JSON.parse(text);
            if (!Array.isArray(parsed))
                throw new Error("wallpaper list is not an array");
            root.items = parsed;
            root.lastError = root.actionFailure;
        } catch (e) {
            root.lastError = "Could not list wallpapers: " + e.message;
        }
    }

    function apply(item, monitorName) {
        const path = item && item.path ? item.path : String(item || "");
        if (!path.length)
            return;
        root.busy = true;
        root.actionFailure = "";
        root.lastError = "";
        actionProcess.command = [root.bin, "wallpaper", "set", path, "--monitor", monitorName];
        actionProcess.running = true;
    }

    function applyAll(item) {
        const path = item && item.path ? item.path : String(item || "");
        if (!path.length)
            return;
        root.busy = true;
        root.actionFailure = "";
        root.lastError = "";
        actionProcess.command = [root.bin, "wallpaper", "set", path, "--all"];
        actionProcess.running = true;
    }

    function random(monitorName) {
        root.busy = true;
        root.actionFailure = "";
        root.lastError = "";
        actionProcess.command = monitorName && monitorName.length
            ? [root.bin, "wallpaper", "random", "--monitor", monitorName]
            : [root.bin, "wallpaper", "random", "--all"];
        actionProcess.running = true;
    }

    property var listProcess: Process {
        command: [root.bin, "wallpaper", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root._parseList(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length)
                    root.lastError = message;
            }
        }
        onExited: code => {
            root.listing = false;
            if (code !== 0 && root.lastError.length === 0)
                root.lastError = "Could not list wallpapers";
            if (root.refreshPending) {
                root.refreshPending = false;
                root.refresh();
            }
        }
    }

    property var actionProcess: Process {
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: actionError
        }
        onExited: code => {
            root.busy = false;
            root.actionFailure = actionError.text.trim() || (code !== 0 ? "Wallpaper action failed" : "");
            root.lastError = root.actionFailure;
            root.refresh();
        }
    }

    property var globalFile: FileView {
        path: root.stateDir + "/wallpaper/path.txt"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.globalPath = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.globalPath = ""
    }

    property var monitorInstances: Instantiator {
        model: Quickshell.screens
        delegate: MonitorWallpaper {
            screenName: modelData.name
        }
    }
}
