import QtQuick

Item {
    id: root

    property var motion
    property int duration: 700
    property var frame: null
    property int serial: 0
    property real progress: 0
    readonly property bool active: frame !== null
    readonly property bool ready: image.status === Image.Ready
    signal finished()

    clip: true
    visible: active

    function prepare(result, generation) {
        reset();
        serial = generation;
        frame = result;
    }

    function reveal() {
        if (ready)
            fade.restart();
        else
            reset();
    }

    function reset() {
        fade.stop();
        frame = null;
        progress = 0;
    }

    Image {
        id: image
        objectName: "unlockFadeImage"
        width: root.width
        height: root.height
        source: root.frame ? root.frame.url : ""
        asynchronous: false
        opacity: 1 - root.progress
    }

    NumberAnimation {
        id: fade
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.motion && root.motion.calm ? 0
            : root.duration
        easing.type: Easing.InOutCubic
        onFinished: {
            root.reset();
            root.finished();
        }
    }
}
