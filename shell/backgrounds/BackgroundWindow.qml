import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../lib/wallpapers.js" as WallpapersLib
import "../lib/proxy.js" as ProxyLib
import "../lib/background.js" as BackgroundLib
import "."

PanelWindow {
    id: root

    property var targetScreen: null
    property string wallpaperPath: ""
    property var config
    property var proxy
    property bool locked: false
    property bool dpmsOn: true
    property bool batteryLow: false
    property bool powerSaver: false

    readonly property bool isVideo: WallpapersLib.isVideoPath(wallpaperPath)
    readonly property bool proxyEnabled: config ? config.wallpaper.proxy.enabled : true
    readonly property var monitor: Hyprland.monitorFor(targetScreen)
    readonly property var activeWorkspace: monitor ? monitor.activeWorkspace : null
    readonly property bool monitorFocused: monitor ? monitor.focused : true
    readonly property bool fullscreenCover: BackgroundLib.isFullscreen(activeWorkspace)
    readonly property bool anyWindow: {
        const workspace = root.activeWorkspace;
        const model = workspace ? workspace.toplevels : null;
        const values = model ? model.values : null;
        return !!(values && values.length > 0);
    }
    readonly property bool obscured: {
        if (!root.config)
            return false;
        return BackgroundLib.shouldPauseForObscured(
            root.config.wallpaper.pauseWhenObscured,
            root.config.wallpaper.pauseOnFullscreen && root.fullscreenCover,
            root.anyWindow);
    }
    property bool unfocusedPaused: false
    readonly property bool shouldDecode: !locked && dpmsOn && !batteryLow && !powerSaver
        && !obscured && !unfocusedPaused

    property string proxyPath: ""
    property bool proxyFailed: false
    property string requestedSource: ""
    property int requestedWidth: 0
    property int requestedHeight: 0
    property string requestedCodec: ""
    property int requestedCrf: -1

    screen: targetScreen
    color: "black"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "zestify-background"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function ensureProxy() {
        const source = wallpaperPath;
        const width = targetScreen ? targetScreen.width : 0;
        const height = targetScreen ? targetScreen.height : 0;
        if (!WallpapersLib.isVideoPath(source) || !proxy || !proxyEnabled || proxy.busy)
            return;
        if (width <= 0 || height <= 0)
            return;
        const settings = root.config ? root.config.wallpaper.proxy : null;
        const target = ProxyLib.resolutionSize(settings ? settings.resolution : "monitor", width, height);
        const codec = settings ? settings.codec : "h264";
        const crf = settings ? settings.crf : 20;
        if (target.width <= 0 || target.height <= 0)
            return;
        const settingsChanged = root.requestedCodec !== codec || root.requestedCrf !== crf;
        if (!settingsChanged && !ProxyLib.needsRequest(source, requestedSource, proxyPath, proxyFailed,
                requestedWidth, requestedHeight, target.width, target.height))
            return;
        requestedSource = source;
        requestedWidth = target.width;
        requestedHeight = target.height;
        requestedCodec = codec;
        requestedCrf = crf;
        proxyFailed = false;
        proxyPath = "";
        proxy.ensure(source, target.width, target.height, codec, crf);
    }

    function resetProxy() {
        proxyPath = "";
        proxyFailed = false;
        requestedSource = "";
        requestedWidth = 0;
        requestedHeight = 0;
        requestedCodec = "";
        requestedCrf = -1;
        ensureProxy();
    }

    onWidthChanged: ensureProxy()
    onHeightChanged: ensureProxy()

    onWallpaperPathChanged: resetProxy()

    onMonitorFocusedChanged: {
        if (monitorFocused)
            unfocusedPaused = false;
    }

    Component.onCompleted: ensureProxy()

    Timer {
        id: unfocusedTimer

        interval: root.config ? Math.max(0, root.config.wallpaper.pauseUnfocusedAfter) * 1000 : 0
        repeat: true
        running: interval > 0 && root.monitor !== null && !root.monitorFocused
        onTriggered: root.unfocusedPaused = true
        onRunningChanged: {
            if (!running)
                root.unfocusedPaused = false;
        }
        onIntervalChanged: root.unfocusedPaused = false
    }

    Connections {
        target: root.proxy
        function onReady(source, path, width, height) {
            if (ProxyLib.accepts(source, path, width, height,
                    root.wallpaperPath, root.requestedWidth, root.requestedHeight)) {
                root.proxyPath = path;
                root.proxyFailed = false;
            }
        }
        function onFailed(source, error) {
            if (source === root.wallpaperPath) {
                root.proxyFailed = true;
                if (error !== "proxy busy")
                    console.warn("zestify: wallpaper proxy failed:", error);
            }
        }
        function onBusyChanged() {
            if (!root.proxy.busy)
                root.ensureProxy();
        }
    }

    Connections {
        target: root.config ? root.config.wallpaper.proxy : null

        function onEnabledChanged() { root.resetProxy(); }
        function onResolutionChanged() { root.resetProxy(); }
        function onCodecChanged() { root.resetProxy(); }
        function onCrfChanged() { root.resetProxy(); }
    }

    WallpaperImage {
        anchors.fill: parent
        path: root.wallpaperPath
        visible: !root.isVideo
    }

    VideoWallpaper {
        anchors.fill: parent
        visible: root.isVideo
        source: WallpapersLib.videoSource(root.isVideo, root.proxyPath, root.wallpaperPath)
        playing: root.isVideo
        shouldDecode: root.isVideo && root.shouldDecode
        muted: root.config ? root.config.wallpaper.muted : true
    }
}
