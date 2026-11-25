import QtQuick
import QtQuick.Effects

// Retain the completed blur, not merely its input. The source must be static;
// callers invalidate it when an asynchronous frame or its geometry changes.
Item {
    id: root
    property Item sourceItem: null
    property bool sourceReady: false
    property var revision: null
    property real blur: 1
    property int blurMax: 64
    property real devicePixelRatio: Screen.devicePixelRatio
    readonly property bool cached: snapshot.valid
    property int generation: 0
    property int captureGeneration: -1
    property bool pending: false
    property bool awaitingInput: false

    function invalidate() {
        generation++;
        snapshot.valid = false;
        Qt.callLater(refresh);
    }
    function refresh() {
        if (pending || !sourceReady || !sourceItem || width <= 0 || height <= 0)
            return;
        captureGeneration = generation;
        pending = true;
        awaitingInput = true;
        inputCapture.scheduleUpdate();
        // Drive the input layer even when the final snapshot is frozen. The
        // completed input schedules a second pass with current pixels/bounds.
        snapshot.scheduleUpdate();
    }
    onSourceItemChanged: invalidate()
    onSourceReadyChanged: invalidate()
    onRevisionChanged: invalidate()
    onWidthChanged: invalidate()
    onHeightChanged: invalidate()
    onDevicePixelRatioChanged: invalidate()
    onBlurChanged: invalidate()
    onBlurMaxChanged: invalidate()
    Component.onCompleted: invalidate()

    ShaderEffectSource {
        id: inputCapture
        sourceItem: root.sourceItem
        sourceRect: Qt.rect(0, 0, root.width, root.height)
        textureSize: Qt.size(Math.max(1, Math.ceil(root.width * root.devicePixelRatio)),
                             Math.max(1, Math.ceil(root.height * root.devicePixelRatio)))
        live: false
        hideSource: true
        anchors.fill: parent
        // scheduleUpdateCompleted needs a drawable preprocessing node. This
        // driver stays below RGBA8 visibility while its texture is consumed.
        visible: root.pending
        opacity: 0.0015
        smooth: true
        onScheduledUpdateCompleted: {
            if (!root.pending) return;
            if (root.sourceReady && root.captureGeneration === root.generation) {
                root.awaitingInput = false;
                snapshot.scheduleUpdate();
            } else {
                root.pending = false;
                Qt.callLater(root.refresh);
            }
        }
    }
    Item {
        id: blurred
        anchors.fill: parent
        MultiEffect {
            anchors.fill: parent
            source: inputCapture
            // Full-output backgrounds need no padding beyond their window.
            autoPaddingEnabled: false
            blurEnabled: true
            blur: root.blur
            blurMax: root.blurMax
        }
    }
    ShaderEffectSource {
        id: snapshot
        objectName: "blurSnapshot"
        property bool valid: false
        anchors.fill: parent
        sourceItem: blurred
        sourceRect: Qt.rect(0, 0, width, height)
        textureSize: Qt.size(Math.max(1, Math.ceil(width * root.devicePixelRatio)),
                             Math.max(1, Math.ceil(height * root.devicePixelRatio)))
        live: false
        hideSource: true
        smooth: true
        // An initial scheduled capture must render even before it is valid.
        visible: root.sourceReady
        onScheduledUpdateCompleted: {
            if (!root.pending || root.awaitingInput) return;
            root.pending = false;
            valid = root.sourceReady && root.captureGeneration === root.generation;
            if (!valid) Qt.callLater(root.refresh);
        }
    }
}
