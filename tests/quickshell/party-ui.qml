import QtQuick
import Quickshell
import Quickshell.Io
import "../../shell/components"
import "../../shell/singletons"
import "../../shell/lib/visualiser.js" as Visualiser

ShellRoot {
    id: root

    property int phase: 0
    property real entry: 0
    property var liveSpectrum: Array(32).fill(0)
    property var livePacket: null
    property bool packetReplay: false
    property var displaySpectrum: []
    property real displayReference: 0.24
    property int frameNumber: 0
    property int returnFrameNumber: 0
    readonly property bool profileFormation: Quickshell.env("PARTY_UI_PROFILE") === "1"
    property var formationIntervals: []
    property double lastFormationFrame: 0
    property int profileRuns: 0
    property int quietKickCount: 0
    property int rapidKickCount: 0
    property int crescendoFrame: 0
    property real largestBuildup: 0
    property int pausedPositionUpdates: 0
    property int closedPositionUpdates: 0
    readonly property string outputDir: Quickshell.env("PARTY_UI_OUTPUT")
    property var audioTrace: null
    property int audioSegment: 0
    property int audioFrame: 0
    property int audioHits: 0
    property bool audioCaptured: false
    property int audioPending: 0
    readonly property var audioSegments: [0.08, 0.145, 0.43, 0.57, 0.65, 0.78, 0.88, 0.96]

    FileView {
        id: audioFile
        path: Quickshell.env("PARTY_UI_AUDIO")
        blockLoading: true
        printErrors: false
        onLoaded: root.audioTrace = JSON.parse(text())
    }

    Theme {
        id: fixtureTheme
        scheme: ({ colours: { primary: "#f1b77b", onPrimary: "#20140c" } })
    }

    QtObject {
        id: player
        property string trackTitle: "A little light in the evening"
        property string trackArtist: "The Daydreams"
        property string trackAlbum: "After Hours"
        property string identity: "Test player"
        property url trackArtUrl: Quickshell.env("PARTY_UI_COVER")
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
        // Model Mpris: time can advance without a position notification.
        property real pendingPosition: 43
        property int positionUpdates: 0
        property var metadata: ({
            "xesam:lyrics": "[00:00.00]The city slows to a whisper\n[00:25.00]And the streetlights come alive\n[00:40.00]There's a little light in the evening\n[00:55.00]That will lead us home tonight\n[01:10.00]Keep the window open"
        })
        onPositionChanged: {
            positionUpdates++;
            if (position !== pendingPosition)
                position = pendingPosition;
        }
    }

    QtObject {
        id: players
        property var active: player
        property bool isPlaying: player.isPlaying
        function previous() {}
        function next() {}
        function playPause() { player.isPlaying = !player.isPlaying; }
        function seek(value) {
            player.pendingPosition = value;
            player.position = value;
        }
    }

    QtObject {
        id: fixtureMotion
        property bool calm: false
        property int fast: 140
        property int standard: 300
        property int morph: 420
        property int shapeshift: 520
        property int heat: 1100
        property var morphCurve: [0.16, 1, 0.3, 1, 1, 1]
    }

    readonly property var spectrum: [
        0.92, 0.78, 0.63, 0.51, 0.44, 0.38, 0.33, 0.28,
        0.24, 0.2, 0.17, 0.15, 0.13, 0.12, 0.11, 0.1,
        0.1, 0.11, 0.13, 0.16, 0.2, 0.25, 0.31, 0.38,
        0.46, 0.54, 0.62, 0.7, 0.76, 0.82, 0.88, 0.94
    ]

    Window {
        id: preview
        visible: true
        width: 1600
        height: 1000
        color: "#15151b"
        onFrameSwapped: {
            if (root.profileFormation && formation.running) {
                const now = Date.now();
                if (root.lastFormationFrame)
                    root.formationIntervals.push(now - root.lastFormationFrame);
                root.lastFormationFrame = now;
            } else {
                root.lastFormationFrame = 0;
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#4a516f" }
                GradientStop { position: 1; color: "#20232f" }
            }
        }

        Pill {
            id: restingPill
            x: (preview.width - width) / 2
            y: 8
            pinned: true
            screen: null
            theme: fixtureTheme
            players: players
            motion: fixtureMotion
            windowObject: preview
            partyVisible: party.active || party.animating || party.entry > 0.001
        }

        PartyScene {
            id: scene
            anchors.fill: parent
            theme: fixtureTheme
            s: 1
            screenWidth: preview.width
            screenHeight: preview.height
            restWidth: restingPill.restWidth
            restHeight: 34
            restX: (preview.width - restWidth) / 2
            restY: 8
            entry: root.entry
            elements: party.elements
            player: player
            lyrics: party.scene.lyrics
            levels: root.packetReplay ? root.displaySpectrum : root.spectrum
            impactLevels: root.liveSpectrum
            timestampedAudio: root.packetReplay
            audioFrame: root.livePacket
            motion: fixtureMotion
        }
    }

    QtObject {
        id: fixtureScreen
        property string name: "fixture-screen"
        property int width: 1600
        property int height: 1000
    }

    PartyStage {
        id: party
        // Attach to a window so visibility matches the real PartyWindow.
        // The preview scene renders this stage's lyrics with fixture audio.
        parent: preview.contentItem
        opacity: 0
        width: 1600
        height: 1000
        theme: fixtureTheme
        screen: fixtureScreen
        player: player
        motion: fixtureMotion
        restWidth: restingPill.restWidth
        restHeight: 34
        sourcePill: restingPill
        topGap: 8
        scriptsDir: ""
        active: ShellState.partyOwner === fixtureScreen.name
    }

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    function find(item, name) {
        if (item.objectName === name)
            return item;
        for (const child of item.children || []) {
            const match = find(child, name);
            if (match)
                return match;
        }
        return null;
    }

    function capture(label, next) {
        preview.contentItem.grabToImage(result => {
            root.check(result.saveToFile(root.outputDir + "/party-" + label + ".png"),
                       "Couldn't save " + label + " preview");
            root.phase = next;
            tick.start();
        });
    }

    function captureAudio() {
        const label = root.audioSegment;
        root.audioCaptured = true;
        root.audioPending++;
        preview.contentItem.grabToImage(result => {
            if (!result.saveToFile(root.outputDir + "/party-audio-" + label + ".png")) {
                console.error("PARTY UI FAIL: couldn't save audio replay frame");
                Qt.quit();
            }
            root.audioPending--;
        });
    }

    Timer {
        id: audioReplay
        interval: 17
        repeat: true
        onTriggered: {
            try {
                const frames = root.audioTrace.frames;
                const length = Math.min(120, frames.length);
                const start = Math.floor((frames.length - length) * root.audioSegments[root.audioSegment]);
                root.liveSpectrum = frames[start + root.audioFrame];
                if (root.audioTrace.fixedGain) {
                    const index = start + root.audioFrame;
                    const sourceTime = root.audioTrace.times ? root.audioTrace.times[index] : index * root.audioTrace.dt;
                    const display = Visualiser.displayLevels(root.displayReference, root.liveSpectrum, root.audioTrace.dt);
                    root.displayReference = display.reference;
                    root.displaySpectrum = display.values;
                    root.livePacket = {version: 1, fixedGain: true, levels: root.liveSpectrum,
                        sequence: index, time: sourceTime, emittedAt: Date.now()};
                }
                root.check(Number.isFinite(scene.impactZoom) && scene.impactZoom <= 1.335,
                    "real audio camera must remain finite and bounded");
                root.check(Math.abs(scene.shakeX) <= scene.coverSize * 0.012,
                    "real audio recoil must stay bounded");
                root.audioHits += scene.impact.hit ? 1 : 0;
                if (!root.audioCaptured && root.audioFrame >= 30 && scene.impact.envelope > 0.35)
                    root.captureAudio();
                if (++root.audioFrame === length) {
                    if (!root.audioCaptured)
                        root.captureAudio();
                    root.audioFrame = 0;
                    root.audioCaptured = false;
                    root.liveSpectrum = Array(32).fill(0);
                    scene.resetMotion();
                    if (++root.audioSegment === root.audioSegments.length) {
                        stop();
                        audioFinish.start();
                    }
                }
            } catch (error) {
                console.error("PARTY UI FAIL: " + error);
                Qt.quit();
            }
        }
    }

    Timer {
        id: audioFinish
        interval: 120
        repeat: true
        onTriggered: {
            if (root.audioPending > 0)
                return;
            console.log("PARTY UI PASS: real-track rendered replay, eight passages, "
                + root.audioHits + " onsets, bounded zoom/recoil, quiet/dense/transition previews");
            Qt.quit();
        }
    }

    NumberAnimation {
        id: formation
        target: root
        property: "entry"
        from: 0
        to: 1
        duration: 1180
        easing.type: Easing.Linear
    }

    Timer {
        interval: 40
        repeat: true
        running: formation.running && !root.profileFormation
        onTriggered: {
            const number = root.frameNumber++;
            preview.contentItem.grabToImage(result => {
                root.check(result.saveToFile(root.outputDir + "/formation-"
                    + String(number).padStart(3, "0") + ".png"), "Couldn't save animation frame");
            });
        }
    }

    Timer {
        interval: 40
        repeat: true
        running: !party.active && party.animating && root.phase >= 14 && root.phase <= 27
        onTriggered: {
            const number = root.returnFrameNumber++;
            preview.contentItem.grabToImage(result => {
                root.check(result.saveToFile(root.outputDir + "/return-"
                    + String(number).padStart(3, "0") + ".png"), "Couldn't save return frame");
            });
        }
    }

    Timer {
        id: quietKickRelease
        interval: 40
        onTriggered: root.liveSpectrum = Array(32).fill(0)
    }

    Timer {
        id: quietKicks
        interval: 128
        repeat: true
        onTriggered: {
            try {
                const bass = Array(32).fill(0);
                bass[root.quietKickCount % 2 ? 11 : 20] = 0.5;
                root.liveSpectrum = bass;
                root.check(scene.impact.hit && scene.impact.strength < 0.4 && scene.impactZoom < 1.13,
                    "quiet, narrow-band kick " + root.quietKickCount + " must drive gentle camera motion");
                quietKickRelease.restart();
                if (++root.quietKickCount === 8) {
                    stop();
                    root.capture("soft-impact", 22);
                }
            } catch (error) {
                console.error("PARTY UI FAIL: " + error);
                Qt.quit();
            }
        }
    }

    Timer {
        id: rapidKickRelease
        interval: 20
        onTriggered: root.liveSpectrum = Array(32).fill(0)
    }

    Timer {
        id: rapidKicks
        interval: 64
        repeat: true
        onTriggered: {
            try {
                root.liveSpectrum = Array(32).fill(1);
                root.check(scene.impact.hit, "rapid kick " + root.rapidKickCount
                    + " must land (age=" + scene.impact.age + ", cooldown="
                    + scene.impact.cooldown + ", interval=" + scene.impact.interval + ")");
                root.check(scene.impactZoom <= 1.34, "rapid beats must not stack zoom");
                rapidKickRelease.restart();
                if (++root.rapidKickCount === 12) {
                    root.check(scene.impact.release < 50 && scene.impact.strength < 0.7,
                        "fast rolls should shorten and soften motion");
                    stop();
                    root.capture("rapid-impact", 23);
                }
            } catch (error) {
                console.error("PARTY UI FAIL: " + error);
                Qt.quit();
            }
        }
    }

    Timer {
        id: crescendo
        interval: 16
        repeat: true
        onTriggered: {
            try {
                root.liveSpectrum = Array(32).fill(++root.crescendoFrame / 160);
                root.largestBuildup = Math.max(root.largestBuildup, scene.impact.buildup);
                root.check(scene.impactZoom < 1.14, "a smooth swell must not become a drum roll");
                if (root.crescendoFrame === 160) {
                    root.check(root.largestBuildup > 0.3, "a crescendo should build camera tension");
                    stop();
                    root.capture("crescendo", 24);
                }
            } catch (error) {
                console.error("PARTY UI FAIL: " + error);
                Qt.quit();
            }
        }
    }

    Timer {
        id: tick
        interval: 260
        running: true
        onTriggered: {
            try {
                if (root.phase === 0) {
                    root.check(!party.active, "party should start closed");
                    root.check(ShellState.partyOwner === "", "party owner should start empty");
                    ShellState.toggleParty(fixtureScreen.name);
                    root.check(party.active, "toggling party should activate the window");
                    const clockSpec = party.elements.find(spec => spec.text === Qt.formatDateTime(new Date(), "HH:mm"));
                    root.check(clockSpec && Math.abs(clockSpec.x - 0.5) < 0.001
                        && party.elements.every(spec => spec.x >= 0 && spec.x <= 1),
                        "entry from the expanded pill must use resting slot positions: "
                        + JSON.stringify({clock: clockSpec, elements: party.elements,
                            width: restingPill.width, restWidth: restingPill.restWidth}));
                    restingPill.pinned = false;
                    formation.start();
                    root.phase = 1;
                } else if (root.phase === 1) {
                    if (root.profileFormation) {
                        if (formation.running) {
                            tick.start();
                            return;
                        }
                        if (++root.profileRuns < 4) {
                            root.entry = 0;
                            root.lastFormationFrame = 0;
                            formation.start();
                            tick.start();
                            return;
                        }
                        const times = root.formationIntervals.slice().sort((a, b) => a - b);
                        root.check(times.length > 0, "entry profiling must render frames");
                        console.log("PARTY PROFILE " + JSON.stringify({frames: times.length,
                            medianMs: times[Math.floor(times.length / 2)],
                            p95Ms: times[Math.floor(times.length * 0.95)],
                            maximumMs: times[times.length - 1],
                            framesOver25Ms: times.filter(time => time > 25).length}));
                        console.log("PARTY UI PASS: formation profiling");
                        Qt.quit();
                        return;
                    }
                    const ghostPill = find(scene, "partyGhostPill");
                    root.check(ghostPill && ghostPill.opacity > 0.1,
                               "morphing pill body should be visible early");
                    root.check(find(scene, "partyFallingIcons").count >= 9, "falling icons missing");
                    root.capture("start", 2);
                    return;
                } else if (root.phase === 2) {
                    root.capture("entry", 3);
                    return;
                } else if (root.phase === 3) {
                    root.capture("landing", 4);
                    return;
                } else if (root.phase === 4) {
                    if (formation.running) {
                        tick.start();
                        return;
                    }
                    root.phase = 5;
                } else if (root.phase === 5) {
                    root.check(restingPill.opacity === 0 && !restingPill.visible,
                        "real pill must stay hidden in party mode");
                    root.check(party.elements.some(spec => spec.rem)
                        && party.elements.filter(spec => spec.native).length === 9,
                        "reconstruction must use the live launcher and all nine workspace slots");
                    root.check(scene.hasLyrics, "fixture lyrics should be available");
                    root.check(scene.currentLyric === "There's a little light in the evening",
                        "party stage must supply synchronized lyrics from the player");
                    root.check(find(scene, "partyLyrics").opacity > 0.99,
                               "lyrics should be revealed when settled");
                    root.check(find(scene, "partyTopBars") && find(scene, "partyBottomBars")
                        && find(scene, "partyLeftBars") && find(scene, "partyRightBars"),
                        "all four edge bars required");
                    root.check(find(scene, "partyGhostPill").opacity < 0.01,
                               "morphing pill body should be gone when settled");
                    root.capture("settled", 16);
                    return;
                } else if (root.phase === 16) {
                    player.pendingPosition = 58;
                    root.check(player.position === 43,
                        "advancing the Mpris clock must wait for a position notification");
                    tick.interval = 600;
                    root.phase = 17;
                } else if (root.phase === 17) {
                    root.check(scene.lyricIndex === 3
                        && scene.previousLyric === "There's a little light in the evening"
                        && scene.currentLyric === "That will lead us home tonight"
                        && scene.nextLyric === "Keep the window open",
                        "party lyrics must advance from position polling without a media view");
                    root.capture("lyrics-advanced", 18);
                    return;
                } else if (root.phase === 18) {
                    player.isPlaying = false;
                    players.seek(12);
                    root.check(scene.currentLyric === "The city slows to a whisper",
                        "seeking backwards while paused must update the lyric");
                    root.pausedPositionUpdates = player.positionUpdates;
                    root.phase = 19;
                } else if (root.phase === 19) {
                    root.check(player.positionUpdates === root.pausedPositionUpdates,
                        "paused party playback must stop position polling");
                    player.pendingPosition = 31;
                    player.isPlaying = true;
                    root.phase = 21;
                } else if (root.phase === 21) {
                    root.check(scene.currentLyric === "And the streetlights come alive",
                        "resuming playback must restart lyric updates");
                    players.seek(43);
                    tick.interval = 260;
                    root.phase = 6;
                } else if (root.phase === 6) {
                    const bass = Array(32).fill(0);
                    bass[11] = bass[12] = bass[13] = bass[14] = bass[15] = 1;
                    bass[16] = bass[17] = bass[18] = bass[19] = bass[20] = 1;
                    root.liveSpectrum = bass;
                    root.check(scene.impactZoom > 1.29,
                        "live bass must zoom immediately on receipt of the frame");
                    tick.interval = 24;
                    root.phase = 7;
                } else if (root.phase === 7) {
                    root.check(scene.impactZoom > 1.15, "bass should punch the camera in");
                    root.check(Math.abs(scene.blurZoom) > 0.001,
                        "moving zoom should have a radial trail");
                    root.capture("impact", 8);
                    return;
                } else if (root.phase === 8) {
                    root.liveSpectrum = Array(32).fill(0);
                    tick.interval = 1500;
                    root.phase = 9;
                } else if (root.phase === 9) {
                    root.check(scene.impactZoom === 1, "zoom must release fully at rest");
                    root.check(Math.abs(scene.blurZoom) < 0.0001, "resting cover must be sharp");
                    root.capture("release", 20);
                    return;
                } else if (root.phase === 20) {
                    tick.interval = 260;
                    quietKicks.start();
                    return;
                } else if (root.phase === 10) {
                    player.isPlaying = false;
                    player.metadata = ({});
                    player.trackTitle = "";
                    preview.width = 900;
                    preview.height = 650;
                    tick.interval = 260;
                    root.phase = 11;
                } else if (root.phase === 22) {
                    rapidKicks.start();
                    return;
                } else if (root.phase === 23) {
                    root.liveSpectrum = Array(32).fill(0);
                    scene.resetMotion();
                    crescendo.start();
                    return;
                } else if (root.phase === 24) {
                    root.liveSpectrum = Array(32).fill(0);
                    tick.interval = 80;
                    root.phase = 25;
                } else if (root.phase === 25) {
                    root.liveSpectrum = Array(32).fill(1);
                    root.check(scene.impact.hit && scene.impactZoom > 1.29,
                        "a drop after a crescendo should land heavily");
                    root.capture("drop", 26);
                    return;
                } else if (root.phase === 26) {
                    scene.outputAudible = false;
                    root.check(scene.impactZoom === 1 && scene.blurZoom === 0
                        && scene.shakeX === 0 && scene.shakeY === 0,
                        "muting must clear camera motion immediately");
                    root.liveSpectrum = Array(32).fill(0.8);
                    root.check(!scene.impact.hit, "muted live frames must not punch");
                    scene.outputAudible = true;
                    player.trackTitle = "The next song";
                    root.check(scene.impact.intervals.length === 0 && scene.impactZoom === 1,
                        "track changes must reset motion history");
                    root.capture("muted-reset", 10);
                    tick.interval = 260;
                    return;
                } else if (root.phase === 11) {
                    root.check(!scene.hasLyrics && find(scene, "partyLyrics").opacity === 0,
                        "missing lyrics should disappear");
                    root.check(scene.impactZoom === 1, "paused playback must not zoom");
                    root.check(scene.coverTargetY + scene.coverSize < preview.height,
                        "cover should fit a smaller display");
                    root.capture("compact", 12);
                    return;
                } else if (root.phase === 12) {
                    preview.width = 1600;
                    preview.height = 1000;
                    root.entry = 0.55;
                    scene.showParticles = false;
                    root.phase = 13;
                } else if (root.phase === 13) {
                    root.capture("exit", 14);
                    return;
                } else if (root.phase === 14) {
                    player.isPlaying = true;
                    root.entry = Qt.binding(() => party.entry);
                    ShellState.closeParty(fixtureScreen.name);
                    root.check(!party.active, "party should close");
                    root.check(party.animating && restingPill.partyOn && restingPill.opacity === 0,
                        "closing party mode must hold the real pill until the return finishes");
                    root.check(party.elements.filter(spec => spec.background !== undefined && !spec.text).length === 12,
                        "playback resumed before exit must reconstruct all visualiser bars");
                    root.closedPositionUpdates = player.positionUpdates;
                    root.phase = 27;
                    tick.interval = 300;
                } else if (root.phase === 27) {
                    root.check(party.animating && party.entry > 0 && restingPill.opacity === 0,
                        "real pill contents must not appear midway through the return");
                    root.check(find(scene, "partyFallingLayer").visible,
                        "returning elements must visibly rebuild the pill");
                    root.phase = 15;
                    tick.interval = 600;
                    root.capture("return", 15);
                    return;
                } else if (root.phase === 15) {
                    root.check(!party.animating && !party.visible, "exit must release the overlay");
                    root.check(!restingPill.partyOn && restingPill.opacity === 1 && restingPill.visible,
                        "real pill must reappear after every element has returned");
                    for (const spec of party.elements) {
                        const item = find(restingPill, spec.key);
                        root.check(item !== null, "reconstructed element must have a live counterpart");
                        const center = item.mapToItem(restingPill, item.width / 2, item.height / 2);
                        root.check(Math.abs(center.x - spec.x * restingPill.restWidth) <= 1
                            && Math.abs(center.y - spec.y * restingPill.restHeight) <= 1,
                            "reconstruction must meet the live slot without jumping: " + spec.key);
                    }
                    root.check(player.positionUpdates === root.closedPositionUpdates,
                        "closing party mode must stop position polling");
                    root.entry = 0;
                    root.capture("restored", 28);
                    return;
                } else if (root.phase === 28) {
                    ShellState.toggleParty(fixtureScreen.name);
                    root.phase = 29;
                    tick.interval = 220;
                } else if (root.phase === 29) {
                    root.check(party.animating && restingPill.opacity === 0,
                        "re-entering must hide the pill");
                    ShellState.closeParty(fixtureScreen.name);
                    root.check(party.animating && restingPill.partyOn,
                        "interrupting entry must hold the pill during return");
                    root.phase = 30;
                    tick.interval = 200;
                } else if (root.phase === 30) {
                    root.check(party.animating && restingPill.opacity === 0,
                        "interrupted entry must not reveal contents during return");
                    ShellState.toggleParty(fixtureScreen.name);
                    root.check(party.animating && restingPill.partyOn,
                        "reversing the return must keep the pill hidden");
                    root.phase = 31;
                    tick.interval = 1250;
                } else if (root.phase === 31) {
                    root.check(!party.animating && party.entry === 1 && restingPill.opacity === 0,
                        "reversed entry must settle with the pill hidden");
                    fixtureMotion.calm = true;
                    ShellState.closeParty(fixtureScreen.name);
                    root.phase = 32;
                    tick.interval = 200;
                } else if (root.phase === 32) {
                    root.check(!party.animating && !party.visible && restingPill.opacity === 1,
                        "reduced-motion exit must restore the pill without a lingering hold");
                    fixtureMotion.calm = false;
                    console.log("PARTY UI PASS: animated formation, falling icons, smooth cover, live lyrics/polling/seek/pause/resume, four edges, proportional bass zoom/shake/blur/release, eight quiet 128ms kicks, twelve 64ms kicks, crescendo/drop, mute/track reset, pause, compact display, exit/restoration timing, interrupted entry/return, reduced-motion exit");
                    if (audioFile.path.length > 0) {
                        root.check(root.audioTrace && root.audioTrace.frames.length > 0,
                            "audio trace must contain live spectrum frames");
                        root.entry = 1;
                        scene.showParticles = true;
                        scene.outputAudible = true;
                        player.isPlaying = true;
                        player.trackTitle = root.audioTrace.source;
                        scene.resetMotion();
                        root.packetReplay = root.audioTrace.fixedGain === true;
                        audioReplay.start();
                        return;
                    }
                    Qt.quit();
                    return;
                }
                tick.start();
            } catch (error) {
                console.error("PARTY UI FAIL: " + error);
                Qt.quit();
            }
        }
    }
}
