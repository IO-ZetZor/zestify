import QtQuick
import Quickshell
import Quickshell.Io
import "../../shell/components"
import "../../shell/surfaces"
import "../../shell/singletons"

ShellRoot {
    id: root
    property int phase: 0
    property int replies: 0
    property int notificationId: 0
    property bool actionReceived: false
    property real scale: 1
    readonly property string outputDir: Quickshell.env("MEDIA_UI_OUTPUT")
    Theme { id: fixtureTheme; shellAccent: "#f1b77b" }
    QtObject {
        id: player
        property string trackTitle: "A little light in the evening"
        property string trackArtist: "The Daydreams"
        property string trackAlbum: "After Hours"
        property string identity: "Test player"
        property url trackArtUrl: Quickshell.env("MEDIA_UI_COVER")
        property bool isPlaying: true
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool canTogglePlaying: true
        property bool canSeek: true
        property bool shuffleSupported: true
        property bool shuffle: false
        property bool loopSupported: true
        property int loopState: 0
        property real position: 43
        property var metadata: ({"mpris:length": 215000000,
            "xesam:lyrics": "[00:00.00]The city slows to a whisper\n[00:25.00]And the streetlights come alive\n[00:40.00]There's a little light in the evening\n[00:55.00]That will lead us home tonight\n[01:10.00]Keep the window open"})
    }
    QtObject {
        id: players
        property var active: player
        property bool isPlaying: player.isPlaying
        function previous() {}
        function next() {}
        function playPause() { player.isPlaying = !player.isPlaying; }
        function seek(value) { player.position = value; }
    }
    QtObject {
        id: networkPlayer
        property string trackTitle: "Network test"
        property string trackArtist: "Test artist"
        property string trackAlbum: "Test album"
        property real position: 12
        property var metadata: ({"mpris:length": 180000000})
    }
    LyricsProvider {
        id: networkLyrics
        player: networkPlayer
        active: false
        endpoint: Quickshell.env("MEDIA_UI_ENDPOINT")
    }
    Window {
        id: preview
        visible: true
        width: 1100 * root.scale
        height: 600 * root.scale
        color: fixtureTheme.surface
        Rectangle { anchors.fill: parent; color: fixtureTheme.surface }
        MediaSurface {
            id: media
            x: 15 * root.scale
            y: 40 * root.scale
            width: 640 * root.scale
            height: 480 * root.scale
            s: root.scale
            theme: fixtureTheme
            players: players
        }
        NotificationsSurface {
            id: inbox
            x: 680 * root.scale
            y: 10 * root.scale
            width: 400 * root.scale
            height: 580 * root.scale
            s: root.scale
            theme: fixtureTheme
        }
    }
    Window {
        id: drawerPreview
        visible: true
        width: 1000 * root.scale
        height: 700 * root.scale
        color: "#323747"
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#40475f" }
                GradientStop { position: 1; color: "#232839" }
            }
        }
        NotificationDrawer {
            id: previewDrawer
            anchors.fill: parent
            theme: fixtureTheme
            s: root.scale
            NotificationsSurface {
                anchors.fill: parent
                theme: fixtureTheme
                s: root.scale
                onCloseRequested: previewDrawer.close()
            }
        }
    }
    Window {
        id: hoverPreview
        visible: true
        width: 900 * root.scale
        height: 300 * root.scale
        color: fixtureTheme.surface
        Rectangle { anchors.fill: parent; color: fixtureTheme.surface }
        MediaCard {
            anchors.fill: parent
            anchors.margins: 20 * root.scale
            theme: fixtureTheme
            players: players
            s: root.scale
        }
    }
    Process {
        id: monitor
        command: ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications"]
        running: true
        stdout: SplitParser { onRead: line => { if (line.indexOf("ActionInvoked") >= 0 && line.indexOf("reply") >= 0) root.actionReceived = true; } }
    }
    Process {
        id: sender
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/uint32 (\d+)/);
                if (match) { root.notificationId = Number(match[1]); root.replies++; }
            }
        }
    }
    function send(summary, replaceId) {
        sender.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
            "Messages", String(replaceId), "", summary, "A real notification with actions, retained in your history.",
            "['default', 'Open', 'reply', 'Reply']", "{'urgency': <byte 1>, 'resident': <true>}", "0"];
        sender.running = true;
    }
    function check(condition, message) { if (!condition) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const match = find(child, name);
            if (match) return match;
        }
        return null;
    }
    function capture(label, next) {
        preview.contentItem.grabToImage(result => {
            root.check(result.saveToFile(root.outputDir + "/media-inbox-" + label + ".png"), "Couldn't save preview");
            hoverPreview.contentItem.grabToImage(hover => {
                root.check(hover.saveToFile(root.outputDir + "/media-hover-" + label + ".png"), "Couldn't save hover preview");
                drawerPreview.contentItem.grabToImage(drawer => {
                    root.check(drawer.saveToFile(root.outputDir + "/drawer-" + label + ".png"), "Couldn't save drawer preview");
                    root.phase = next;
                    tick.start();
                });
            });
        });
    }
    Timer {
        id: tick
        interval: 250
        running: true
        onTriggered: {
            try {
                const entry = Notifications.history.find(item => item.id === root.notificationId);
                if (root.phase === 0) {
                    previewDrawer.open();
                    Notifications.notify("Download complete", "Your playlist is ready to play.", "normal", "Music", 0);
                    Notifications.notify("Battery is running low", "Connect your charger when you can.", "critical", "System", 0);
                    root.send("Original notification", 0);
                    root.phase = 1;
                } else if (root.phase === 1 && root.replies >= 1) {
                    root.check(entry && entry.notification && entry.notification.tracked, "Notification was not retained");
                    root.check(entry.expires === 0 && entry.notification.actions.length === 2, "Persistent timeout/actions lost");
                    root.send("Updated notification", root.notificationId);
                    root.phase = 2;
                } else if (root.phase === 2 && root.replies >= 2) {
                    root.check(entry.summary === "Updated notification", "Replacement text is stale");
                    root.check(Notifications.history.filter(item => item.id === root.notificationId).length === 1, "Replacement duplicated history");
                    const list = root.find(media, "lyricsList");
                    root.check(list && list.currentIndex === 2, "Synced lyrics not integrated into media surface");
                    root.check(Math.abs(media.trackLength - 215) < 0.01, "Track duration not integrated");
                    const current = list.itemAtIndex(list.currentIndex);
                    const point = current.mapToItem(list, 0, 0);
                    root.check(point.y >= -1 && point.y + current.height <= list.height + 1, "Highlighted lyric is clipped");
                    root.capture("dark", 3);
                    return;
                } else if (root.phase === 3) {
                    root.scale = 1.25;
                    fixtureTheme.mode = "light";
                    root.phase = 4;
                } else if (root.phase === 4) {
                    root.capture("light-scaled", 5);
                    return;
                } else if (root.phase === 5) {
                    Notifications.invokeAction(root.notificationId, "reply");
                    networkLyrics.active = true;
                    root.phase = 6;
                } else if (root.phase === 6 && networkLyrics.status === "ready") {
                    root.check(root.actionReceived, "Notification action did not reach D-Bus");
                    root.check(networkLyrics.currentLine === "Network lyric", "HTTP lyrics were not parsed/synced");
                    Notifications.expirePopup(root.notificationId);
                    root.check(!Notifications.history.find(item => item.id === root.notificationId).notification,
                        "Closed notification retained stale actions");
                    networkPlayer.trackTitle = "Missing";
                    root.phase = 7;
                } else if (root.phase === 7 && networkLyrics.status === "missing") {
                    networkPlayer.trackTitle = "Bad JSON";
                    root.phase = 8;
                } else if (root.phase === 8 && networkLyrics.status === "error") {
                    networkPlayer.trackTitle = "Slow old";
                    root.phase = 9;
                } else if (root.phase === 9) {
                    // Let the debounce start the old request, then replace it.
                    tick.interval = 500;
                    root.phase = 10;
                } else if (root.phase === 10) {
                    networkPlayer.trackTitle = "New song";
                    root.phase = 11;
                } else if (root.phase === 11 && networkLyrics.status === "ready") {
                    root.check(networkLyrics.currentLine === "New lyric", "Stale HTTP response overwrote current track");
                    networkLyrics.active = false;
                    root.check(networkLyrics.lines.length === 0 && !networkLyrics.request, "Hidden lyrics request not cancelled");
                    root.scale = 1;
                    fixtureTheme.mode = "dark";
                    preview.width = 780;
                    media.width = 340;
                    inbox.x = 365;
                    drawerPreview.width = 340;
                    players.active = null;
                    Notifications.clear();
                    root.phase = 12;
                } else if (root.phase === 12) {
                    root.capture("empty-narrow", 13);
                    return;
                } else if (root.phase === 13) {
                    console.log("MEDIA UI PASS: native media/inbox views, real D-Bus replacement/actions/closure, HTTP lyrics/sync/missing/error/cancellation, dark/light/scaled/empty previews");
                    Qt.quit();
                    return;
                }
                tick.start();
            } catch (error) {
                console.error("MEDIA UI FAIL: " + error);
                Qt.quit();
            }
        }
    }
}
