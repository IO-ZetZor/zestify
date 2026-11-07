//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "."
import "components"
import "singletons"

ShellRoot {
    PwObjectTracker {
        // qmllint disable missing-property
        objects: Pipewire.nodes.values
    }

    Connections {
        target: Config

        function onRevisionChanged(): void {
            Appearance.applyLayerRules();
        }
    }

    Component.onCompleted: Appearance.applyLayerRules()

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

    IpcHandler {
        target: "zestify"

        function ping(): string {
            return "pong";
        }

        function quit(): void {
            Qt.quit();
        }

        function lockState(locked: bool): void {
            Session.handleLockState(locked);
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
            ShellState.open(name, Config.monitor.primary);
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
