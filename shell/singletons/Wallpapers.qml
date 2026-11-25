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
    property var preparedCommand: null
    property string applySource: ""
    readonly property bool preparing: preparedCommand !== null
    signal applied()
    signal applyFailed()
    // A preview belongs to one display and never changes committed paths or app themes.
    property string previewOwner: ""
    property var previewItem: null
    property var previewScheme: null
    property string previewError: ""
    property var previewCache: ({})
    readonly property string previewKey: previewItem
        ? JSON.stringify([previewOwner, previewItem.path, Config.theme.mode, Config.theme.smartScheme]) : ""
    readonly property string bin: Quickshell.env("ZESTI_BIN") || Quickshell.env("ZESTIFY_BIN") || "zesti"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/zestify"

    Component.onCompleted: {
        refresh();
        refreshPalettes();
    }

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

    function preview(item, screenName) {
        if (root.busy || Session.locked || !item || !item.path || !screenName)
            return;
        if (item.path === root.currentFor(screenName)) {
            root.clearPreview(screenName);
            return;
        }
        root.previewOwner = screenName;
        root.previewItem = item;
        WallpaperEffects.warm(item.path);
    }

    function clearPreview(screenName) {
        if (screenName && root.previewOwner !== screenName)
            return;
        root.previewItem = null;
        root.previewOwner = "";
        root.previewCache = ({});
    }

    function previewFor(screenName) {
        return root.previewOwner === screenName ? root.previewItem : null;
    }

    function previewSchemeFor(screenName) {
        return root.previewOwner === screenName ? root.previewScheme : null;
    }

    onPreviewKeyChanged: {
        root.previewScheme = null;
        root.previewError = "";
        previewTimer.stop();
        if (root.previewKey.length) {
            if (root.previewCache[root.previewKey])
                root.previewScheme = root.previewCache[root.previewKey];
            else
                previewTimer.restart();
        }
    }

    property var previewTimer: Timer {
        interval: 120
        onTriggered: {
            if (!root.previewItem)
                return;
            if (root.previewProcess.running) {
                restart();
                return;
            }
            root.previewProcess.key = root.previewKey;
            root.previewProcess.command = [root.bin, "wallpaper", "print", root.previewItem.path,
                "--mode", Config.theme.mode];
            root.previewProcess.running = true;
        }
    }

    property var previewProcess: Process {
        property string key: ""
        stdout: StdioCollector { id: previewOutput }
        stderr: StdioCollector { id: previewFailure }
        onExited: (code, status) => {
            if (key !== root.previewKey || !root.previewItem)
                return;
            if (code !== 0 || status !== 0) {
                root.previewError = previewFailure.text.trim() || "Could not preview wallpaper colours";
                return;
            }
            try {
                const colours = JSON.parse(previewOutput.text);
                if (!colours.primary || !colours.surface || !colours.onSurface)
                    throw new Error("Incomplete preview palette");
                root.previewScheme = {colours: colours};
                const cache = Object.assign({}, root.previewCache);
                if (Object.keys(cache).length >= 16)
                    delete cache[Object.keys(cache)[0]];
                cache[key] = root.previewScheme;
                root.previewCache = cache;
            } catch (error) {
                root.previewError = "Could not preview wallpaper colours: " + error.message;
            }
        }
    }

    property var previewSessionChanges: Connections {
        target: Session
        function onLockedChanged() { if (Session.locked) root.clearPreview(); }
    }

    function refresh(rescan) {
        // A rescan may replace an image at the same path. The CLI validates
        // size/mtime before reusing its persistent subject maps.
        if (rescan === true) WallpaperEffects.invalidate();
        if (root.previewItem && root.previewError.length) {
            root.previewError = "";
            root.previewTimer.restart();
        }
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
        function onDirChanged() { root.refresh(true); }
    }

    property var themeChanges: Connections {
        target: Config.theme
        function onSmartSchemeChanged() { root.refreshPalettes(); }
    }

    function refreshPalettes() {
        paletteRefreshTimer.restart();
    }

    property var paletteRefreshTimer: Timer {
        interval: 200
        onTriggered: {
            if (root.busy || actionProcess.running) {
                restart();
                return;
            }
            root.busy = true;
            root.actionFailure = "";
            root.lastError = "";
            actionProcess.command = [root.bin, "wallpaper", "refresh"];
            actionProcess.running = true;
        }
    }

    function _parseList(text) {
        try {
            const parsed = JSON.parse(text);
            if (!Array.isArray(parsed))
                throw new Error("wallpaper list is not an array");
            // Opening the studio refreshes the list. Preserve loaded delegates
            // when the collection is unchanged instead of rebuilding the strip.
            if (JSON.stringify(parsed) !== JSON.stringify(root.items))
                root.items = parsed;
            root.lastError = root.actionFailure;
        } catch (e) {
            root.lastError = "Could not list wallpapers: " + e.message;
        }
    }

    function apply(item, monitorName) {
        if (root.busy) return;
        const path = item && item.path ? item.path : String(item || "");
        if (!path.length)
            return;
        root.busy = true;
        root.actionFailure = "";
        root.lastError = "";
        root.applySource = path;
        root.preparedCommand = [root.bin, "wallpaper", "set", path, "--monitor", monitorName];
        WallpaperEffects.prepare(path);
    }

    function applyAll(item) {
        if (root.busy) return;
        const path = item && item.path ? item.path : String(item || "");
        if (!path.length)
            return;
        root.busy = true;
        root.actionFailure = "";
        root.lastError = "";
        root.applySource = path;
        root.preparedCommand = [root.bin, "wallpaper", "set", path, "--all"];
        WallpaperEffects.prepare(path);
    }

    function runPreparedApply() {
        if (root.preparedCommand === null) return;
        actionProcess.command = root.preparedCommand;
        root.preparedCommand = null;
        root.applySource = "";
        actionProcess.running = true;
    }

    property var effectChanges: Connections {
        target: WallpaperEffects
        function onReady(source, maps) {
            if (root.preparing && source === root.applySource) root.runPreparedApply();
        }
        function onFailed(source, error) {
            if (!root.preparing || source !== root.applySource) return;
            console.warn("zestify: wallpaper maps unavailable:", error);
            // A helper failure must not stop a requested wallpaper change.
            root.runPreparedApply();
        }
    }

    function random(monitorName) {
        if (root.busy) return;
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
        onExited: (code, status) => {
            root.busy = false;
            const success = code === 0 && status === 0;
            root.actionFailure = actionError.text.trim() || (!success ? "Wallpaper action failed" : "");
            root.lastError = root.actionFailure;
            root.refresh();
            if (command[2] === "set" || command[2] === "random") {
                if (success) {
                    root.clearPreview();
                    root.applied();
                } else root.applyFailed();
            }
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
