pragma ComponentBehavior: Bound

import QtQuick
import "../lib/party.js" as Party

// Pure party-mode visuals. Kept free of Quickshell imports so the morph and
// lyric layout can be exercised with qmltestrunner. Entry is normalized time.
Item {
    id: root

    property var theme
    property real s: 1
    property real screenWidth: 1920
    property real screenHeight: 1080
    property real restWidth: 1000
    property real restHeight: 34
    property real restX: Math.round((screenWidth - restWidth) / 2)
    property real restY: 8
    property real entry: 0
    property var player: null
    property var lyrics: null
    property var levels: []
    property var impactLevels: levels
    property bool timestampedAudio: false
    property var audioFrame: null
    property bool audioLive: true
    property bool outputAudible: true
    property real bassThreshold: 0.62
    readonly property bool calm: !!(motion && motion.calm)
    property var motion: null
    property bool showParticles: true
    property var elements: []
    property real pillBackgroundOpacity: 1

    signal exitRequested()

    readonly property real coverSize: Math.round(Math.min(screenWidth * 0.46,
                                                          screenHeight * 0.56))
    readonly property real gap: 28 * s
    readonly property bool hasLyrics: !!(lyrics
        && lyrics.status === "ready"
        && lyrics.lines
        && lyrics.lines.length > 0)
    readonly property real lyricsBlockHeight: hasLyrics ? 150 * s : 0
    readonly property real columnHeight: coverSize
        + (hasLyrics ? gap + lyricsBlockHeight : 0)
    readonly property real coverTargetX: Math.round((screenWidth - coverSize) / 2)
    readonly property real coverTargetY: Math.max(restY + restHeight + 40 * s,
        Math.round((screenHeight - columnHeight) / 2 + 8 * s))
    readonly property var pillRect: ({
        x: Math.round(restX), y: Math.round(restY),
        width: Math.round(restWidth), height: Math.round(restHeight)
    })
    readonly property var coverTargetRect: ({
        x: coverTargetX, y: coverTargetY,
        width: coverSize, height: coverSize
    })
    readonly property var coverBox: Party.formationRect(entry, pillRect, coverTargetRect)

    readonly property real coverReveal: Party.smooth(Party.phase(entry, 0.16, 0.48))
    readonly property real barsReveal: Party.smooth(Party.phase(entry, 0.30, 0.82))
    readonly property real lyricsReveal: hasLyrics ? Party.smooth(Party.phase(entry, 0.76, 1)) : 0
    readonly property real backdropOpacity: Party.clamp01(entry * 4.5)

    readonly property bool syncedLyrics: hasLyrics && lyrics.synced === true
    readonly property var lyricLines: hasLyrics ? lyrics.lines : []
    readonly property int lyricIndex: syncedLyrics ? Number(lyrics.currentIndex) : -1
    readonly property string previousLyric: {
        if (!syncedLyrics || lyricIndex <= 0 || lyricIndex > lyricLines.length)
            return "";
        const line = lyricLines[lyricIndex - 1];
        return line ? String(line.text || "") : "";
    }
    readonly property string currentLyric: {
        if (!hasLyrics || lyricLines.length === 0)
            return "";
        const index = syncedLyrics ? lyricIndex : 0;
        if (index < 0 || index >= lyricLines.length)
            return "";
        const line = lyricLines[index];
        return line ? String(line.text || "") : "";
    }
    readonly property string nextLyric: {
        if (!syncedLyrics || lyricIndex < 0 || lyricIndex + 1 >= lyricLines.length)
            return "";
        const line = lyricLines[lyricIndex + 1];
        return line ? String(line.text || "") : "";
    }
    readonly property string plainLyric: {
        if (!hasLyrics)
            return "";
        const lines = [];
        for (let i = 0; i < Math.min(4, lyricLines.length); i++) {
            const line = lyricLines[i];
            if (line)
                lines.push(String(line.text || ""));
        }
        return lines.join("\n");
    }

    readonly property var ghostSpecs: elements.length > 0 ? elements : fallbackGhostSpecs
    readonly property var fallbackGhostSpecs: [
        { glyph: "󰀻", x: 0.025, size: 20, delay: 0.02, drift: -0.6, spin: -1.2 },
        { chip: true, x: 0.072, size: 12, delay: 0.035, drift: -0.3, spin: 0.9 },
        { chip: true, x: 0.112, size: 12, delay: 0.05, drift: 0.2, spin: -0.7 },
        { chip: true, x: 0.152, size: 12, delay: 0.065, drift: -0.2, spin: 0.8 },
        { chip: true, x: 0.192, size: 12, delay: 0.08, drift: 0.3, spin: -1.0 },
        { chip: true, x: 0.232, size: 12, delay: 0.095, drift: -0.4, spin: 0.6 },
        { clock: true, x: 0.55, size: 15, delay: 0.12, drift: 0.2, spin: -0.4 },
        { glyph: "\uf1eb", x: 0.72, size: 16, delay: 0.145, drift: 0.4, spin: 0.7 },
        { glyph: "\uf293", x: 0.765, size: 16, delay: 0.16, drift: -0.4, spin: -0.8 },
        { glyph: "󰁹", x: 0.81, size: 16, delay: 0.175, drift: 0.3, spin: 0.5 },
        { glyph: "󰍜", x: 0.865, size: 16, delay: 0.19, drift: -0.3, spin: -0.6 },
        { glyph: "󰒓", x: 0.93, size: 18, delay: 0.21, drift: 0.5, spin: 0.9 }
    ]

    readonly property bool effectsEnabled: audioLive && outputAudible && !!player && player.isPlaying
        && !calm && showParticles && entry > 0.65
    property real bassEnergy: 0
    property var impact: Party.idleImpact()
    property var camera: Party.idleCamera()
    property var analysis: Party.idleAnalysis()
    property var rhythm: Party.idleRhythm()
    property real tintEnvelope: 0
    property double lastAudioTime: -1
    property int lastAudioSequence: -1
    property real deliveryDelay: 0
    readonly property real cameraEnvelope: camera.envelope
    readonly property real motionDensity: camera.density
    readonly property string trackIdentity: player ? String(player.trackTitle || "")
        + "\n" + String(player.trackArtist || "") + "\n" + String(player.trackAlbum || "")
        + "\n" + String(player.trackArtUrl || "")
        + "\n" + String(player.metadata ? player.metadata["mpris:trackid"] || "" : "") : ""
    readonly property real cameraReveal: Party.smooth(Party.phase(entry, 0.65, 0.93))
    readonly property real impactZoom: 1 + (0.33 * cameraEnvelope
        + 0.035 * Math.max(0, impact.buildup - 0.01))
        * cameraReveal
    readonly property real shakeX: camera.x * coverSize * 0.012 * cameraReveal
    readonly property real shakeY: camera.y * coverSize * 0.012 * cameraReveal
    readonly property real shakeRotation: camera.rotation * 0.45 * cameraReveal
    property real blurZoom: 0
    property point blurOffset: Qt.point(0, 0)
    property var previousBox: null
    property real previousZoom: 1
    property point previousShake: Qt.point(0, 0)
    property var previousSpectrum: []
    property double lastFrame: 0

    function resetMotion() {
        impact = Party.idleImpact();
        camera = Party.idleCamera();
        analysis = Party.idleAnalysis();
        rhythm = Party.idleRhythm();
        tintEnvelope = 0;
        lastAudioTime = -1;
        lastAudioSequence = -1;
        deliveryDelay = 0;
        bassEnergy = 0;
        blurZoom = 0;
        blurOffset = Qt.point(0, 0);
        previousBox = coverBox;
        previousZoom = impactZoom;
        previousShake = Qt.point(shakeX, shakeY);
        previousSpectrum = [];
        lastFrame = 0;
    }

    function advanceFrame(dt, freshSample, sourceAnalysis) {
        const oldImpact = impact;
        bassEnergy = effectsEnabled ? (sourceAnalysis ? sourceAnalysis.level : Party.bass(impactLevels)) : 0;
        const flux = freshSample === true && impact.sampleAge + dt <= 450
            ? Party.bassFlux(impactLevels, previousSpectrum) : 0;
        impact = Party.advanceImpact(impact, bassEnergy, dt, effectsEnabled,
                                     bassThreshold, freshSample === true, flux, sourceAnalysis);
        if (freshSample === true)
            previousSpectrum = impactLevels;
        if (sourceAnalysis && effectsEnabled)
            rhythm = Party.advanceRhythm(rhythm, impact, sourceAnalysis.dt);
        else if (impact.sampleAge > 450 || !effectsEnabled)
            rhythm = Party.idleRhythm();
        camera = Party.advanceCamera(camera, impact, oldImpact.age, dt,
                                     timestampedAudio ? rhythm : null);
        tintEnvelope = effectsEnabled ? Party.advanceTint(tintEnvelope, camera.envelope, dt) : 0;
        const box = coverBox;
        const old = previousBox || box;
        const morphZoom = Math.sqrt((box.width * box.height)
            / Math.max(1, old.width * old.height)) - 1;
        // Use a fixed exposure, independent of render cadence. A missed frame
        // must not produce a disproportionately long trail.
        const forming = entry > 0 && entry < 1;
        const exposure = (forming ? 4.17 : 16.67) / Math.max(8, dt || 16.67);
        const velocity = (impactZoom / previousZoom - 1 + morphZoom) * exposure;
        const immediate = impact.hit && oldImpact.age + dt >= 280 && motionDensity < 0.2;
        const alpha = immediate ? 1 : 1 - Math.exp(-dt / 22);
        const blurLimit = forming ? 0.018
            : 0.045 * Math.pow(cameraEnvelope, 1.15) * impact.damping * (1 - 0.6 * motionDensity);
        blurZoom = Party.lerp(blurZoom,
            Math.max(-blurLimit, Math.min(blurLimit, velocity * 1.5)), alpha);
        const dx = (box.x + box.width / 2 - old.x - old.width / 2
            + shakeX - previousShake.x) * exposure / Math.max(1, screenWidth);
        const dy = (box.y + box.height / 2 - old.y - old.height / 2
            + shakeY - previousShake.y) * exposure / Math.max(1, screenHeight);
        const offsetLimit = forming ? 0.007 : 0.025;
        blurOffset = Qt.point(
            Party.lerp(blurOffset.x, Math.max(-offsetLimit, Math.min(offsetLimit, dx)), alpha),
            Party.lerp(blurOffset.y, Math.max(-offsetLimit, Math.min(offsetLimit, dy)), alpha));
        previousBox = box;
        previousZoom = impactZoom;
        previousShake = Qt.point(shakeX, shakeY);
    }

    function tickFrame(freshSample) {
        const now = Date.now();
        const dt = lastFrame ? Math.max(0, now - lastFrame) : 0;
        lastFrame = now;
        advanceFrame(dt, freshSample);
    }

    // Detect on receipt of each live frame; the animation timer only needs to
    // advance the release between audio frames, not delay the initial impact.
    onImpactLevelsChanged: {
        if (!timestampedAudio && entry > 0.001 && !calm)
            tickFrame(true);
    }

    function receiveAudioFrame(packet, now) {
        if (!timestampedAudio || !effectsEnabled || !packet)
            return;
        if (packet.fixedGain !== true || packet.version !== 1
            || !Number.isInteger(packet.sequence) || packet.sequence < 0
            || !Number.isFinite(packet.time) || !Number.isFinite(packet.emittedAt)
            || !Array.isArray(packet.levels) || packet.levels.length !== 32
            || packet.levels.some(value => !Number.isFinite(value) || value < 0 || value > 1))
            return;
        if (packet.sequence <= lastAudioSequence || packet.time <= lastAudioTime
            || now - packet.emittedAt > 250 || packet.emittedAt - now > 1000)
            return;
        const sourceDt = lastAudioTime >= 0 ? packet.time - lastAudioTime : 16.67;
        if (sourceDt > 450) {
            analysis = Party.idleAnalysis();
            rhythm = Party.idleRhythm();
        }
        analysis = Party.advanceAnalysis(analysis, packet.levels, sourceDt);
        lastAudioTime = packet.time;
        lastAudioSequence = packet.sequence;
        deliveryDelay = Math.max(0, now - packet.emittedAt);
        const dt = lastFrame ? Math.max(0, now - lastFrame) : 0;
        lastFrame = now;
        advanceFrame(dt, true, analysis);
    }

    onAudioFrameChanged: receiveAudioFrame(audioFrame, Date.now())

    onEffectsEnabledChanged: {
        if (!effectsEnabled)
            resetMotion();
    }
    onPlayerChanged: resetMotion()
    onTrackIdentityChanged: resetMotion()
    onCalmChanged: resetMotion()
    // A display/layout resize is not camera motion. Reset after dependent
    // cover geometry bindings have updated to avoid a spurious full-screen trail.
    onScreenWidthChanged: Qt.callLater(root.resetMotion)
    onScreenHeightChanged: Qt.callLater(root.resetMotion)
    onEntryChanged: {
        if (entry <= 0.001)
            resetMotion();
    }
    Component.onCompleted: resetMotion()

    Timer {
        interval: 16
        repeat: true
        running: root.entry > 0.001 && !root.calm
        onTriggered: root.tickFrame(false)
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme ? root.theme.withAlpha(root.theme.surface,
                                                 0.92 * root.backdropOpacity) : "#101014"
    }

    Rectangle {
        objectName: "partyTint"
        anchors.fill: parent
        color: root.theme ? root.theme.accent : "#bfc4ee"
        opacity: (0.025 + root.tintEnvelope * 0.055) * root.backdropOpacity
    }

    Item {
        id: contentLayer
        anchors.fill: parent

        EdgeVisualiser {
            objectName: "partyTopBars"
            anchors.fill: parent
            edge: "top"
            levels: root.levels
            barCount: 64
            theme: root.theme
            s: root.s
            opacity: root.barsReveal
        }

        EdgeVisualiser {
            objectName: "partyBottomBars"
            anchors.fill: parent
            edge: "bottom"
            levels: root.levels
            barCount: 64
            theme: root.theme
            s: root.s
            opacity: root.barsReveal
        }

        EdgeVisualiser {
            objectName: "partyLeftBars"
            anchors.fill: parent
            edge: "left"
            levels: root.levels
            barCount: 40
            theme: root.theme
            s: root.s
            opacity: root.barsReveal
        }

        EdgeVisualiser {
            objectName: "partyRightBars"
            anchors.fill: parent
            edge: "right"
            levels: root.levels
            barCount: 40
            theme: root.theme
            s: root.s
            opacity: root.barsReveal
        }

    }

    // Screen-edge bars stay anchored while the center punches toward the viewer.
    Item {
        id: cameraLayer
        objectName: "partyCamera"
        anchors.fill: parent
        transform: [
            Scale {
                origin.x: root.coverTargetX + root.coverSize / 2
                origin.y: root.coverTargetY + root.coverSize / 2
                xScale: root.impactZoom
                yScale: root.impactZoom
            },
            Rotation {
                origin.x: root.coverTargetX + root.coverSize / 2
                origin.y: root.coverTargetY + root.coverSize / 2
                angle: root.shakeRotation
            },
            Translate { x: root.shakeX; y: root.shakeY }
        ]
        layer.enabled: !root.calm && root.entry >= 1 && (Math.abs(root.blurZoom) > 0.0001
            || Math.abs(root.blurOffset.x) + Math.abs(root.blurOffset.y) > 0.0001)
        layer.smooth: true
        layer.effect: ShaderEffect {
            objectName: "partyMotionBlur"
            property var source
            property real zoomVelocity: root.blurZoom
            property point motionOffset: root.blurOffset
            property point blurCenter: Qt.point(
                (root.coverBox.x + root.coverBox.width / 2) / Math.max(1, root.screenWidth),
                (root.coverBox.y + root.coverBox.height / 2) / Math.max(1, root.screenHeight))
            fragmentShader: "../shaders/party-motion.frag.qsb"
        }

        Item {
            id: coverHost
            objectName: "partyCoverHost"
            x: root.coverBox.x
            y: root.coverBox.y
            width: root.coverBox.width
            height: root.coverBox.height
            transformOrigin: Item.Center
            // Capture only the morphing cover during formation. A fixed texture
            // avoids allocating a full-screen buffer (or resizing it every frame).
            layer.enabled: !root.calm && root.entry > 0 && root.entry < 1
            layer.smooth: true
            layer.textureSize: Qt.size(
                Math.ceil(Math.max(root.restWidth, root.coverSize) * Screen.devicePixelRatio),
                Math.ceil(root.coverSize * Screen.devicePixelRatio))
            layer.effect: ShaderEffect {
                property var source
                property real zoomVelocity: root.blurZoom
                property point motionOffset: Qt.point(
                    root.blurOffset.x * root.screenWidth / Math.max(1, coverHost.width),
                    root.blurOffset.y * root.screenHeight / Math.max(1, coverHost.height))
                property point blurCenter: Qt.point(0.5, 0.5)
                fragmentShader: "../shaders/party-motion.frag.qsb"
            }

            PillBody {
                objectName: "partyGhostPill"
                anchors.fill: parent
                theme: root.theme
                backgroundOpacity: root.pillBackgroundOpacity
                cornerRadius: Math.min(width, height) / 2
                antialiasing: true
                animateCornerRadius: false
                opacity: 1 - Party.clamp01(root.entry / 0.42)
                visible: opacity > 0.01
            }

            AlbumCover {
                objectName: "partyCover"
                anchors.fill: parent
                s: root.s * Party.lerp(1, root.coverSize / (180 * root.s),
                                      Party.smooth(Party.phase(root.entry, 0.30, 0.85)))
                fillContainer: true
                artSize: Math.max(1, Math.round(root.coverSize * 4))
                theme: root.theme
                source: root.player ? root.player.trackArtUrl || "" : ""
                playing: root.player && root.player.isPlaying
                active: root.entry > 0.5 && !(root.motion && root.motion.calm)
                opacity: root.coverReveal
                visible: root.coverReveal > 0.001
                interactive: root.entry > 0.96
                onLongPressed: root.exitRequested()
            }
        }

        Item {
            id: ghostLayer
            x: root.coverBox.x
            y: root.coverBox.y
            width: root.coverBox.width
            height: root.coverBox.height
            visible: root.entry < 0.34

            Repeater {
                objectName: "partySeatedIcons"
                model: root.ghostSpecs

                Item {
                    id: ghost
                    required property var modelData
                    required property int index

                    visible: root.entry <= (modelData.delay || 0) + 0.12
                    x: modelData.x * ghostLayer.width - width / 2
                    y: (modelData.y === undefined ? 0.5 : modelData.y) * ghostLayer.height - height / 2
                    width: element.implicitWidth
                    height: element.implicitHeight

                    PartyElement {
                        id: element
                        anchors.fill: parent
                        spec: ghost.modelData
                        index: ghost.index
                        theme: root.theme
                        s: root.s
                    }
                }
            }
        }

        Item {
            id: fallingLayer
            objectName: "partyFallingLayer"
            anchors.fill: parent
            visible: root.entry > 0.001 && root.entry < 0.99

            Repeater {
                id: fallingRepeater
                objectName: "partyFallingIcons"
                model: root.ghostSpecs

                Item {
                    id: particle
                    required property var modelData
                    required property int index

                    readonly property real release: (modelData.delay || 0) + 0.12
                    readonly property real fall: Party.phase(root.entry, release, release + 0.62)
                    readonly property var launch: Party.formationRect(release,
                        root.pillRect, root.coverTargetRect)

                    width: 1
                    height: 1
                    x: launch.x + modelData.x * launch.width
                        + (modelData.drift || 0) * fall * root.screenWidth * 0.10
                    y: launch.y + (modelData.y === undefined ? 0.5 : modelData.y) * launch.height
                        - Math.sin(fall * Math.PI) * 30 * root.s
                        + fall * fall * (root.screenHeight - launch.y + 100 * root.s)
                    rotation: (modelData.spin || 0) * fall * 220
                    opacity: fall < 0.94 ? 1 : Math.max(0, (1 - fall) / 0.06)
                    visible: root.entry < 0.99 && fall > 0

                    PartyElement {
                        anchors.centerIn: parent
                        width: implicitWidth
                        height: implicitHeight
                        spec: particle.modelData
                        index: particle.index
                        theme: root.theme
                        s: root.s
                    }
                }
            }
        }

        Item {
            id: lyricBlock
            objectName: "partyLyrics"
            x: Math.round((root.screenWidth - width) / 2)
            y: root.coverTargetY + root.coverSize + root.gap
                + (1 - root.lyricsReveal) * 24 * root.s
            width: Math.min(root.screenWidth * 0.74, 980 * root.s)
            height: root.lyricsBlockHeight
            opacity: root.lyricsReveal
            visible: root.hasLyrics

            Text {
                id: previousText
                width: parent.width
                visible: root.syncedLyrics && root.previousLyric.length > 0
                text: root.previousLyric
                color: root.theme ? root.theme.withAlpha(root.theme.cream, 0.42) : "#777"
                font.family: root.theme ? root.theme.fontFamily : "sans"
                font.pixelSize: 16 * root.s
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                id: currentText
                width: parent.width
                y: previousText.visible ? previousText.height + 8 * root.s : 0
                text: root.syncedLyrics ? root.currentLyric : root.plainLyric
                color: root.theme ? root.theme.cream : "#f0f0f0"
                font.family: root.theme ? root.theme.fontFamily : "sans"
                font.pixelSize: (root.syncedLyrics ? 27 : 17) * root.s
                font.weight: root.syncedLyrics ? Font.DemiBold : Font.Normal
                lineHeight: 1.35
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: root.syncedLyrics ? 2 : 4
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                y: currentText.y + currentText.height + 8 * root.s
                visible: root.syncedLyrics && root.nextLyric.length > 0
                text: root.nextLyric
                color: root.theme ? root.theme.withAlpha(root.theme.cream, 0.55) : "#888"
                font.family: root.theme ? root.theme.fontFamily : "sans"
                font.pixelSize: 17 * root.s
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
