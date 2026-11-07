pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property var list: Mpris.players.values
    readonly property var active: list.find(p => p.isPlaying) ?? list[0] ?? null
    readonly property bool hasPlayer: active !== null
    readonly property bool isPlaying: active ? active.isPlaying : false

    function playPause() {
        if (active && active.canTogglePlaying)
            active.togglePlaying();
    }

    function next() {
        if (active && active.canGoNext)
            active.next();
    }

    function previous() {
        if (active && active.canGoPrevious)
            active.previous();
    }

    function seek(position) {
        if (active && active.canSeek && active.positionSupported)
            active.position = position;
    }
}
