import QtQuick
import Quickshell.Services.Pipewire

Item {
    id: root

    property var theme
    property var screen
    property var player
    property var motion
    property real s: 1
    property real topGap: 8
    property real restWidth: 1000
    property real restHeight: 34
    property string scriptsDir: ""
    property string python: "python3"
    property bool active: false
    property real entry: 0
    property var sourcePill: null
    property var elements: []

    readonly property bool calm: motion && motion.calm
    readonly property alias scene: stage
    readonly property bool animating: entryAnimation.running
    readonly property real restX: screen ? Math.round((screen.width - restWidth) / 2) : 0
    readonly property real restY: topGap
    readonly property var audioSink: Pipewire.defaultAudioSink
    property bool outputAudible: !audioSink || !audioSink.audio
        || (!audioSink.audio.muted && audioSink.audio.volume > 0)

    signal exitRequested()

    visible: entry > 0.001

    onActiveChanged: {
        if (root.active)
            root.open();
        else
            root.close();
    }

    Component.onCompleted: {
        if (root.active)
            root.open();
        else
            root.visible = false;
    }

    function open() {
        if (root.sourcePill)
            root.elements = root.sourcePill.partyElements();
        root.visible = true;
        entryAnimation.stop();
        entryAnimation.from = root.entry;
        entryAnimation.to = 1;
        entryAnimation.duration = root.calm ? 0
            : (root.motion && root.motion.heat ? root.motion.heat + 80 : 1180);
        entryAnimation.easing.type = Easing.Linear;
        entryAnimation.restart();
    }

    function close() {
        if (root.entry <= 0.001) {
            root.visible = false;
            return;
        }
        root.visible = true;
        if (root.sourcePill)
            root.elements = root.sourcePill.partyElements();
        entryAnimation.stop();
        entryAnimation.from = root.entry;
        entryAnimation.to = 0;
        entryAnimation.duration = root.calm ? 0
            : (root.motion ? root.motion.morph + 200 : 620);
        entryAnimation.easing.type = Easing.Linear;
        entryAnimation.restart();
    }

    NumberAnimation {
        id: entryAnimation
        target: root
        property: "entry"
        easing.type: Easing.Linear
        onFinished: {
            if (root.entry <= 0.001)
                root.visible = false;
        }
    }

    VisualiserLevels {
        id: audio
        scriptsDir: root.scriptsDir
        python: root.python
        active: root.active || root.entry > 0.05
        transients: true
    }

    PwObjectTracker {
        objects: root.active || root.entry > 0.05 ? [root.audioSink] : []
    }

    LyricsProvider {
        id: lyricProvider
        player: root.player
        active: root.active && root.entry > 0.25
    }

    // Mpris position advances without notifications while playing. Keep the
    // lyric bindings current even when the regular media views are hidden.
    Timer {
        interval: 500
        repeat: true
        triggeredOnStart: true
        running: lyricProvider.active && root.visible && root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    PartyScene {
        id: stage
        anchors.fill: parent
        theme: root.theme
        s: root.s
        screenWidth: root.screen ? root.screen.width : 1920
        screenHeight: root.screen ? root.screen.height : 1080
        restWidth: root.restWidth
        restHeight: root.restHeight
        restX: root.restX
        restY: root.restY
        entry: root.entry
        elements: root.elements
        pillBackgroundOpacity: root.sourcePill ? root.sourcePill.partyBackgroundOpacity : 1
        player: root.player
        lyrics: lyricProvider
        levels: audio.values
        impactLevels: audio.spectrum
        timestampedAudio: true
        audioFrame: audio.frame
        audioLive: audio.cavaActive
        outputAudible: root.outputAudible
        motion: root.motion
        showParticles: root.active
        onExitRequested: root.exitRequested()
    }
}
