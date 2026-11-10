import QtQuick

Item {
    id: root

    property var theme
    property var motion
    property real backgroundOpacity: 1
    property string userName: ""
    property string batteryText: ""
    property real uiScale: 1
    property int lockTimeout: 40000
    property bool dragging: false
    property bool requestingLock: false
    property real pull: 0
    property real handoffProgress: 0
    property real settleTarget: 0
    property real pressY: 0
    property date now: new Date()

    readonly property real edgeHeight: Math.max(2, Math.min(6, 3 * uiScale))
    readonly property real triggerDistance: Math.min(height * 0.3, 180 * uiScale)
    readonly property real progress: height > 0 ? pull / height : 0
    readonly property real faceScale: Math.max(0.75, Math.min(1.1, Math.min(width, height) / 1080)) * uiScale
    readonly property bool ready: height > 0 && pull >= triggerDistance
    readonly property bool active: dragging || requestingLock || pull > 0 || settle.running

    signal lockRequested()
    signal lockTimedOut()

    clip: true
    focus: active

    Theme { id: fallbackTheme }

    function reset() {
        settle.stop();
        lockTimer.stop();
        dragging = false;
        requestingLock = false;
        pull = 0;
        handoffProgress = 0;
    }

    function cancel() {
        if (requestingLock)
            return;
        dragging = false;
        settleTarget = 0;
        settle.restart();
    }

    function updatePull(y) {
        pull = Math.max(0, Math.min(height, y - pressY));
    }

    onEnabledChanged: {
        if (!enabled)
            reset();
    }
    onHeightChanged: reset()
    Keys.onEscapePressed: (event) => {
        if (active && !requestingLock) {
            cancel();
            event.accepted = true;
        }
    }

    ParallelAnimation {
        id: settle
        NumberAnimation {
            target: root
            property: "pull"
            to: root.settleTarget
            duration: root.requestingLock
                ? (root.motion ? root.motion.morph : 420)
                : (root.motion ? root.motion.standard : 300)
            easing.type: root.requestingLock ? Easing.InOutCubic : Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "handoffProgress"
            to: root.requestingLock ? 1 : 0
            duration: root.requestingLock
                ? (root.motion ? root.motion.morph : 420)
                : (root.motion ? root.motion.standard : 300)
            easing.type: Easing.InOutCubic
        }
        onFinished: {
            if (root.requestingLock) {
                lockTimer.restart();
                root.lockRequested();
            }
        }
    }

    Timer {
        id: lockTimer
        interval: root.lockTimeout
        onTriggered: {
            root.reset();
            root.lockTimedOut();
        }
    }

    Timer {
        interval: 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    PillBody {
        id: curtain
        y: root.pull - height
        width: root.width
        height: root.height
        cornerRadius: 24 * root.uiScale * (1 - root.handoffProgress)
        // The handoff already animates the radius alongside the curtain.
        animateCornerRadius: false
        theme: root.theme || fallbackTheme
        backgroundOpacity: root.backgroundOpacity
        visible: root.active
        clip: true

        LockScreenFace {
            anchors.fill: parent
            theme: root.theme
            s: root.faceScale
            now: root.now
            userName: root.userName
            batteryText: root.batteryText
            ready: root.ready
            requestingLock: root.requestingLock
            handoffProgress: root.handoffProgress
            prompt: root.ready ? "Release to lock" : "Pull down · Esc to cancel"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: handle.top
            anchors.bottomMargin: 14 * root.uiScale
            text: root.ready ? "Release to lock" : "Pull down to lock · Esc to cancel"
            opacity: 1 - root.handoffProgress
            color: root.ready && root.theme ? root.theme.accent
                : (root.theme ? root.theme.cream : "#e6e4f0")
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: 13 * root.uiScale
        }

        Rectangle {
            id: handle
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14 * root.uiScale
            width: 64 * root.uiScale
            height: 4 * root.uiScale
            radius: height / 2
            color: root.theme ? root.theme.accent : "#bfc4ee"
            opacity: (root.ready ? 1 : 0.55) * (1 - root.handoffProgress)
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.SizeVerCursor

        onPressed: (mouse) => {
            if (root.active || mouse.y > root.edgeHeight) {
                mouse.accepted = false;
                return;
            }
            root.pressY = mouse.y;
            root.dragging = true;
            // Show the grabbed edge before the first motion event arrives.
            root.pull = root.edgeHeight;
            root.forceActiveFocus();
        }
        onPositionChanged: (mouse) => {
            if (root.dragging)
                root.updatePull(mouse.y);
        }
        onReleased: (mouse) => {
            if (!root.dragging)
                return;
            root.updatePull(mouse.y);
            root.dragging = false;
            if (!root.ready) {
                root.cancel();
                return;
            }
            root.requestingLock = true;
            root.settleTarget = root.height;
            settle.restart();
        }
        onCanceled: {
            if (root.dragging)
                root.cancel();
        }
    }
}
