pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/desktop.js" as Desktop

Singleton {
    id: root

    property var items: []

    readonly property string scanScript: [
        'data_home="${XDG_DATA_HOME:-$HOME/.local/share}"',
        'data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"',
        'seen=""',
        'scan() {',
        '    d="$1"',
        '    [ -d "$d" ] || return 0',
        '    case ":$seen:" in *":$d:"*) return 0 ;; esac',
        '    seen="$seen:$d"',
        "    find -L \"$d\" -maxdepth 1 -type f -name '*.desktop' -exec sh -c '",
        '        for f; do',
        '            printf "\\n@@ZESTIFY_FILE@@%s\\n" "$f"',
        '            cat "$f"',
        '        done',
        "    ' sh {} +",
        '}',
        'scan "$data_home/applications"',
        'oldifs="$IFS"',
        'IFS=:',
        'for base in $data_dirs; do scan "$base/applications"; done',
        'IFS="$oldifs"'
    ].join("\n")

    function refresh() {
        if (scan.running)
            scan.running = false;
        scan.running = true;
    }

    function launch(app) {
        if (!app || !app.exec)
            return;
        let command = Desktop.resolveExec(app.exec, app);
        if (command.length === 0)
            return;
        if (app.terminal) {
            const terminal = Quickshell.env("TERMINAL") || "kitty";
            command = [terminal, "-e"].concat(command);
        }
        Quickshell.execDetached(command);
    }

    function currentDesktops() {
        const value = Quickshell.env("XDG_CURRENT_DESKTOP");
        if (!value)
            return [];
        return String(value).toLowerCase().split(":").filter(function(item) {
            return item.length > 0;
        });
    }

    function consume(text) {
        const chunks = String(text).split("\n@@ZESTIFY_FILE@@");
        const files = [];

        for (let i = 0; i < chunks.length; i++) {
            const chunk = chunks[i];
            if (chunk.length === 0)
                continue;
            const newline = chunk.indexOf("\n");
            if (newline < 0)
                continue;

            const path = chunk.slice(0, newline).trim();
            if (path.length === 0)
                continue;
            files.push({ path: path, text: chunk.slice(newline + 1) });
        }

        root.items = Desktop.collectFiles(files, currentDesktops());
    }

    Process {
        id: scan
        command: ["sh", "-c", root.scanScript]
        stdout: StdioCollector {
            onStreamFinished: root.consume(text)
        }
    }
}
