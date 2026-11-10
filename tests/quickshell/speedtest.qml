import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/surfaces"
import "../../shell/singletons"

ShellRoot {
    id: root
    property int phase: 0
    property int ticks: 0
    property bool failure: Quickshell.env("SPEEDTEST_FAILURE") === "1"
    Theme { id: theme }

    Window {
        id: window
        visible: true
        width: 620
        height: 560
        color: theme.surface
        NetworkSurface {
            id: network
            anchors.fill: parent
            theme: theme
        }
    }
    SystemSurface {
        id: system
        width: 820
        height: 690
        visible: false
        sampling: false
        theme: theme
    }

    function find(item, predicate) {
        if (predicate(item))
            return item;
        for (const child of item.children || []) {
            const found = root.find(child, predicate);
            if (found)
                return found;
        }
        return null;
    }

    function text(item, value) { return root.find(item, child => child.text === value) !== null; }

    function click(item) {
        const button = root.find(item, child => child.objectName === "speedTestButton");
        const mouse = button && root.find(button, child => typeof child.clicked === "function");
        if (!mouse)
            throw new Error("Speed test button did not load");
        mouse.clicked(null);
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            try {
                if (++root.ticks > 180)
                    throw new Error("Speed test state did not advance");
                if (root.phase === 0) {
                    if (SpeedTest.busy || SpeedTest.state !== "idle")
                        throw new Error("Speed test ran automatically");
                    root.click(network);
                    SpeedTest.start(); // A second request must not start another process.
                    root.phase = 1;
                } else if (root.failure) {
                    if (SpeedTest.state !== "error" || SpeedTest.busy)
                        return;
                    console.log("SPEEDTEST PASS: failed helper reports an error");
                    Qt.quit();
                } else if (root.phase === 1) {
                    if (SpeedTest.state !== "done" || SpeedTest.busy)
                        return;
                    for (const surface of [network, system]) {
                        if (!root.text(surface, "123.4 Mbps") || !root.text(surface, "56.7 Mbps")
                                || !root.text(surface, "12.3 ms") || !root.text(surface, "Test again"))
                            throw new Error("Shared speed test results did not render");
                    }
                    root.phase = 2;
                    network.grabToImage(result => {
                        result.saveToFile(Quickshell.env("SPEEDTEST_PREVIEW"));
                        root.click(network);
                        root.phase = 3;
                    });
                } else if (root.phase === 3) {
                    // Wait for helper output before cancelling, so this test
                    // also covers slower process startup under the full suite.
                    if (SpeedTest.state === "latency")
                        return;
                    if (!SpeedTest.busy || !root.text(system, "Cancel"))
                        throw new Error("Active speed test cannot be cancelled from System");
                    root.click(system);
                    SpeedTest.receive('{"type":"result","download":999,"upload":999,"latency":999}');
                    if (SpeedTest.state !== "cancelled" || SpeedTest.download === 999)
                        throw new Error("Cancelled test accepted a late result");
                    root.phase = 4;
                } else if (root.phase === 4) {
                    if (SpeedTest.busy)
                        return;
                    root.click(system);
                    root.phase = 5;
                } else if (root.phase === 5) {
                    if (SpeedTest.state !== "error" || SpeedTest.busy)
                        return;
                    if (!root.text(network, "Server unavailable. Try again."))
                        throw new Error("Speed test error did not render");
                    root.click(network);
                    root.phase = 6;
                } else if (root.phase === 6) {
                    if (SpeedTest.state !== "done" || SpeedTest.busy)
                        return;
                    console.log("SPEEDTEST PASS: on-demand start, shared results, cancellation, errors and retry");
                    Qt.quit();
                }
            } catch (error) {
                console.error("SPEEDTEST FAIL: " + error);
                SpeedTest.cancel();
                Qt.quit();
            }
        }
    }
}
