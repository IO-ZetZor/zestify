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
    property bool showTitle: true
    property bool focusRequested: false

    readonly property alias pill: pill

    screen: targetScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: pill && pill.fullscreen ? 0 : topGap + (pill ? pill.restHeight : 0)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-pill"
    WlrLayershell.keyboardFocus: pill && pill.surface.length > 0 && !pill.fullscreen
        ? (root.focusRequested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
        : WlrKeyboardFocus.None

    // Hyprland routes all pointer input to Exclusive layers, even outside
    // their masks. Acquire focus for keyboard-opened surfaces briefly, then
    // retain focus with OnDemand so the screen-edge gestures remain reachable.
    function acquireFocus() {
        root.focusRequested = pill.surface.length > 0 && !pill.fullscreen;
        if (root.focusRequested) focusPulse.restart();
        else focusPulse.stop();
    }
    Component.onCompleted: root.acquireFocus()
    Timer {
        id: focusPulse
        interval: 100
        onTriggered: root.focusRequested = false
    }
    Connections {
        target: pill
        function onSurfaceChanged() { root.acquireFocus(); }
        function onFullscreenChanged() { root.acquireFocus(); }
    }

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: targetScreen ? targetScreen.height : 0

    mask: pill && pill.surface.length > 0
        ? fullMask
        : (pill && pill.fullscreen ? emptyMask : pillMask)

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
        // Leave the drawer's narrow edge strip reachable while expanded.
        x: Math.max(3, Math.min(6, Math.round(4 * (pill ? pill.s : root.uiScale))))
        y: 0
        width: targetScreen ? Math.max(0, targetScreen.width - x) : 0
        height: targetScreen ? targetScreen.height : 0
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
            showTitle: root.showTitle
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
