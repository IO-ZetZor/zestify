import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root

    property var targetScreen: null
    property var theme
    property real uiScale: 1
    property real topGap: 8
    property bool enabled: true
    property bool fullscreen: false
    property bool focusRequested: false
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    readonly property real s: targetScreen
        ? LayoutLib.pillScale(targetScreen.width, targetScreen.height) * uiScale : uiScale
    readonly property bool available: enabled && !fullscreen && !Session.locked && Session.dpmsActive
        && !ShellState.isOpenOn(screenName) && !ShellState.isPartyOn(screenName)
        && ShellState.notificationsOwner !== screenName && ShellState.powerOwner !== screenName
        && ShellState.shortcutsOwner !== screenName
    readonly property alias card: focusCard

    screen: targetScreen
    visible: available
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: available ? topGap + focusCard.restHeight : 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-focus"
    WlrLayershell.keyboardFocus: available && focusCard.editorOpen
        ? (focusRequested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
        : WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true }
    implicitHeight: targetScreen ? targetScreen.height : 0

    mask: !available ? emptyMask : focusCard.editorOpen ? fullMask : cardMask
    Region { id: emptyMask; width: 0; height: 0 }
    Region { id: cardMask; x: focusCard.x; y: focusCard.y; width: focusCard.width; height: focusCard.height }
    Region {
        id: fullMask
        x: Math.max(3, Math.min(6, Math.round(4 * root.s)))
        y: Math.max(6, root.topGap)
        width: root.targetScreen ? Math.max(0, root.targetScreen.width - 2 * x) : 0
        height: root.targetScreen ? Math.max(0, root.targetScreen.height - y - x) : 0
    }

    onAvailableChanged: {
        if (!available) {
            focusCard.dismiss();
            focusPulse.stop();
            focusRequested = false;
        }
    }
    Timer {
        id: focusPulse
        interval: 100
        onTriggered: root.focusRequested = false
    }
    Connections {
        target: focusCard
        function onEditorOpenChanged() {
            root.focusRequested = focusCard.editorOpen && root.available;
            if (root.focusRequested) focusPulse.restart();
            else focusPulse.stop();
        }
    }
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: focusCard.editorOpen
        onClicked: focusCard.dismiss()
    }
    FocusCard {
        id: focusCard
        anchors.top: parent.top
        anchors.topMargin: root.topGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.targetScreen ? Math.min(implicitWidth, root.targetScreen.width - 32 * root.s) : implicitWidth
        enabled: root.available
        theme: root.theme
        session: Focus.session
        s: root.s
        backgroundOpacity: Config.bar.opacity
        defaultMode: Config.focus.mode
        defaultMinutes: Config.focus.minutes
        defaultDnd: Config.focus.dnd
    }
}
