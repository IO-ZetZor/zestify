import QtQuick
import Quickshell.Io
import "../singletons"

Item {
    id: root
    property string path: ""
    property string frame: ""
    property string requestedPath: ""
    readonly property bool ready: image.status === Image.Ready && frame.length > 0
    readonly property string revision: frame

    function refresh() {
        if (extract.running)
            return;
        requestedPath = path;
        frame = "";
        if (path.length) {
            extract.command = [Session.python, Session.scriptsDir + "/lock.py", "--frame", path];
            extract.running = true;
        }
    }

    onPathChanged: refresh()
    Component.onCompleted: refresh()

    Process {
        id: extract
        stdout: StdioCollector { id: output }
        onExited: (code) => {
            if (root.path !== root.requestedPath) {
                root.refresh();
                return;
            }
            if (code === 0) {
                try { root.frame = JSON.parse(output.text).url || ""; }
                catch (error) { root.frame = ""; }
            }
        }
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.frame
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
}
