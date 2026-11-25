import QtQuick

QtObject {
    id: root

    property string task: ""
    property string mode: "countdown"
    property string status: "idle"
    property bool onBreak: false
    property bool muteNotifications: false
    property int durationMinutes: 25
    property double elapsedMs: 0
    property double accumulatedMs: 0
    property double startedAt: 0
    // Measure elapsed time, rather than counting timer callbacks. Hidden cards,
    // suspend and a busy event loop must not slow the countdown.
    property var clock: () => Date.now()

    readonly property bool active: status === "running" || status === "paused"
    readonly property bool suppressNotifications: active && !onBreak && muteNotifications
    readonly property double durationMs: (onBreak ? 5 : durationMinutes) * 60000
    readonly property double remainingMs: Math.max(0, durationMs - elapsedMs)
    readonly property real progress: mode === "stopwatch" && !onBreak ? 0
        : Math.min(1, elapsedMs / durationMs)
    readonly property string timeText: formatTime(mode === "stopwatch" && !onBreak
        ? Math.floor(elapsedMs / 1000) : Math.ceil(remainingMs / 1000))

    signal finished(bool wasBreak)
    signal taskSaved(string text)

    function formatTime(seconds) {
        const total = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(total / 60);
        const tail = String(total % 60).padStart(2, "0");
        return minutes < 60 ? String(minutes).padStart(2, "0") + ":" + tail
            : Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0") + ":" + tail;
    }

    function editTask(text) {
        const next = String(text).trim().slice(0, 200);
        if (!next.length)
            return false;
        task = next;
        taskSaved(next);
        return true;
    }

    function start(text, nextMode, minutes, quiet) {
        const duration = Number(minutes);
        if (active || ["countdown", "stopwatch"].indexOf(nextMode) < 0
                || !Number.isFinite(duration) || duration < 1 || duration > 240
                || !String(text).trim().length)
            return false;
        editTask(text);
        mode = nextMode;
        durationMinutes = Math.round(duration);
        onBreak = false;
        muteNotifications = !!quiet;
        begin();
        return true;
    }

    function begin() {
        elapsedMs = 0;
        accumulatedMs = 0;
        startedAt = clock();
        status = "running";
    }

    function update() {
        if (status !== "running")
            return;
        elapsedMs = accumulatedMs + Math.max(0, clock() - startedAt);
        if ((mode === "countdown" || onBreak) && elapsedMs >= durationMs) {
            elapsedMs = durationMs;
            status = "finished";
            finished(onBreak);
        }
    }

    function pause() {
        update();
        if (status !== "running")
            return;
        accumulatedMs = elapsedMs;
        status = "paused";
    }

    function resume() {
        if (status !== "paused")
            return;
        startedAt = clock();
        status = "running";
    }

    function end() {
        status = "idle";
        onBreak = false;
        muteNotifications = false;
        elapsedMs = 0;
        accumulatedMs = 0;
    }

    function takeBreak() {
        if (status !== "finished" || onBreak)
            return;
        onBreak = true;
        begin();
    }

    function keepGoing() {
        if (status !== "finished")
            return;
        onBreak = false;
        begin();
    }

    readonly property Timer ticker: Timer {
        interval: 200
        running: root.status === "running"
        repeat: true
        onTriggered: root.update()
    }
}
