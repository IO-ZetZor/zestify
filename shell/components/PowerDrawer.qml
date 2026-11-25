import QtQuick
import "../lib/spring.js" as Spring

Item {
    id: root
    property var theme
    property var motion
    property real s: 1
    property real sideInset: 8 * s
    property real topInset: 8 * s
    property real backgroundOpacity: 1
    property bool dragging: false
    property bool opened: false
    property real pull: 0
    property real velocity: 0
    property real pressY: 0
    property real startPull: 0
    property real lastY: 0
    property double lastMove: 0
    property double lastFrame: 0
    readonly property real edgeHeight: Math.max(3, Math.min(6, Math.round(4 * s)))
    readonly property real drawerWidth: Math.max(0, Math.min(520 * s, width - 24 * s))
    readonly property real drawerHeight: Math.max(0, Math.min(280 * s, height - topInset - 24 * s))
    readonly property real target: opened ? drawerHeight : 0
    readonly property bool active: dragging || opened || settle.running || pull > 0.1
    readonly property real progress: drawerHeight > 0 ? Math.max(0, Math.min(1, pull / drawerHeight)) : 0
    readonly property alias settling: settle.running
    default property alias content: body.data
    signal pullStarted()
    signal closed()

    clip: true
    focus: active

    function beginPull(y) {
        if (!enabled || drawerWidth <= 0 || drawerHeight <= 0) return;
        settle.stop();
        dragging = true;
        pressY = y;
        lastY = y;
        lastMove = Date.now();
        startPull = pull;
        velocity = 0;
        root.forceActiveFocus();
        root.pullStarted();
    }
    function updatePull(y, sample) {
        if (!dragging) return;
        const now = Date.now();
        const dt = Math.max(1, now - lastMove) / 1000;
        if (sample !== false && y !== lastY) {
            velocity = Math.max(-1800 * s, Math.min(1800 * s, (lastY - y) / dt));
            lastY = y;
            lastMove = now;
        }
        const distance = startPull + pressY - y;
        pull = distance > drawerHeight ? drawerHeight + (distance - drawerHeight) * 0.18 : Math.max(0, distance);
    }
    function releasePull(y) {
        if (!dragging) return;
        updatePull(y, false);
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
    function close() {
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
        else if (opened) { settle.stop(); pull = drawerHeight; velocity = 0; }
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
        objectName: "powerDrawerPanel"
        x: (root.width - width) / 2
        y: root.height - root.pull
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
            anchors.margins: 8 * root.s
            anchors.topMargin: 24 * root.s
            // Cancel any confirmation hold as soon as the drawer is dismissed
            // or grabbed, and never let an edge release activate an action.
            enabled: root.opened && !root.dragging && !root.settling
        }
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 8 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64 * root.s
            height: 4 * root.s
            radius: height / 2
            color: root.theme.accent
            opacity: grab.containsMouse || root.dragging ? 1 : 0.5
        }
        MouseArea {
            id: grab
            objectName: "powerDrawerGrab"
            anchors.top: parent.top
            width: parent.width
            height: 20 * root.s
            hoverEnabled: true
            preventStealing: true
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => root.beginPull(mapToItem(root, mouse.x, mouse.y).y)
            onPositionChanged: mouse => root.updatePull(mapToItem(root, mouse.x, mouse.y).y)
            onReleased: mouse => root.releasePull(mapToItem(root, mouse.x, mouse.y).y)
            onCanceled: root.close()
        }
    }

    MouseArea {
        objectName: "powerDrawerEdge"
        x: root.sideInset
        y: root.height - height
        width: Math.max(0, root.width - 2 * root.sideInset)
        height: root.edgeHeight
        preventStealing: true
        enabled: !root.opened && !root.settling
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.SizeVerCursor
        onPressed: mouse => root.beginPull(mapToItem(root, mouse.x, mouse.y).y)
        onPositionChanged: mouse => root.updatePull(mapToItem(root, mouse.x, mouse.y).y)
        onReleased: mouse => root.releasePull(mapToItem(root, mouse.x, mouse.y).y)
        onCanceled: root.close()
    }
}
