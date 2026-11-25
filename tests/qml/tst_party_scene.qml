import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 1920
    height: 1200

    Theme { id: fixtureTheme }

    QtObject {
        id: mockPlayer
        property bool isPlaying: true
        property string trackArtUrl: ""
        property string trackTitle: "Fixture track"
    }
    QtObject {
        id: mockMotion
        property bool calm: false
    }

    QtObject {
        id: mockLyrics
        property string status: "ready"
        property bool synced: true
        property var lines: [
            { text: "The line before", time: 0 },
            { text: "This is the current line", time: 10 },
            { text: "The line after", time: 20 }
        ]
        property int currentIndex: 1
    }

    PartyScene {
        id: scene
        anchors.fill: parent
        theme: fixtureTheme
        s: 1
        screenWidth: parent.width
        screenHeight: parent.height
        restWidth: 1000
        restHeight: 34
        restY: 8
        entry: 1
        lyrics: mockLyrics
        player: mockPlayer
        motion: mockMotion
    }

    TestCase {
        name: "PartyScene"
        when: windowShown

        function init() {
            scene.timestampedAudio = false;
            scene.elements = [];
            scene.audioFrame = null;
            scene.entry = 1;
            scene.levels = [0, 0, 0, 0, 0, 0];
            scene.showParticles = true;
            scene.audioLive = true;
            scene.outputAudible = true;
            scene.player = mockPlayer;
            mockPlayer.isPlaying = true;
            mockMotion.calm = false;
            scene.resetMotion();
            mockLyrics.status = "ready";
            mockLyrics.synced = true;
            mockLyrics.currentIndex = 1;
            wait(10);
        }

        function test_entry_zero_starts_at_the_pill_rect() {
            scene.entry = 0;
            wait(10);
            compare(scene.coverBox.x, scene.pillRect.x);
            compare(scene.coverBox.y, scene.pillRect.y);
            compare(scene.coverBox.width, scene.pillRect.width);
            compare(scene.coverBox.height, scene.pillRect.height);
        }

        function test_timestamped_audio_rejects_stale_duplicate_and_reordered_packets() {
            scene.timestampedAudio = true;
            scene.resetMotion();
            const now = Date.now();
            const packet = {version: 1, fixedGain: true, levels: Array(32).fill(0.2),
                            sequence: 1, time: 1000, emittedAt: now};
            scene.receiveAudioFrame(packet, now);
            verify(scene.impact.hit);
            const sequence = scene.impact.sequence;
            scene.receiveAudioFrame(packet, now);
            scene.receiveAudioFrame(Object.assign({}, packet, {sequence: 0, time: 999}), now);
            scene.receiveAudioFrame(Object.assign({}, packet, {sequence: 2, time: 1017, emittedAt: now - 400}), now);
            scene.receiveAudioFrame(Object.assign({}, packet, {sequence: 2, levels: null}), now);
            compare(scene.impact.sequence, sequence);
            compare(scene.lastAudioSequence, 1);
            scene.levels = Array(32).fill(1);
            compare(scene.impact.sequence, sequence, "normalized bars cannot detect a second impact");
            mockPlayer.isPlaying = false;
            compare(scene.tintEnvelope, 0);
            compare(scene.lastAudioSequence, -1);
            compare(scene.rhythm.confidence, 0);
        }

        function test_entry_one_lands_on_the_cover_rect() {
            compare(scene.coverBox.x, scene.coverTargetRect.x);
            compare(scene.coverBox.y, scene.coverTargetRect.y);
            compare(scene.coverBox.width, scene.coverTargetRect.width);
            compare(scene.coverBox.height, scene.coverTargetRect.height);
        }

        function test_cover_is_centered_and_large() {
            verify(scene.coverTargetRect.width > fixture.width * 0.3);
            verify(scene.coverTargetRect.height > fixture.height * 0.45);
            verify(Math.abs(scene.coverTargetRect.x
                             + scene.coverTargetRect.width / 2
                             - fixture.width / 2) < 1);
        }

        function test_lyrics_appear_with_a_ready_provider() {
            const lyricsItem = findChild(scene, "partyLyrics");
            verify(lyricsItem !== null);
            verify(lyricsItem.opacity > 0.9);
            compare(scene.currentLyric, "This is the current line");
            compare(scene.previousLyric, "The line before");
            compare(scene.nextLyric, "The line after");
        }

        function test_lyrics_hide_when_the_provider_has_nothing() {
            mockLyrics.status = "missing";
            wait(10);
            compare(findChild(scene, "partyLyrics").opacity, 0);
        }

        function test_out_of_range_lyric_index_is_empty() {
            mockLyrics.currentIndex = 99;
            wait(10);
            compare(scene.lyricIndex, 99);
            compare(scene.previousLyric, "");
            compare(scene.currentLyric, "");
            compare(scene.nextLyric, "");
        }

        function test_all_four_edge_visualisers_exist() {
            verify(findChild(scene, "partyTopBars") !== null);
            verify(findChild(scene, "partyBottomBars") !== null);
            verify(findChild(scene, "partyLeftBars") !== null);
            verify(findChild(scene, "partyRightBars") !== null);
        }

        function test_falling_icon_repeater_has_particles() {
            const icons = findChild(scene, "partyFallingIcons");
            verify(icons !== null);
            verify(icons.count >= 9);
        }

        function test_formation_keeps_motion_trails_short_data() {
            return [
                { tag: "entering", from: 0.25, to: 0.4 },
                { tag: "returning", from: 0.4, to: 0.25 }
            ];
        }

        function test_formation_keeps_motion_trails_short(data) {
            scene.entry = data.from;
            scene.resetMotion();
            scene.entry = data.to;
            scene.advanceFrame(16, false);
            verify(Math.abs(scene.blurZoom) > 0.0001, "moving elements retain a short trail");
            verify(Math.abs(scene.blurZoom) <= 0.018, "formation zoom should stay legible");
            verify(Math.abs(scene.blurOffset.x) <= 0.007);
            verify(Math.abs(scene.blurOffset.y) <= 0.007, "formation travel should stay legible");
        }

        function test_formation_blurs_only_the_cover_with_a_stable_texture() {
            scene.entry = 0.2;
            const camera = findChild(scene, "partyCamera");
            const cover = findChild(scene, "partyCoverHost");
            verify(!camera.layer.enabled, "formation must avoid the full-screen capture");
            verify(cover.layer.enabled);
            const size = cover.layer.textureSize;
            scene.entry = 0.7;
            compare(cover.layer.textureSize, size, "formation must not resize its texture each frame");
            verify(size.width * size.height < scene.screenWidth * scene.screenHeight);
            mockMotion.calm = true;
            verify(!camera.layer.enabled && !cover.layer.enabled);
        }

        function test_particles_return_while_audio_effects_are_disabled() {
            scene.showParticles = false;
            scene.entry = 0.5;
            wait(10);
            compare(findChild(scene, "partyFallingLayer").visible, true);
            verify(findChild(scene, "partyFallingIcons").itemAt(0).visible);
        }

        function test_each_slot_is_empty_until_its_element_lands() {
            scene.showParticles = false;
            const seated = findChild(scene, "partySeatedIcons");
            const moving = findChild(scene, "partyFallingIcons");
            for (let i = 0; i < moving.count; i++) {
                const release = scene.ghostSpecs[i].delay + 0.12;
                scene.entry = release + 0.01;
                verify(!seated.itemAt(i).visible, "slot must be empty before arrival");
                verify(moving.itemAt(i).visible, "returning element must be visible");
                scene.entry = release;
                verify(seated.itemAt(i).visible, "arrival fills the slot");
                verify(!moving.itemAt(i).visible, "there must be only one copy after arrival");
                const center = seated.itemAt(i).mapToItem(scene,
                    seated.itemAt(i).width / 2, seated.itemAt(i).height / 2);
                fuzzyCompare(center.x, moving.itemAt(i).x, 0.01);
                fuzzyCompare(center.y, moving.itemAt(i).y, 0.01);
            }
        }

        function test_reconstructed_elements_finish_in_the_live_layout() {
            scene.elements = [
                {rem: true, x: 0.06, y: 0.5, width: 20, height: 20, delay: 0.02},
                {text: "13:00", x: 0.5, y: 0.5, width: 40, height: 20, delay: 0.12},
                {text: "9", x: 0.2, y: 0.5, width: 11, height: 20, delay: 0.21}
            ];
            scene.entry = 0;
            const seated = findChild(scene, "partySeatedIcons");
            compare(seated.count, scene.elements.length);
            for (let i = 0; i < seated.count; i++) {
                const item = seated.itemAt(i);
                const spec = scene.elements[i];
                const center = item.mapToItem(scene, item.width / 2, item.height / 2);
                fuzzyCompare(center.x, scene.pillRect.x + spec.x * scene.pillRect.width, 0.01);
                fuzzyCompare(center.y, scene.pillRect.y + spec.y * scene.pillRect.height, 0.01);
                compare(item.width, spec.width);
                compare(item.height, spec.height);
            }
        }

        function test_morphing_pill_body_fades_as_the_cover_arrives() {
            scene.entry = 0.12;
            wait(10);
            const body = findChild(scene, "partyGhostPill");
            verify(body !== null);
            verify(body.opacity > 0.2, "the pill body should be visible early");

            scene.entry = 0.55;
            wait(10);
            compare(body.opacity, 0, "the pill body should give way to the cover");
        }

        function test_bass_energy_reacts_to_levels() {
            scene.levels = [1, 1, 1, 1, 1, 1];
            wait(140);
            verify(scene.bassEnergy > 0.2, "bass energy should follow the spectrum");
        }

        function test_bass_zoom_has_a_sharp_attack_and_releases() {
            scene.levels = [1, 1, 1, 1, 1, 1];
            verify(scene.impactZoom >= 1.29,
                "the live sample must land without waiting for an animation tick");
            verify(scene.blurZoom > 0.01, "zoom must produce a directional trail");
            scene.levels = [0, 0, 0, 0, 0, 0];
            for (let i = 0; i < 90; ++i)
                scene.advanceFrame(16);
            compare(scene.impactZoom, 1);
            verify(Math.abs(scene.blurZoom) < 0.0001, "resting cover must be sharp");
        }

        function test_narrow_quiet_kicks_zoom_on_each_fresh_sample() {
            for (let beat = 0; beat < 8; ++beat) {
                scene.levels = Array(32).fill(0);
                for (let frame = 0; frame < 8; ++frame)
                    scene.advanceFrame(16);
                const levels = Array(32).fill(0);
                // Alternate channels and include the higher kick bins.
                levels[beat % 2 ? 11 : 20] = 0.5;
                scene.levels = levels;
                verify(scene.impact.hit, "each fresh bass onset must trigger");
                scene.advanceFrame(16);
                verify(scene.impactZoom > 1.02 && scene.impactZoom < 1.13,
                    "quiet kicks should have a visible, proportionately small zoom");
                verify(Math.abs(scene.shakeX) + Math.abs(scene.shakeY) > 0,
                    "a fresh kick should have a small recoil");
                verify(Math.abs(scene.blurZoom) > 0.0001, "each new zoom should have a short trail");
                verify(scene.blurZoom < 0.02, "soft kicks must keep a short, legible trail");
            }
        }

        function test_animation_ticks_do_not_replay_rejected_onsets() {
            scene.levels = Array(32).fill(1);
            verify(scene.impact.hit);
            scene.advanceFrame(16);
            scene.levels = Array(32).fill(0);
            scene.advanceFrame(16);
            scene.levels = Array(32).fill(1);
            verify(!scene.impact.hit, "duplicate during cooldown must be suppressed");
            for (let frame = 0; frame < 90; ++frame) {
                scene.advanceFrame(16);
                verify(!scene.impact.hit, "animation must only release the impact");
            }
            compare(scene.impactZoom, 1);
        }

        function test_fake_audio_pause_calm_and_exit_reset_impact() {
            scene.levels = [1, 1, 1, 1, 1, 1];
            scene.advanceFrame(16);
            scene.advanceFrame(42);
            mockPlayer.isPlaying = false;
            compare(scene.impactZoom, 1);
            scene.advanceFrame(16);
            compare(scene.bassEnergy, 0);

            mockPlayer.isPlaying = true;
            scene.audioLive = false;
            scene.advanceFrame(100);
            compare(scene.impactZoom, 1);
            scene.audioLive = true;
            mockMotion.calm = true;
            scene.advanceFrame(100);
            compare(scene.impactZoom, 1);
            compare(scene.blurZoom, 0);
            mockMotion.calm = false;
            scene.showParticles = false;
            scene.advanceFrame(100);
            compare(scene.impactZoom, 1);
        }

        function test_player_disappearing_clears_zoom() {
            scene.levels = [1, 1, 1, 1, 1, 1];
            verify(scene.impactZoom > 1.29);
            scene.player = null;
            compare(scene.impactZoom, 1);
            scene.advanceFrame(16);
            compare(scene.bassEnergy, 0);
        }

        function test_track_switch_clears_camera_history() {
            scene.levels = Array(32).fill(1);
            verify(scene.impactZoom > 1.29);
            mockPlayer.trackTitle = "Next track";
            compare(scene.impactZoom, 1);
            compare(scene.shakeX, 0);
            compare(scene.shakeY, 0);
            compare(scene.shakeRotation, 0);
            compare(scene.blurZoom, 0);
            compare(scene.blurOffset, Qt.point(0, 0));
            compare(scene.impact.intervals.length, 0);
            mockPlayer.trackTitle = "Fixture track";
        }

        function test_pause_clears_shake_and_blur_immediately() {
            scene.levels = Array(32).fill(1);
            verify(scene.blurZoom > 0);
            mockPlayer.isPlaying = false;
            compare(scene.impactZoom, 1);
            compare(scene.shakeX, 0);
            compare(scene.shakeY, 0);
            compare(scene.blurZoom, 0);
            compare(scene.blurOffset, Qt.point(0, 0));
        }

        function test_muted_output_blocks_impacts_until_a_new_live_sample() {
            scene.levels = Array(32).fill(1);
            verify(scene.impact.hit);
            scene.outputAudible = false;
            compare(scene.impactZoom, 1);
            compare(scene.blurZoom, 0);
            scene.levels = Array(32).fill(0.9);
            verify(!scene.impact.hit);
            scene.outputAudible = true;
            scene.advanceFrame(100);
            compare(scene.impactZoom, 1, "unmuting must not replay stale bins");
            scene.levels = Array(32).fill(1);
            verify(scene.impact.hit);
        }

        function test_shake_stays_small_and_edge_bars_stay_anchored() {
            const bars = findChild(scene, "partyTopBars");
            const before = bars.mapToItem(scene, 0, 0);
            scene.levels = Array(32).fill(1);
            for (let frame = 0; frame < 80; ++frame) {
                verify(Math.abs(scene.shakeX) <= scene.coverSize * 0.012);
                verify(Math.abs(scene.shakeY) <= scene.coverSize * 0.012);
                verify(Math.abs(scene.shakeRotation) <= 0.45);
                compare(bars.mapToItem(scene, 0, 0), before);
                scene.advanceFrame(16);
            }
            verify(Math.abs(scene.shakeX) < 0.0001);
        }

        function test_successive_hits_blend_camera_motion_without_snapping() {
            scene.levels = Array(32).fill(1);
            let previousZoom = scene.impactZoom;
            let previousX = scene.shakeX;
            let previousY = scene.shakeY;
            for (let beat = 0; beat < 18; ++beat) {
                scene.levels = Array(32).fill(0);
                for (let frame = 0; frame < 3; ++frame)
                    scene.advanceFrame(16);
                const before = scene.impactZoom;
                scene.levels = Array(32).fill(1);
                verify(scene.impact.hit, "smoothing must not drop detected beats");
                verify(Math.abs(scene.impactZoom - before) < 0.02,
                    "dense onsets update the target without an instant zoom jump");
                scene.advanceFrame(16);
                if (beat > 3) {
                    verify(Math.abs(scene.impactZoom - previousZoom) < 0.04);
                    verify(Math.abs(scene.shakeX) < scene.coverSize * 0.002);
                    verify(Math.abs(scene.shakeY) < scene.coverSize * 0.002);
                    verify(Math.abs(scene.shakeX - previousX) < 1);
                    verify(Math.abs(scene.shakeY - previousY) < 1);
                }
                previousZoom = scene.impactZoom;
                previousX = scene.shakeX;
                previousY = scene.shakeY;
            }
        }

        function test_coincident_dense_audio_does_not_reset_the_blur() {
            scene.levels = Array(32).fill(1);
            scene.levels = Array(32).fill(0);
            scene.advanceFrame(64, true);
            const zoom = scene.impactZoom;
            const blur = scene.blurZoom;
            const offset = scene.blurOffset;
            verify(Math.abs(blur) > 0.0001);
            // Force zero elapsed time, as when audio and rendering coincide.
            scene.lastFrame = Date.now() + 1000;
            scene.levels = Array(32).fill(1);
            verify(scene.impact.hit);
            compare(scene.impactZoom, zoom);
            compare(scene.blurZoom, blur);
            compare(scene.blurOffset, offset);
        }

        function test_long_press_on_the_big_cover_requests_exit() {
            let exits = 0;
            const onExit = () => exits++;
            scene.exitRequested.connect(onExit);

            const cover = findChild(scene, "partyCover");
            verify(cover !== null);
            cover.longPressed();
            compare(exits, 1);

            scene.exitRequested.disconnect(onExit);
        }
    }
}
