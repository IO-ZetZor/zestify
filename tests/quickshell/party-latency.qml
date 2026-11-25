import QtQuick
import Quickshell
import "../../shell/components"

ShellRoot {
    id: root
    property var pending: []
    property int lastImpact: 0
    Theme { id: theme }
    QtObject { id: player; property bool isPlaying: true }
    VisualiserLevels {
        id: audio
        scriptsDir: Quickshell.env("PARTY_LATENCY_SCRIPTS")
        transients: true
        // Use the production parser, normalization and process lifecycle.
        python: Quickshell.env("PARTY_LATENCY_PYTHON")
        onFrameChanged: {
            if (!frame)
                return;
            const now = Date.now();
            scene.receiveAudioFrame(frame, now);
            if (scene.impact.hit && scene.impact.sequence !== root.lastImpact) {
                root.lastImpact = scene.impact.sequence;
                root.pending.push({receivedAt: frame.receivedAt, emittedAt: frame.emittedAt,
                                   detectedAt: now, sequence: frame.sequence});
            }
        }
    }
    Window {
        visible: true
        width: 640
        height: 480
        PartyScene {
            id: scene
            anchors.fill: parent
            screenWidth: 640
            screenHeight: 480
            theme: theme
            player: player
            entry: 1
            levels: audio.values
            audioLive: audio.cavaActive
            timestampedAudio: true
        }
        onFrameSwapped: {
            while (root.pending.length) {
                const event = root.pending.shift();
                event.presentedAt = Date.now();
                console.log("PARTY LATENCY EVENT " + JSON.stringify(event));
            }
        }
    }
    Timer { interval: 9500; running: true; onTriggered: Qt.quit() }
}
