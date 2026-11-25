import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var targetScreen: null
    property var theme
    property var stats
    property var players
    property var motion
    property var wallpapers
    property string wallpaperFolder: ""
    property real uiScale: 1
    property real topGap: 8
    property bool showRest: true
    property bool partyVisible: false
    property bool focusRequested: false
    property bool expandedCanvasHeld: false
    readonly property bool fullCanvas: pill.expanded || expandedCanvasHeld
    readonly property alias pill: pill

    screen: targetScreen
    visible: showRest || fullCanvas
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: !showRest || (pill && (pill.fullscreen || pill.partyOn))
        ? 0 : topGap + (pill ? pill.restHeight : 0)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-pill"
    WlrLayershell.keyboardFocus: pill && pill.surface.length > 0 && !pill.fullscreenHidden
        ? (root.focusRequested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
        : WlrKeyboardFocus.None

    // Hyprland routes all pointer input to Exclusive layers, even outside
    // their masks. Acquire focus for keyboard-opened surfaces briefly, then
    // retain focus with OnDemand so the screen-edge gestures remain reachable.
    function acquireFocus() {
        root.focusRequested = pill.surface.length > 0 && !pill.fullscreenHidden;
        if (root.focusRequested) focusPulse.restart();
        else focusPulse.stop();
    }
    Component.onCompleted: {
        root.expandedCanvasHeld = pill.expanded;
        root.acquireFocus();
    }
    Timer {
        id: focusPulse
        interval: 100
        onTriggered: root.focusRequested = false
    }
    Connections {
        target: pill
        function onSurfaceChanged() {
            root.acquireFocus();
            if (pill.expanded) {
                releaseCanvas.stop();
                root.expandedCanvasHeld = true;
            } else if (root.expandedCanvasHeld) {
                releaseCanvas.restart();
            }
        }
        function onFullscreenChanged() { root.acquireFocus(); }
    }

    Timer {
        id: releaseCanvas
        interval: (root.motion ? root.motion.morph : 420) + 32
        onTriggered: {
            if (pill.morphing) restart();
            else root.expandedCanvasHeld = false;
        }
    }

    anchors {
        top: true
        left: true
        right: true
    }
    // Keep the native canvas stable. Hyprland can scale the previous buffer
    // into new layer bounds before Qt commits the resized buffer, producing
    // a one-frame jump even with compositor layer animations disabled.
    // Animate the child pill only; its input region still follows its bounds.
    implicitWidth: targetScreen ? targetScreen.width : 0
    implicitHeight: targetScreen ? targetScreen.height : 0

    mask: !root.visible || (pill && (pill.fullscreenHidden || pill.partyOn))
        ? emptyMask
        : (pill && pill.surface.length > 0 ? fullMask : pillMask)

    Region {
        id: emptyMask
        width: 0
        height: 0
    }

    Region {
        id: pillMask
        x: slot.x + pill.x
        y: slot.y + pill.y
        width: pill.width
        height: pill.height
    }

    Region {
        id: fullMask
        // Keep all drawer edge strips reachable while expanded.
        x: Math.max(3, Math.min(6, Math.round(4 * (pill ? pill.s : root.uiScale))))
        y: 0
        width: targetScreen ? Math.max(0, targetScreen.width - 2 * x) : 0
        height: targetScreen ? Math.max(0, targetScreen.height - x) : 0
    }

    // While a surface is open the window is not masked, so this catches clicks
    // anywhere outside the pill and closes the surface.
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: pill && pill.surface.length > 0
        onClicked: pill.closeSurface()
    }

    Item {
        id: slot

        anchors.top: parent.top
        anchors.topMargin: root.topGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: pill.width
        height: pill.height

        Pill {
            id: pill
            theme: root.theme
            screen: root.targetScreen
            stats: root.stats
            players: root.players
            motion: root.motion
            wallpapers: root.wallpapers
            wallpaperFolder: root.wallpaperFolder
            uiScale: root.uiScale
            topGap: root.topGap
            partyVisible: root.partyVisible
            windowObject: root
        }

        focus: pill.surface.length > 0
        Keys.enabled: pill.surface.length > 0
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                pill.closeSurface();
            }
        }
    }
}
