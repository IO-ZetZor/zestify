pragma ComponentBehavior: Bound

import QtQuick
import "../lib/wallpapers.js" as WallpapersLib
import "."

Item {
    id: root
    objectName: "wallpaperTransition"
    property var item: null
    property bool active: true
    property bool shouldDecode: true
    property bool muted: true
    property var motion
    property var effects: null
    property color ink: "white"
    property color ember: "orange"
    property bool initialized: false
    property var displayedLayer: null
    property var incomingLayer: null
    property var maps: null
    property string mapSource: ""
    property bool mapFailed: false
    property bool simpleFade: false
    property real progress: 0
    property real seed: 0
    // Negative uses the reference scene timings; tests can override the duration.
    property int duration: -1
    readonly property bool transitioning: reveal.running
    readonly property bool mapsReady: maps !== null && fieldImage.status === Image.Ready && lineImage.status === Image.Ready
    readonly property var currentFrame: incomingLayer && incomingLayer.ready
        ? incomingLayer.frame : (displayedLayer ? displayedLayer.frame : null)
    readonly property VideoWallpaper video: currentFrame ? currentFrame.video : null
    readonly property var image: currentFrame ? currentFrame.image : null
    visible: active && (displayedLayer !== null || incomingLayer !== null)

    function sameItem(a, b) {
        return a && b && a.path === b.path && a.thumb === b.thumb;
    }
    function reset() {
        reveal.stop();
        displayedLayer = null;
        incomingLayer = null;
        first.wallpaper = null;
        second.wallpaper = null;
        maps = null;
        mapSource = "";
        mapFailed = false;
        progress = 0;
    }
    function finish() {
        const outgoing = displayedLayer;
        displayedLayer = incomingLayer;
        incomingLayer = null;
        if (outgoing) outgoing.wallpaper = null;
        maps = null;
        mapSource = "";
        progress = 0;
        Qt.callLater(root.update);
    }
    function update() {
        if (!initialized) return;
        if (!active || !item) { reset(); return; }
        if (reveal.running) return;
        if (displayedLayer && sameItem(displayedLayer.wallpaper, item)) {
            if (incomingLayer) incomingLayer.wallpaper = null;
            incomingLayer = null;
            maps = null;
            mapSource = "";
            return;
        }
        if (!incomingLayer) incomingLayer = displayedLayer === first ? second : first;
        incomingLayer.wallpaper = item;
        if (displayedLayer && !(motion && motion.calm)) {
            const path = item.mapSource || item.thumb || item.path;
            if (path !== mapSource) {
                mapSource = path;
                maps = null;
                mapFailed = false;
                if (effects) effects.prepare(path);
                else mapFailed = true;
            }
        }
        Qt.callLater(root.tryTransition);
    }
    function tryTransition() {
        if (!active || reveal.running || !incomingLayer || !incomingLayer.ready
                || !sameItem(incomingLayer.wallpaper, item)) return;
        if (!displayedLayer || (motion && motion.calm)) { finish(); return; }
        if (!mapsReady && !mapFailed) return;
        simpleFade = mapFailed;
        seed = Math.random() * 100;
        progress = 0;
        reveal.start();
    }
    function mapLoadChanged() {
        if (maps && (fieldImage.status === Image.Error || lineImage.status === Image.Error)) {
            console.warn("zestify: transition maps could not load; using a fade");
            mapFailed = true;
        }
        Qt.callLater(root.tryTransition);
    }
    Connections {
        target: root.effects
        function onReady(source, maps) {
            if (source !== root.mapSource || root.transitioning || !root.incomingLayer) return;
            root.maps = maps;
            Qt.callLater(root.tryTransition);
        }
        function onFailed(source, error) {
            if (source !== root.mapSource || root.transitioning || !root.incomingLayer) return;
            console.warn("zestify: wallpaper transition:", error);
            root.mapFailed = true;
            Qt.callLater(root.tryTransition);
        }
    }
    Image {
        id: fieldImage
        visible: false
        asynchronous: true
        source: root.maps ? WallpapersLib.localUrl(root.maps.field) : ""
        smooth: root.maps !== null && root.maps.kind === "perfil"
        onStatusChanged: root.mapLoadChanged()
    }
    Image {
        id: lineImage
        visible: false
        asynchronous: true
        source: root.maps ? WallpapersLib.localUrl(root.maps.line) : ""
        smooth: false
        onStatusChanged: root.mapLoadChanged()
    }
    component SceneLayer: Item {
        id: sceneLayer
        property var wallpaper: null
        readonly property WallpaperPreviewFrame frame: loader.item as WallpaperPreviewFrame
        readonly property bool ready: frame !== null && frame.ready
        visible: sceneLayer === root.displayedLayer || root.transitioning
        z: root.simpleFade && sceneLayer === root.incomingLayer ? 1 : 0
        opacity: root.transitioning && root.simpleFade && sceneLayer === root.incomingLayer ? root.progress : 1
        onReadyChanged: Qt.callLater(root.tryTransition)
        Loader {
            id: loader
            anchors.fill: parent
            active: root.active && sceneLayer.wallpaper !== null
            sourceComponent: WallpaperPreviewFrame { item: sceneLayer.wallpaper }
        }
        Binding {
            target: sceneLayer.frame ? sceneLayer.frame.video : null
            property: "shouldDecode"
            value: root.shouldDecode && (sceneLayer === root.displayedLayer || root.transitioning)
            when: target !== null
        }
        Binding {
            target: sceneLayer.frame ? sceneLayer.frame.video : null
            property: "muted"
            value: root.muted || sceneLayer !== root.displayedLayer
            when: target !== null
        }
    }
    SceneLayer { id: first; anchors.fill: parent }
    SceneLayer { id: second; anchors.fill: parent }

    // Capture only during the scene change. Maps use the original image's
    // coordinates; native image/video textures already cover the output.
    Loader {
        anchors.fill: parent
        active: root.transitioning && !root.simpleFade
        sourceComponent: Item {
            ShaderEffectSource { id: firstTexture; sourceItem: first; hideSource: true; live: true; visible: false }
            ShaderEffectSource { id: secondTexture; sourceItem: second; hideSource: true; live: true; visible: false }
            ShaderEffect {
                objectName: "wallpaperTransitionEffect"
                anchors.fill: parent
                property var oldTex: root.displayedLayer === first ? firstTexture : secondTexture
                property var newTex: root.incomingLayer === first ? firstTexture : secondTexture
                property var fieldTex: fieldImage
                property var lineTex: lineImage
                property real t: root.progress
                property real mode: root.maps && root.maps.kind === "perfil" ? 1 : 0
                property real sw: root.width
                property real sh: root.height
                property real fw: Math.max(1, fieldImage.implicitWidth)
                property real fh: Math.max(1, fieldImage.implicitHeight)
                property real lw: Math.max(1, lineImage.implicitWidth)
                property real lh: Math.max(1, lineImage.implicitHeight)
                property real glow: 0.9
                property real lineW: 1.5
                property real sdRange: 16
                property real seed: root.seed
                property color ember: root.ember
                property color ink: root.ink
                property vector4d cropOld: Qt.vector4d(0, 0, 1, 1)
                property vector4d cropNew: {
                    if (!root.maps || root.maps.kind !== "perfil") return Qt.vector4d(0, 0, 1, 1);
                    const w = Math.max(1, fieldImage.implicitWidth), h = Math.max(1, fieldImage.implicitHeight);
                    const scale = Math.max(root.width / w, root.height / h);
                    const cw = root.width / (w * scale), ch = root.height / (h * scale);
                    return Qt.vector4d((1 - cw) / 2, (1 - ch) / 2, cw, ch);
                }
                fragmentShader: "../shaders/wallpaper-transition-v15.frag.qsb"
            }
        }
    }
    NumberAnimation {
        id: reveal
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.duration >= 0 ? root.duration : root.simpleFade ? 300
            : root.maps && root.maps.kind === "perfil" ? 2000 : 1800
        easing.type: Easing.Linear
        onFinished: root.finish()
    }
    onItemChanged: update()
    onActiveChanged: update()
    Component.onCompleted: { initialized = true; update(); }
}
