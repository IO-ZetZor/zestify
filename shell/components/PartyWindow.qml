import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../lib/layout.js" as LayoutLib

PanelWindow {
    id: root

    property var targetScreen: null
    property var theme
    property var players: null
    property var motion: null
    property real uiScale: 1
    property real topGap: 8
    property real restWidth: 1000
    property real restHeight: 34
    property var sourcePill: null

    readonly property real s: targetScreen
        ? LayoutLib.pillScale(targetScreen.width, targetScreen.height) * uiScale : uiScale
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    readonly property bool active: screenName.length > 0 && ShellState.isPartyOn(screenName)
    readonly property var player: players ? players.active : null
    readonly property string scriptsDir: Quickshell.shellDir
        ? Quickshell.shellDir + "/../scripts" : ""
    readonly property alias stage: partyStage

    screen: targetScreen
    visible: active || partyStage.animating || partyStage.entry > 0.001
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-party"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    mask: (active || partyStage.animating || partyStage.entry > 0.001)
        ? fullMask : emptyMask

    Region {
        id: emptyMask
        width: 0
        height: 0
    }

    Region {
        id: fullMask
        width: targetScreen ? targetScreen.width : 0
        height: targetScreen ? targetScreen.height : 0
    }

    Connections {
        target: Session
        function onLockedChanged() {
            if (Session.locked)
                ShellState.closeParty(root.screenName);
        }
    }

    Component.onDestruction: ShellState.closeParty(root.screenName)

    Item {
        id: keyboard
        anchors.fill: parent
        focus: root.active
        Keys.enabled: root.active
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                ShellState.closeParty(root.screenName);
            }
        }
    }

    PartyStage {
        id: partyStage
        anchors.fill: parent
        theme: root.theme
        screen: root.targetScreen
        player: root.player
        motion: root.motion
        s: root.s
        topGap: root.topGap
        restWidth: root.restWidth
        restHeight: root.restHeight
        sourcePill: root.sourcePill
        scriptsDir: root.scriptsDir
        active: root.active
        onExitRequested: ShellState.closeParty(root.screenName)
    }
}
