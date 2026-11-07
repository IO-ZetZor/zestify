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
    readonly property var activeWorkspace: {
        const monitor = Hyprland.monitorFor(targetScreen);
        return monitor ? monitor.activeWorkspace : null;
    }
    readonly property bool fullscreenCover: BackgroundLib.isFullscreen(activeWorkspace)
    readonly property bool shouldDecode: !locked && dpmsOn && !batteryLow && !powerSaver
        && !(config && config.wallpaper.pauseOnFullscreen && fullscreenCover)

    property string proxyPath: ""
    property bool proxyFailed: false
    property string requestedSource: ""
    property int requestedWidth: 0
    property int requestedHeight: 0

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
        if (!ProxyLib.needsRequest(source, requestedSource, proxyPath, proxyFailed,
                requestedWidth, requestedHeight, width, height))
            return;
        requestedSource = source;
        requestedWidth = width;
        requestedHeight = height;
        proxyFailed = false;
        proxyPath = "";
        proxy.ensure(source, width, height);
    }

    onWidthChanged: ensureProxy()
    onHeightChanged: ensureProxy()

    onWallpaperPathChanged: {
        proxyPath = "";
        proxyFailed = false;
        requestedSource = "";
        requestedWidth = 0;
        requestedHeight = 0;
        ensureProxy();
    }

    Component.onCompleted: ensureProxy()

    Connections {
        target: root.proxy
        function onReady(source, path, width, height) {
            if (ProxyLib.accepts(source, path, width, height,
                    root.wallpaperPath, root.targetScreen.width, root.targetScreen.height)) {
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
