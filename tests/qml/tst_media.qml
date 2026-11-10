import QtQuick
import QtTest
import "../../shell/components"
import "../../shell/lib/lyrics.js" as Lyrics

Item {
    id: fixture
    width: 640
    height: 480
    Theme { id: theme }
    QtObject {
        id: player
        property string trackTitle: "Test track"
        property string trackArtist: "Test artist"
        property string trackAlbum: "Test album"
        property real position: 11
        property bool canSeek: true
        property var metadata: ({"xesam:lyrics": "[00:02.00]First line\n[00:10.00]Second line\n[00:20.00]Third line"})
    }
    QtObject {
        id: players
        property real sought: -1
        function seek(value) { sought = value; }
    }
    LyricsProvider { id: provider; player: player }
    LyricsView {
        id: view
        width: 380
        height: 240
        theme: theme
        provider: provider
        players: players
    }
    AlbumCover { id: cover; x: 400; width: 180; height: 180; theme: theme; ringColor: "#39a2c4" }
    TestCase {
        name: "MediaUI"
        when: windowShown
        function init() {
            provider.active = true;
            provider.player = player;
            player.position = 11;
            player.metadata = {"xesam:lyrics": "[00:02.00]First line\n[00:10.00]Second line\n[00:20.00]Third line"};
            cover.playing = false;
            cover.active = true;
            players.sought = -1;
            wait(30);
        }
        function test_synced_lyrics_follow_playback_and_seeking_back() {
            compare(provider.status, "ready");
            verify(provider.synced);
            compare(provider.currentLine, "Second line");
            player.position = 21;
            compare(provider.currentLine, "Third line");
            player.position = 1;
            compare(provider.currentIndex, -1);
            compare(provider.currentLine, "");
            const list = findChild(view, "lyricsList");
            list.positionViewAtIndex(0, ListView.Beginning);
            wait(30);
            mouseClick(list.itemAtIndex(0));
            compare(players.sought, 2);
        }
        function test_plain_lyrics_and_track_disappearance_clear_old_lines() {
            player.metadata = {lyrics: "First plain line\n\nSecond plain line"};
            compare(provider.status, "ready");
            verify(!provider.synced);
            compare(provider.lines.length, 2);
            provider.player = null;
            compare(provider.status, "idle");
            compare(provider.lines.length, 0);
            provider.player = player;
            provider.active = false;
            compare(provider.lines.length, 0);
        }
        function test_cover_rotation_pauses_and_resumes_and_keeps_ring_color() {
            const ring = findChild(cover, "albumRing");
            compare(String(ring.border.color), "#39a2c4");
            cover.playing = true;
            verify(cover.rotating);
            const before = cover.angle;
            wait(100);
            verify(cover.angle > before);
            cover.playing = false;
            const stopped = cover.angle;
            wait(100);
            compare(cover.angle, stopped);
            cover.playing = true;
            wait(100);
            verify(cover.angle > stopped);
            cover.active = false;
            verify(!cover.rotating);
            const hidden = cover.angle;
            wait(100);
            compare(cover.angle, hidden);
            compare(String(ring.border.color), "#39a2c4");
        }
        function test_lrc_multiple_timestamps_offset_blank_lines_and_plain_fallback() {
            const parsed = Lyrics.parse("[offset:-500]\n[00:02.5][00:12.50]Repeat\n[00:08.000]\n[ar:Artist]", "");
            verify(parsed.synced);
            compare(parsed.lines.length, 3);
            compare(parsed.lines[0].time, 2);
            compare(parsed.lines[1].time, 7.5);
            compare(parsed.lines[1].text, "");
            compare(parsed.lines[2].time, 12);
            compare(Lyrics.indexAt(parsed.lines, 9), 1);
            const plain = Lyrics.parse("[ar:Artist]", "One\r\nTwo");
            verify(!plain.synced);
            compare(plain.lines.length, 2);
        }
    }
}
