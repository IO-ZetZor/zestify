import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/backgrounds"
import "../../shell/surfaces"

ShellRoot {
    id: root
    property int phase: 0
    property int audioChanges: 0
    property int settledChanges: 0
    readonly property string imagePath: Quickshell.env("REVIEW_WALLPAPER")

    Theme { id: fixtureTheme }
    QtObject {
        id: wifiA
        property bool scannerEnabled: false
        property var networks: ({values: []})
        property string address: ""
    }
    QtObject {
        id: wifiB
        property bool scannerEnabled: false
        property var networks: ({values: []})
        property string address: ""
    }
    QtObject {
        id: borrowedWifi
        property bool scannerEnabled: true
        property var networks: ({values: []})
        property string address: ""
    }
    QtObject {
        id: bluetoothA
        property bool discovering: false
        property bool enabled: true
        property var devices: ({values: []})
    }
    QtObject {
        id: bluetoothB
        property bool discovering: false
        property bool enabled: true
        property var devices: ({values: []})
    }
    QtObject {
        id: borrowedBluetooth
        property bool discovering: true
        property bool enabled: true
        property var devices: ({values: []})
    }
    QtObject {
        id: proxyConfig
        property bool enabled: true
        property string resolution: "monitor"
        property string codec: "h264"
        property int crf: 20
        property int maxFps: 24
    }
    QtObject {
        id: wallpaperConfig
        property var proxy: proxyConfig
        property string pauseWhenObscured: "never"
        property bool pauseOnFullscreen: false
        property int pauseUnfocusedAfter: 0
        property bool muted: true
    }
    QtObject {
        id: fixtureConfig
        property var wallpaper: wallpaperConfig
    }
    QtObject {
        id: fakeProxy
        property bool busy: false
        property int requests: 0
        property int lastMaxFps: 0
        signal ready(string source, string path, int width, int height)
        signal failed(string source, string error)
        function ensure(source, width, height, codec, crf, maxFps) {
            root.check(!busy, "Proxy requests overlapped");
            requests++;
            lastMaxFps = maxFps;
            busy = true;
            Qt.callLater(function() {
                fakeProxy.failed(source, "intentional regression failure");
                fakeProxy.busy = false;
            });
        }
    }

    BackgroundWindow {
        id: background
        visible: false
        targetScreen: Quickshell.screens[0] || null
        config: fixtureConfig
        proxy: fakeProxy
    }
    FloatingWindow {
        visible: true
        implicitWidth: 900
        implicitHeight: 700
        color: "#262331"
        NetworkSurface {
            id: network
            width: 430
            height: 500
            theme: fixtureTheme
            wifiDevice: wifiA
        }
        BluetoothSurface {
            id: bluetooth
            x: 450
            width: 430
            height: 500
            theme: fixtureTheme
            adapter: bluetoothA
        }
        WallpaperImage {
            id: image
            width: 64
            height: 64
            y: 550
            path: root.imagePath
        }
        VisualiserLevels {
            id: audio
            active: false
            scriptsDir: ""
        }
    }
    Connections {
        target: audio
        function onValuesChanged() { root.audioChanges++; }
    }

    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    function run() {
        try {
            if (phase === 0) {
                check(Quickshell.screens.length > 0, "Offscreen screen is unavailable");
                check(wifiA.scannerEnabled && bluetoothA.discovering, "Initial adapter scanning did not start");
                network.pendingNetwork = {};
                network.password = "discard on device change";
                network.wifiDevice = wifiB;
                bluetooth.adapter = bluetoothB;
                check(!wifiA.scannerEnabled && wifiB.scannerEnabled, "Wi-Fi scanner ownership did not transfer");
                check(!bluetoothA.discovering && bluetoothB.discovering, "Bluetooth discovery ownership did not transfer");
                check(network.pendingNetwork === null && network.password === "", "Device replacement retained a stale password prompt");
                network.wifiDevice = borrowedWifi;
                bluetooth.adapter = borrowedBluetooth;
                check(!wifiB.scannerEnabled && !bluetoothB.discovering, "Replaced owned scanners remained enabled");
                network.wifiDevice = null;
                bluetooth.adapter = null;
                check(borrowedWifi.scannerEnabled && borrowedBluetooth.discovering, "Borrowed discovery was stopped");
                check(image.status === Image.Ready, "Wallpaper with URL delimiters failed to load");
                audio.cavaActive = true;
                audio.rawLevels = Array(32).fill(0.4);
                audio.active = true;
                background.wallpaperPath = "/tmp/review-invalid-first.mp4";
                check(fakeProxy.requests === 1, "Initial proxy request did not start");
                check(fakeProxy.lastMaxFps === 24, "Default proxy frame limit was not forwarded");
                check(!background.shouldDecode, "Full-rate decoding continued while proxy generation was pending");
            } else if (phase === 2) {
                check(fakeProxy.requests === 1, "Failed proxy retried immediately after busy=false");
                background.wallpaperPath = "/tmp/review-invalid-second.mp4";
                check(fakeProxy.requests === 2, "Changed source did not clear proxy backoff");
            } else if (phase === 4) {
                check(fakeProxy.requests === 2, "Changed source bypassed retry backoff");
                proxyConfig.crf = 21;
                check(fakeProxy.requests === 3, "Changed configuration did not clear proxy backoff");
            } else if (phase === 6) {
                proxyConfig.maxFps = 15;
                check(fakeProxy.requests === 4 && fakeProxy.lastMaxFps === 15,
                    "Changed frame limit did not regenerate the proxy");
            } else if (phase === 14) {
                check(audio.settled, "Constant visualiser input did not settle");
                check(audio.values.length === 32 && Math.abs(audio.values[0] - 0.4) < 0.001,
                    "Visualiser did not converge to its target");
                settledChanges = audioChanges;
            } else if (phase === 18) {
                check(audioChanges === settledChanges, "Settled visualiser kept publishing frames");
                audio.rawLevels = Array(32).fill(0.4);
            } else if (phase === 20) {
                check(audioChanges === settledChanges, "Identical input restarted visualiser animation");
                audio.rawLevels = Array(32).fill(0.8);
            } else if (phase === 22) {
                check(audioChanges > settledChanges && audio.values[0] > 0.4,
                    "Changed input did not wake visualiser animation");
                check(fakeProxy.requests === 4, "Proxy failure bypassed bounded backoff");
                audio.active = false;
                check(audio.values.length === 0 && audio.settled, "Deactivation did not release visualiser state");
            } else if (phase === 60) {
                check(fakeProxy.requests === 5, "Proxy did not retry after its backoff expired");
                check(background.proxyRetryDelay === 10000, "Repeated proxy failure did not increase backoff");
                fakeProxy.ready(background.wallpaperPath, "/tmp/review-ready.mp4",
                    background.requestedWidth, background.requestedHeight);
                check(background.proxyPath === "/tmp/review-ready.mp4" && background.shouldDecode,
                    "Optimized proxy did not resume decoding");
                const savedPath = background.renderedPath;
                const savedPlaybackSource = background.renderedItem.path;
                background.holdChanges = true;
                background.wallpaperPath = root.imagePath;
                check(background.renderedPath === savedPath,
                    "Applying changed the desktop behind the open picker");
                check(background.renderedItem.path === savedPlaybackSource,
                    "Applying replaced the held optimized video source");
                background.holdChanges = false;
                check(background.renderedPath === root.imagePath,
                    "Closing the picker did not release the committed wallpaper");
                console.log("REVIEW SURFACES PASS: adapter ownership, proxy backoff, URL paths, visualiser quiescence");
                Qt.quit();
                return;
            }
            phase++;
        } catch (error) {
            console.error("REVIEW SURFACES FAIL:", error);
            Qt.exit(1);
        }
    }
    Timer { interval: 100; running: true; repeat: true; onTriggered: root.run() }
}
