import QtQuick
import "../lib/lyrics.js" as Lyrics
import "../lib/time.js" as Time

QtObject {
    id: root
    property var player: null
    property bool active: true
    property string endpoint: "https://lrclib.net/api/get"
    property string status: "idle"
    property string attribution: ""
    property var lines: []
    property bool synced: false
    property var request: null
    property int generation: 0
    readonly property string title: player ? String(player.trackTitle || "").trim() : ""
    readonly property string artist: player ? Time.joinArtists(player.trackArtist) : ""
    readonly property string album: player ? String(player.trackAlbum || "").trim() : ""
    readonly property real duration: player && player.metadata
        ? Math.max(0, Number(player.metadata["mpris:length"]) || 0) / 1000000 : 0
    readonly property string embedded: player && player.metadata
        ? String(player.metadata["xesam:lyrics"] || player.metadata["lyrics"] || "") : ""
    readonly property string key: JSON.stringify([title, artist, album, duration, embedded])
    readonly property int currentIndex: synced && player ? Lyrics.indexAt(lines, player.position) : -1
    readonly property string currentLine: currentIndex >= 0 ? lines[currentIndex].text : ""

    onKeyChanged: refresh()
    onActiveChanged: refresh()
    Component.onCompleted: refresh()
    Component.onDestruction: cancel()

    function cancel() {
        generation++;
        debounce.stop();
        deadline.stop();
        const previous = request;
        request = null;
        if (previous) previous.abort();
    }
    function apply(value) {
        const parsed = Lyrics.parse(value.syncedLyrics, value.plainLyrics);
        lines = parsed.lines;
        synced = parsed.synced;
        status = value.instrumental ? "instrumental" : (lines.length ? "ready" : "missing");
    }
    function refresh() {
        cancel();
        lines = [];
        synced = false;
        attribution = "";
        status = "idle";
        if (!active || !title) return;
        if (embedded) {
            apply({syncedLyrics: embedded, plainLyrics: embedded});
            attribution = "From your player";
        } else if (artist) {
            status = "loading";
            debounce.start();
        } else status = "missing";
    }
    function fetch() {
        const lookupKey = key;
        if (Lyrics.cache[lookupKey]) {
            apply(Lyrics.cache[lookupKey]);
            attribution = "LRCLIB";
            return;
        }
        const token = generation;
        const xhr = new XMLHttpRequest();
        request = xhr;
        xhr.onreadystatechange = function() {
            if (token !== root.generation || xhr.readyState !== XMLHttpRequest.DONE) return;
            deadline.stop();
            root.request = null;
            if (xhr.status === 404) { root.status = "missing"; return; }
            if (xhr.status !== 200) { root.status = "error"; return; }
            try {
                const value = JSON.parse(xhr.responseText);
                root.apply(value);
                Lyrics.remember(lookupKey, value);
                root.attribution = "LRCLIB";
            } catch (error) { root.status = "error"; }
        };
        let url = endpoint + "?track_name=" + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist);
        if (album) url += "&album_name=" + encodeURIComponent(album);
        if (duration >= 1 && duration <= 3600) url += "&duration=" + encodeURIComponent(duration);
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "Zestify (https://github.com/zetzor/zestify)");
        deadline.start();
        xhr.send();
    }
    property Timer debounce: Timer { interval: 350; onTriggered: root.fetch() }
    property Timer deadline: Timer {
        interval: 10000
        onTriggered: { root.cancel(); root.status = "error"; }
    }
}
