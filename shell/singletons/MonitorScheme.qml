import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/wallpapers.js" as WallpapersLib

QtObject {
    id: root

    property string screenName: ""
    property var scheme: null
    property bool loaded: false

    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    readonly property string screenSlug: WallpapersLib.monitorSlug(root.screenName)

    function reload() {
        schemeFile.reload();
    }

    function parse(text) {
        try {
            const parsed = JSON.parse(text);
            root.scheme = parsed && (parsed.colours || parsed.colors || parsed.palettes) ? parsed : null;
            root.loaded = root.scheme !== null;
        } catch (error) {
            root.scheme = null;
            root.loaded = false;
        }
    }

    property var schemeFile: FileView {
        id: schemeFile

        path: root.stateDir + "/zestify/wallpaper/monitors/" + root.screenSlug + "-scheme.json"
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
