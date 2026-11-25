//@ pragma UseQApplication
// Rasterize small labels and font icons at their final size instead of using distance fields.
//@ pragma NativeTextRendering

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "."
import "components"
import "singletons"

ShellRoot {
    id: root

    readonly property string appThemeSettings: JSON.stringify([
        Config.value("theme.mode", "dark"), Config.value("monitor.primary", "eDP-1"),
        Config.value("theme.apply", true)
    ])
    property string appliedThemeSettings: ""

    PwObjectTracker {
        // qmllint disable missing-property
        objects: Pipewire.nodes.values
    }

    Connections {
        target: Config

        function onRevisionChanged(): void {
            Appearance.applyLayerRules();
            if (root.appliedThemeSettings.length > 0 && root.appliedThemeSettings !== root.appThemeSettings)
                applyThemeTimer.restart();
            root.appliedThemeSettings = root.appThemeSettings;
        }
    }

    Component.onCompleted: {
        root.appliedThemeSettings = root.appThemeSettings;
        Appearance.applyLayerRules();
        if (Config.value("theme.apply", true) !== false)
            applyThemeTimer.restart();
    }

    Timer {
        id: applyThemeTimer
        interval: 200
        onTriggered: {
            if (applyThemeProcess.running)
                restart();
            else
                applyThemeProcess.running = true;
        }
    }

    Process {
        id: applyThemeProcess
        command: [Session.cli, "theme", "apply"]
        stderr: StdioCollector { id: applyThemeErrors }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("zestify: application theme failed:", applyThemeErrors.text.trim());
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: MonitorShell {
            required property var modelData

            screen: modelData
        }
    }

    Osd {
        id: osdDisplay
    }

    PolkitAuth {}
    SessionLock { id: sessionLock }

    IpcHandler {
        target: "zestify"

        function ping(): string {
            return "pong";
        }

        function quit(): void {
            Qt.quit();
        }

        function lock(): int {
            return sessionLock.requestLock("");
        }

        function lockStatus(): string {
            return sessionLock.status();
        }

        function aboutToSleep(value: bool): void {
            Session.handleAboutToSleep(value);
        }

        function dpmsState(off: bool): void {
            Session.handleDpmsState(off);
        }

        function osd(kind: string, value: real): void {
            osdDisplay.show(kind, value);
        }

        function notify(title: string, body: string): void {
            Notifications.notify(title, body, "normal", "Zestify", 5000);
        }

        function toggleDnd(): bool {
            Notifications.toggleDnd();
            return Notifications.dnd;
        }

        function openSurface(name: string): void {
            ShellState.open(name, Config.monitor.activePrimary);
        }

        function setConfig(path: string, json: string): bool {
            try {
                Config.setValue(path, JSON.parse(json));
                return true;
            } catch (error) {
                console.warn("zestify: setConfig failed", error);
                return false;
            }
        }
    }
}
