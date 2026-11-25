pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Fast cache lookups never queue behind AI inference. Missing masks warm on a
// separate, single worker; a nearly completed mask gets at most two seconds.
Singleton {
    id: root
    readonly property string bin: Quickshell.env("ZESTI_BIN") || Quickshell.env("ZESTIFY_BIN") || "zesti"
    readonly property int outlineBudget: 2000
    readonly property var fallbackMaps: ({ok: true, kind: "contagio", fallback: true,
        field: String(Qt.resolvedUrl("../assets/wallpaper-colony-field.png")),
        line: String(Qt.resolvedUrl("../assets/wallpaper-colony-line.png"))})
    property var cache: ({})
    property var recent: ({})
    property var requests: ({})
    property var queue: []
    property string pendingWarm: ""
    property string source: ""
    property bool busy: false
    property bool started: false
    property bool timedOut: false
    property int generation: 0
    property int workerGeneration: 0
    property bool warming: false
    property bool warmStarted: false
    property bool warmTimedOut: false
    property string warmSource: ""
    property int warmGeneration: 0
    property double warmStartTime: 0
    property double lastWarmMs: 0
    signal ready(string source, var maps)
    signal failed(string source, string error)

    function invalidate() {
        generation++;
        cache = ({});
        recent = ({});
        for (const path of Object.keys(requests)) settle(path, fallbackMaps);
    }
    function remember(path, maps, gen) {
        if (gen !== generation || maps.error) return;
        if (maps.kind !== "perfil" && !(maps.cached || maps.reason === "No clear subject")) return;
        const updated = Object.assign({}, cache);
        if (Object.keys(updated).length >= 16) delete updated[Object.keys(updated)[0]];
        updated[path] = maps;
        cache = updated;
    }
    function settle(path, maps) {
        const request = requests[path];
        if (!request) return;
        const pending = Object.assign({}, requests);
        delete pending[path];
        requests = pending;
        queue = queue.filter(value => value !== path);
        remember(path, maps, request.generation);
        // Reuse the same maps when the committed background asks immediately
        // after Apply. This avoids a second lookup/wait during the transition.
        const results = Object.assign({}, recent);
        for (const key of Object.keys(results))
            if (results[key].expires < Date.now()) delete results[key];
        if (Object.keys(results).length >= 16) delete results[Object.keys(results)[0]];
        if (request.generation === generation && !maps.error)
            results[path] = {maps: maps, expires: Date.now() + 5000};
        recent = results;
        root.ready(path, maps);
    }
    function prepare(path) {
        if (!path) { root.failed(path, "No wallpaper source"); return; }
        const maps = cache[path] || (recent[path] && recent[path].expires > Date.now() ? recent[path].maps : null);
        if (maps) {
            const gen = generation;
            Qt.callLater(() => { if (gen === generation) root.ready(path, maps); else root.prepare(path); });
            return;
        }
        if (requests[path]) return;
        const pending = Object.assign({}, requests);
        pending[path] = {deadline: Date.now() + outlineBudget, generation: generation, candidate: fallbackMaps};
        requests = pending;
        const dropped = queue.slice(0, Math.max(0, queue.length - 7));
        queue = queue.slice(-7).concat([path]);
        for (const old of dropped) settle(old, fallbackMaps);
        Qt.callLater(root.next);
    }
    function warm(path) {
        if (!path || cache[path] || (warming && warmSource === path)) return;
        pendingWarm = path;
        warmDelay.restart();
    }
    function next() {
        if (!busy && queue.length) {
            source = queue[0];
            queue = queue.slice(1);
            busy = true;
            started = false;
            timedOut = false;
            workerGeneration = generation;
            worker.command = [bin, "wallpaper", "effects", "prepare", "--source", source, "--no-inference"];
            worker.running = true;
            watchdog.restart();
        }
        nextWarm();
    }
    function nextWarm() {
        if (warming || warmDelay.running || !pendingWarm) return;
        const path = pendingWarm;
        pendingWarm = "";
        if (cache[path]) return;
        warmSource = path;
        warmGeneration = generation;
        warming = true;
        warmStarted = false;
        warmTimedOut = false;
        warmStartTime = Date.now();
        warmWorker.command = [bin, "wallpaper", "effects", "prepare", "--source", path];
        warmWorker.running = true;
        warmWatchdog.restart();
    }
    function decode(text) {
        const maps = JSON.parse(text);
        if (!maps.ok || !["perfil", "contagio"].includes(maps.kind) || !maps.field || !maps.line)
            throw new Error(maps.error || "Invalid transition maps");
        return maps;
    }
    function complete(maps, error) {
        watchdog.stop();
        const path = source;
        source = "";
        busy = false;
        if (maps) remember(path, maps, workerGeneration);
        if (maps && workerGeneration === generation && maps.kind === "contagio" && !maps.cached && !maps.error)
            warm(path);
        if (requests[path] && requests[path].generation === workerGeneration) {
            const candidate = maps || Object.assign({}, fallbackMaps, {error: error});
            requests[path].candidate = candidate;
            const remaining = lastWarmMs - (Date.now() - warmStartTime);
            const nearReady = maps && maps.kind === "contagio" && !maps.cached && !maps.error
                && warming && warmSource === path && warmGeneration === generation
                && lastWarmMs > 0 && remaining > 0 && remaining <= outlineBudget;
            if (!nearReady) settle(path, candidate);
        }
        Qt.callLater(root.next);
    }
    function completeWarm(maps, error) {
        warmWatchdog.stop();
        const path = warmSource;
        const gen = warmGeneration;
        if (maps && !maps.cached && !maps.error) lastWarmMs = Date.now() - warmStartTime;
        warmSource = "";
        warming = false;
        if (maps) remember(path, maps, gen);
        if (requests[path] && requests[path].generation === gen)
            settle(path, maps || requests[path].candidate);
        if (error) console.warn("zestify: background wallpaper mask:", error);
        Qt.callLater(root.nextWarm);
    }
    property var deadline: Timer {
        interval: 20
        repeat: true
        running: Object.keys(root.requests).length > 0
        onTriggered: {
            for (const path of Object.keys(root.requests))
                if (root.requests[path].deadline <= Date.now()) root.settle(path, root.requests[path].candidate);
        }
    }
    property var warmDelay: Timer { interval: 250; onTriggered: root.nextWarm() }
    property var watchdog: Timer {
        interval: 5000
        onTriggered: { root.timedOut = true; if (worker.running) worker.running = false; else root.complete(null, "Cache lookup timed out"); }
    }
    property var warmWatchdog: Timer {
        interval: 90000
        onTriggered: { root.warmTimedOut = true; if (warmWorker.running) warmWorker.running = false; else root.completeWarm(null, "Mask preparation timed out"); }
    }
    property var worker: Process {
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: failure }
        onStarted: root.started = true
        onRunningChanged: if (!running && root.busy && !root.started) Qt.callLater(() => {
            if (root.busy && !worker.running && !root.started) root.complete(null, "Could not start wallpaper cache helper");
        })
        onExited: (code, status) => {
            if (root.timedOut || code !== 0 || status !== 0) { root.complete(null, failure.text.trim() || "Cache lookup failed"); return; }
            try { root.complete(root.decode(output.text), ""); }
            catch (error) { root.complete(null, error.message); }
        }
    }
    property var warmWorker: Process {
        stdout: StdioCollector { id: warmOutput }
        stderr: StdioCollector { id: warmFailure }
        onStarted: root.warmStarted = true
        onRunningChanged: if (!running && root.warming && !root.warmStarted) Qt.callLater(() => {
            if (root.warming && !warmWorker.running && !root.warmStarted) root.completeWarm(null, "Could not start wallpaper mask helper");
        })
        onExited: (code, status) => {
            if (root.warmTimedOut || code !== 0 || status !== 0) { root.completeWarm(null, warmFailure.text.trim() || "Mask preparation failed"); return; }
            try { root.completeWarm(root.decode(warmOutput.text), ""); }
            catch (error) { root.completeWarm(null, error.message); }
        }
    }
}
