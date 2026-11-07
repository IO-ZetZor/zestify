pragma Singleton
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import "../lib/scheme.js" as Scheme

Singleton {
    id: root

    property var globalScheme: null
    readonly property var fallback: Scheme.fallbackScheme()

    function _setGlobal(text) {
        try {
            root.globalScheme = JSON.parse(text);
        } catch (error) {
            root.globalScheme = null;
        }
    }

    function schemeFor(screenName) {
        for (let i = 0; i < monitorInstances.count; i++) {
            const monitor = monitorInstances.objectAt(i);
            if (monitor && monitor.screenName === screenName && monitor.scheme)
                return monitor.scheme;
        }
        return root.globalScheme || root.fallback;
    }

    function coloursFor(screenName) {
        const scheme = root.schemeFor(screenName);
        return scheme.colours || root.fallback.colours;
    }

    function reload() {
        globalFile.reload();
        for (let i = 0; i < monitorInstances.count; i++) {
            const monitor = monitorInstances.objectAt(i);
            if (monitor && monitor["reload"])
                monitor["reload"]();
        }
    }

    Instantiator {
        id: monitorInstances

        model: Quickshell.screens

        delegate: MonitorScheme {
            required property var modelData
            screenName: modelData.name
        }
    }

    FileView {
        id: globalFile

        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/zestify/scheme.json"
        watchChanges: true
        printErrors: false

        onLoaded: root._setGlobal(text())
        onFileChanged: reload()
        onLoadFailed: root.globalScheme = null
    }
}
