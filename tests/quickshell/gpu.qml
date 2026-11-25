import QtQuick
import Quickshell
import "../../shell/singletons"

ShellRoot {
    id: root
    property int phase: -1
    property int ticks: 0
    property bool unavailable: Quickshell.env("GPU_FAILURE_TEST") === "1"
    QtObject { id: secondConsumer }

    Component.onCompleted: {
        Stats.interval = 100;
        Stats.start();
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            root.ticks++;
            try {
                if (root.ticks > 40)
                    throw new Error("GPU process did not respond");
                if (root.phase === -1) {
                    if (Stats._gpuStarted || Stats.gpuConsumers.length)
                        throw new Error("Idle Stats started an unused GPU helper");
                    if (root.ticks < 3)
                        return;
                    if (!Stats.historyCpu.length)
                        throw new Error("CPU sampling stopped with GPU sampling");
                    Stats.setGpuConsumer(root, true);
                    Stats.setGpuConsumer(root, true);
                    Stats.setGpuConsumer(secondConsumer, true);
                    Stats.setGpuConsumer(root, false);
                    if (Stats.gpuConsumers.length !== 1)
                        throw new Error("GPU subscribers were not deduplicated");
                    root.phase = 0;
                } else if (root.unavailable) {
                    if (Stats.gpuStatus !== "GPU telemetry unavailable")
                        return;
                    if (Stats.gpuDevices.length !== 0)
                        throw new Error("Failed helper left stale GPU data");
                    Stats.stop();
                    console.log("GPU PASS: failed helper reports unavailable");
                    Qt.quit();
                } else if (root.phase === 0) {
                    if (Stats.gpuDevices.length !== 2 || Stats.gpuDevices[0].history.length < 3)
                        return;
                    if (Stats.gpuDevices[0].history[1] !== 20 || Stats.gpuDevices[1].history[1] !== 40)
                        throw new Error("Collector did not retain per-device histories");
                    Stats.stop();
                    root.phase = 1;
                } else if (root.phase === 1) {
                    if (Stats._gpuStarted)
                        return;
                    Stats.interval = 200;
                    Stats.start();
                    root.phase = 2;
                } else if (root.phase === 2) {
                    if (Stats.gpuDevices.length !== 2 || Stats.gpuDevices[0].history.length < 2)
                        return;
                    const devices = Stats.gpuDevices;
                    Stats._onGpus(JSON.stringify([Object.assign({}, devices[1], {utilization: 77}),
                        Object.assign({}, devices[0], {utilization: null})]));
                    if (Stats.gpuDevices[0].history.slice(-1)[0] !== 77 || Stats.gpuDevices[1].history.length !== 0)
                        throw new Error("Reordered/unavailable GPU history did not update");
                    Stats._onGpus("invalid JSON");
                    if (Stats.gpuDevices.length || Stats.gpuStatus !== "GPU telemetry unavailable")
                        throw new Error("Invalid GPU sample left stale data");
                    Stats.setGpuConsumer(secondConsumer, false);
                    root.phase = 3;
                } else {
                    if (Stats._gpuStarted)
                        return;
                    if (!Stats.running || Stats.gpuConsumers.length || Stats.gpuDevices.length)
                        throw new Error("GPU unsubscribe did not stop/clear only GPU work");
                    if (Stats.gpuStatus !== "GPU sampling paused")
                        throw new Error("Stopped GPU helper was not marked paused");
                    Stats._onGpus('[{"id":"late","utilization":50}]');
                    if (Stats.gpuDevices.length)
                        throw new Error("Late GPU response restored stale data");
                    Stats.stop();
                    console.log("GPU PASS: on-demand subscribers, collector polling, histories, stop/restart and interval changes");
                    Qt.quit();
                }
            } catch (error) {
                console.error("GPU FAIL: " + error);
                Qt.quit();
            }
        }
    }
}
