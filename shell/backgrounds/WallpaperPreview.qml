pragma ComponentBehavior: Bound

import QtQuick
import "."

Item {
    id: root

    property var item: null
    property bool active: true
    property var motion
    property bool initialized: false
    property var displayedLayer: null
    property var incomingLayer: null
    readonly property bool transitioning: fade.running
    readonly property var currentFrame: incomingLayer ? incomingLayer.frame
        : (displayedLayer ? displayedLayer.frame : null)
    readonly property VideoWallpaper video: currentFrame ? currentFrame.video : null
    readonly property var image: currentFrame ? currentFrame.image : null
    visible: active && (displayedLayer !== null || incomingLayer !== null)

    function sameItem(a, b) {
        return a && b && a.path === b.path && a.thumb === b.thumb;
    }

    function reset() {
        fade.stop();
        incomingLayer = null;
        displayedLayer = null;
        first.wallpaper = null;
        second.wallpaper = null;
        first.opacity = 0;
        second.opacity = 0;
    }

    function update() {
        if (!initialized)
            return;
        if (!active) {
            reset();
            return;
        }
        // Finish the visible blend, then load only the latest selection. This
        // bounds decoder use and avoids snapping during rapid arrow-key input.
        if (fade.running)
            return;
        if (displayedLayer && sameItem(displayedLayer.wallpaper, item)) {
            if (incomingLayer) incomingLayer.wallpaper = null;
            incomingLayer = null;
            return;
        }
        if (!item) {
            if (incomingLayer) incomingLayer.wallpaper = null;
            incomingLayer = null;
            if (displayedLayer) {
                fade.target = displayedLayer;
                fade.from = displayedLayer.opacity;
                fade.to = 0;
                fade.start();
            }
            return;
        }
        if (!incomingLayer)
            incomingLayer = displayedLayer === first ? second : first;
        incomingLayer.z = 1;
        incomingLayer.opacity = 0;
        if (displayedLayer) displayedLayer.z = 0;
        incomingLayer.wallpaper = item;
        Qt.callLater(root.tryTransition);
    }

    function tryTransition() {
        if (!active || fade.running || !incomingLayer
            || !sameItem(incomingLayer.wallpaper, item) || !incomingLayer.ready)
            return;
        // Keep the outgoing layer opaque underneath the incoming alpha blend.
        // Fading both layers would let the desktop show through at the midpoint.
        fade.target = incomingLayer;
        fade.from = 0;
        fade.to = 1;
        fade.start();
    }

    component PreviewLayer: Item {
        id: previewLayer
        property var wallpaper: null
        readonly property WallpaperPreviewFrame frame: loader.item as WallpaperPreviewFrame
        readonly property bool ready: frame !== null && frame.ready
        opacity: 0
        onReadyChanged: Qt.callLater(root.tryTransition)
        Loader {
            id: loader
            anchors.fill: parent
            active: root.active && previewLayer.wallpaper !== null
            sourceComponent: WallpaperPreviewFrame {
                item: previewLayer.wallpaper
            }
        }
    }

    PreviewLayer { id: first; anchors.fill: parent }
    PreviewLayer { id: second; anchors.fill: parent }

    NumberAnimation {
        id: fade
        property: "opacity"
        duration: root.motion && root.motion.calm ? 0 : (root.motion ? root.motion.standard : 300)
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.displayedLayer) {
                root.displayedLayer.wallpaper = null;
                root.displayedLayer.opacity = 0;
            }
            root.displayedLayer = root.incomingLayer;
            root.incomingLayer = null;
            Qt.callLater(root.update);
        }
    }

    onItemChanged: update()
    onActiveChanged: update()
    Component.onCompleted: {
        initialized = true;
        update();
    }
}
