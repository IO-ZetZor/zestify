import QtQuick
import QtMultimedia
import "../lib/wallpapers.js" as WallpapersLib

Item {
    id: root

    property string source: ""
    property bool playing: true
    property bool shouldDecode: true
    property bool muted: true
    property bool hasFirstFrame: false
    property bool failed: false

    readonly property alias player: player

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    MediaPlayer {
        id: player
        videoOutput: output
        loops: MediaPlayer.Infinite
        playbackRate: 1
        source: WallpapersLib.localUrl(root.source)
        audioOutput: AudioOutput {
            muted: root.muted
        }

        onSourceChanged: {
            root.hasFirstFrame = false;
            root.failed = false;
            root.sync();
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia)
                root.sync();
        }
        onPositionChanged: {
            if (!root.hasFirstFrame && position > 0)
                root.hasFirstFrame = true;
        }
        onErrorOccurred: function(error, errorString) {
            console.warn("zestify: video wallpaper error:", errorString);
            root.failed = true;
            root.hasFirstFrame = true;
        }
    }

    function sync() {
        if (!root.source.length || root.failed)
            return;
        if ((root.shouldDecode && root.playing) || !root.hasFirstFrame)
            player.play();
        else
            player.pause();
    }

    Timer {
        interval: 1500
        running: root.source.length > 0 && !root.hasFirstFrame
            && (player.mediaStatus === MediaPlayer.LoadedMedia
                || player.mediaStatus === MediaPlayer.BufferingMedia
                || player.mediaStatus === MediaPlayer.BufferedMedia)
        onTriggered: root.hasFirstFrame = true
    }

    Component.onCompleted: sync()
    onPlayingChanged: sync()
    onHasFirstFrameChanged: sync()
    onShouldDecodeChanged: sync()
}
