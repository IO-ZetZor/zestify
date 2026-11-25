pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    signal ready(string source, string path, int width, int height)
    signal failed(string source, string error)

    readonly property string bin: Quickshell.env("ZESTI_BIN") || Quickshell.env("ZESTIFY_BIN") || "zesti"
    property bool busy: false
    property string pendingSource: ""
    property int pendingWidth: 0
    property int pendingHeight: 0
    property string pendingCodec: "h264"
    property int pendingCrf: 20
    property int pendingMaxFps: 24

    function ensure(source, width, height, codec, crf, maxFps) {
        if (!source) {
            root.failed(source, "no source");
            return;
        }
        if (root.busy) {
            root.failed(source, "proxy busy");
            return;
        }
        const nextCodec = codec || "h264";
        const nextCrf = crf === undefined ? 20 : Number(crf);
        const nextMaxFps = maxFps === undefined ? 24 : Number(maxFps);
        root.pendingSource = source;
        root.pendingWidth = width;
        root.pendingHeight = height;
        root.pendingCodec = nextCodec;
        root.pendingCrf = nextCrf;
        root.pendingMaxFps = nextMaxFps;
        root.busy = true;
        process.command = [root.bin, "proxy", "ensure", "--source", source,
            "--width", String(width), "--height", String(height),
            "--codec", nextCodec, "--crf", String(nextCrf), "--max-fps", String(nextMaxFps)];
        process.running = true;
    }

    property var process: Process {
        id: worker

        stdout: StdioCollector {
            id: out
        }
        stderr: StdioCollector {
            id: err
        }
        onExited: function(code) {
            const source = root.pendingSource;
            const width = root.pendingWidth;
            const height = root.pendingHeight;
            if (code !== 0) {
                root.failed(source, err.text.trim() || "proxy exited " + code);
            } else {
                try {
                    const data = JSON.parse(out.text);
                    if (data.ok && data.path)
                        root.ready(source, data.path, width, height);
                    else
                        root.failed(source, data.error || "proxy failed");
                } catch (e) {
                    root.failed(source, "invalid proxy response: " + e);
                }
            }
            root.busy = false;
        }
    }
}
