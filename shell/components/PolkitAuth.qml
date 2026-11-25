import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "../singletons"

Scope {
    id: root
    readonly property var targetScreen: {
        const screens = Quickshell.screens;
        for (const screen of screens)
            if (screen.name === Config.monitor.activePrimary) return screen;
        return screens.length > 0 ? screens[0] : null;
    }

    PolkitAgent {
        id: agent
        path: "/org/zestify/PolkitAgent"
        onAuthenticationRequestStarted: {
            if (Session.locked && flow) flow.cancelAuthenticationRequest();
        }
    }
    Connections {
        target: Session
        function onLockedChanged() {
            if (Session.locked && agent.flow) agent.flow.cancelAuthenticationRequest();
        }
    }
    Theme {
        id: theme
        scheme: Colours.schemeFor(root.targetScreen ? root.targetScreen.name : "")
        mode: Config.theme.mode
        fontFamily: Config.theme.fontFamily
    }
    LazyLoader {
        active: agent.isActive && agent.flow && !agent.flow.isCompleted && !Session.locked && root.targetScreen !== null
        PanelWindow {
            screen: root.targetScreen
            color: "#88000000"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "zestify-polkit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            AuthDialog {
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 32)
                flow: agent.flow
                theme: theme
            }
        }
    }
}
