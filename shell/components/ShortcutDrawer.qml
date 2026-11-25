import QtQuick
import "../lib/spring.js" as Spring

Item {
    id: root
    property var theme
    property var motion
    property real s: 1
    property real topInset: 8 * s
    property real bottomInset: 8 * s
    property real backgroundOpacity: 1
    property bool dragging: false
    property bool opened: false
    property bool recording: false
    property real pull: 0
    property real velocity: 0
    property real pressX: 0
    property real startPull: 0
    property real lastX: 0
    property double lastMove: 0
    property double lastFrame: 0
    readonly property real edgeWidth: Math.max(3, Math.min(6, Math.round(4 * s)))
    readonly property real drawerWidth: Math.max(0, Math.min(80 * s, width - 24 * s))
    readonly property real drawerHeight: Math.max(0, Math.min(304 * s, height - topInset - bottomInset - 24 * s))
    readonly property real target: opened ? drawerWidth : 0
    readonly property bool active: dragging || opened || settle.running || pull > 0.1
    readonly property real progress: drawerWidth > 0 ? Math.max(0, Math.min(1, pull / drawerWidth)) : 0
    readonly property alias settling: settle.running
    default property alias content: body.data
    signal pullStarted()
    signal closed()

    clip: true
    focus: active

    function beginPull(x) {
        if (!enabled || drawerWidth <= 0 || drawerHeight <= 0) return;
        settle.stop();
        dragging = true;
        pressX = x;
        lastX = x;
        lastMove = Date.now();
        startPull = pull;
        velocity = 0;
        root.forceActiveFocus();
        root.pullStarted();
    }
    function updatePull(x, sample) {
        if (!dragging) return;
        const now = Date.now();
        const dt = Math.max(1, now - lastMove) / 1000;
        if (sample !== false && x !== lastX) {
            velocity = Math.max(-1800 * s, Math.min(1800 * s, (lastX - x) / dt));
            lastX = x;
            lastMove = now;
        }
        const distance = startPull + pressX - x;
        pull = distance > drawerWidth ? drawerWidth + (distance - drawerWidth) * 0.18 : Math.max(0, distance);
    }
    function releasePull(x) {
        if (!dragging) return;
        updatePull(x, false);
        if (Date.now() - lastMove > 100) velocity = 0;
        dragging = false;
        opened = velocity > 600 * s || (velocity >= -600 * s && progress >= 0.42);
        startSettle();
    }
    function startSettle() {
        lastFrame = Date.now();
        settle.start();
    }
    function open() {
        if (!enabled) return;
        dragging = false;
        opened = true;
        velocity = 0;
        root.forceActiveFocus();
        startSettle();
    }
    function close(immediate) {
        if (immediate === true) {
            reset();
            closed();
            return;
        }
        dragging = false;
        opened = false;
        velocity = 0;
        startSettle();
    }
    function reset() {
        settle.stop();
        dragging = false;
        opened = false;
        pull = 0;
        velocity = 0;
    }
    function resize() {
        if (dragging) { reset(); closed(); }
        else if (opened) { settle.stop(); pull = drawerWidth; velocity = 0; }
    }
    onEnabledChanged: if (!enabled) { reset(); closed(); }
    onWidthChanged: resize()
    onHeightChanged: resize()
    onDrawerWidthChanged: resize()
    onDrawerHeightChanged: resize()
    Keys.onEscapePressed: event => { if (active) { close(); event.accepted = true; } }

    Timer {
        id: settle
        interval: 16
        repeat: true
        onTriggered: {
            const now = Date.now();
            const dt = Math.max(0.001, Math.min(0.05, (now - root.lastFrame) / 1000));
            root.lastFrame = now;
            const step = Spring.step(root.pull - root.target, root.velocity, 18,
                root.motion && root.motion.calm ? 1 : 0.72, dt);
            root.pull = root.target + step[0];
            root.velocity = step[1];
            if (Math.abs(step[0]) < 0.25 && Math.abs(step[1]) < 4) {
                stop();
                root.pull = root.target;
                root.velocity = 0;
                if (!root.opened) root.closed();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.progress * 0.22
        visible: root.active
        MouseArea {
            anchors.fill: parent
            enabled: root.active && !root.dragging
            onClicked: root.close()
        }
    }

    Rectangle {
        id: panel
        objectName: "shortcutDrawerPanel"
        x: root.width - root.pull
        y: root.topInset + (root.height - root.topInset - root.bottomInset - height) / 2
        width: root.drawerWidth
        height: root.drawerHeight
        radius: 20 * root.s
        color: "transparent"
        visible: root.active
        clip: true
        PillBody {
            anchors.fill: parent
            theme: root.theme
            backgroundOpacity: root.backgroundOpacity
            cornerRadius: panel.radius
        }
        MouseArea { anchors.fill: parent; onClicked: {} }
        Item {
            id: body
            anchors.fill: parent
            anchors.margins: 16 * root.s
            // A gesture release must never also activate a shortcut.
            enabled: root.opened && !root.dragging && !root.settling
        }
        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 4 * root.s
            height: Math.min(64 * root.s, parent.height)
            radius: width / 2
            color: root.theme.accent
            opacity: grab.containsMouse || root.dragging ? 1 : 0.5
        }
        MouseArea {
            id: grab
            objectName: "shortcutDrawerGrab"
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 16 * root.s
            hoverEnabled: true
            preventStealing: true
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => root.beginPull(mapToItem(root, mouse.x, mouse.y).x)
            onPositionChanged: mouse => root.updatePull(mapToItem(root, mouse.x, mouse.y).x)
            onReleased: mouse => root.releasePull(mapToItem(root, mouse.x, mouse.y).x)
            onCanceled: root.close()
        }
    }

    Rectangle {
        objectName: "shortcutRecordingIndicator"
        visible: root.recording && !root.active
        anchors.right: parent.right
        anchors.rightMargin: 4 * root.s
        anchors.verticalCenter: parent.verticalCenter
        width: 6 * root.s
        height: width
        radius: width / 2
        color: root.theme.danger
        Accessible.name: "Screen recording is active"
    }

    MouseArea {
        objectName: "shortcutDrawerEdge"
        x: root.width - width
        y: root.topInset
        width: root.edgeWidth
        height: Math.max(0, root.height - y - root.bottomInset)
        preventStealing: true
        enabled: !root.opened && !root.settling
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.SizeHorCursor
        onPressed: mouse => root.beginPull(mapToItem(root, mouse.x, mouse.y).x)
        onPositionChanged: mouse => root.updatePull(mapToItem(root, mouse.x, mouse.y).x)
        onReleased: mouse => root.releasePull(mapToItem(root, mouse.x, mouse.y).x)
        onCanceled: root.close()
    }
}
