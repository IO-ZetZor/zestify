import QtQuick
import QtMultimedia

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
        source: root.source.length > 0 ? "file://" + root.source : ""
        audioOutput: AudioOutput {
            muted: root.muted
        }

        onSourceChanged: {
            root.hasFirstFrame = false;
            root.failed = false;
            root.sync();
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && root.shouldDecode && root.playing)
                play();
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
        if (!root.source.length)
            return;
        if ((root.shouldDecode && root.playing) || !root.hasFirstFrame)
            player.play();
        else
            player.pause();
    }

    Timer {
        interval: 1500
        running: root.source.length > 0 && root.shouldDecode && root.playing && !root.hasFirstFrame
        onTriggered: root.hasFirstFrame = true
    }

    Component.onCompleted: sync()
    onPlayingChanged: sync()
    onHasFirstFrameChanged: sync()
    onShouldDecodeChanged: sync()
}
