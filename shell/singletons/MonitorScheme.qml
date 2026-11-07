import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string screenName: ""
    property var scheme: null
    property bool loaded: false

    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")

    function reload() {
        schemeFile.reload();
    }

    function parse(text) {
        try {
            root.scheme = JSON.parse(text);
            root.loaded = true;
        } catch (error) {
            root.scheme = null;
            root.loaded = false;
        }
    }

    property var schemeFile: FileView {
        id: schemeFile

        path: root.stateDir + "/zestify/wallpaper/monitors/" + root.screenName + "-scheme.json"
        watchChanges: true
        printErrors: false

        onLoaded: root.parse(text())
        onFileChanged: reload()
        onLoadFailed: {
            root.scheme = null;
            root.loaded = false;
        }
    }
}
