import QtQuick
import QtMultimedia

Item {
    id: root
    property url source
    property bool playing: true
    property real speed: 1
    property string fit: "crop"
    property int frames: 0
    property string mediaError: ""
    readonly property real position: player.position

    function sync() {
        if (source.toString().length === 0 || mediaError.length > 0) return;
        // Decode one frame even when initially paused, then retain it.
        if (playing || frames === 0) player.play();
        else player.pause();
    }
    VideoOutput {
        id: output
        anchors.fill: parent
        visible: root.frames > 0 && root.mediaError.length === 0
        fillMode: root.fit === "fit" ? VideoOutput.PreserveAspectFit
            : root.fit === "stretch" ? VideoOutput.Stretch : VideoOutput.PreserveAspectCrop
    }
    Connections {
        target: output.videoSink
        function onVideoFrameChanged() {
            // QVideoFrame's isValid() is not exposed to QML. The sink's
            // videoSize is empty for an invalid frame and is QML-readable.
            if (output.videoSink.videoSize.width <= 0 || output.videoSink.videoSize.height <= 0) return;
            root.frames++;
            if (!root.playing) player.pause();
        }
    }
    MediaPlayer {
        id: player
        objectName: "wallpaperPlayer"
        source: root.source
        videoOutput: output
        // No audio output is attached; login wallpaper never plays sound.
        loops: MediaPlayer.Infinite
        playbackRate: root.speed
        onSourceChanged: { root.frames = 0; root.mediaError = ""; root.sync(); }
        onMediaStatusChanged: { if (mediaStatus === MediaPlayer.LoadedMedia) root.sync(); }
        onErrorOccurred: function(error, errorString) {
            root.mediaError = errorString;
            console.warn("zestify-greeter: video wallpaper:", errorString);
        }
    }
    onPlayingChanged: sync()
    Component.onCompleted: sync()
}
