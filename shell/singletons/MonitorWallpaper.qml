import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string screenName: ""
    property string path: ""
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/zestify"

    function reload() {
        if (root.screenName.length > 0)
            file.reload();
    }

    onScreenNameChanged: reload()

    property var file: FileView {
        path: root.stateDir + "/wallpaper/monitors/" + root.screenName + ".txt"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.path = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.path = ""
    }
}
