import QtQuick
import QtTest
import "../../shell/lib/party.js" as Party

TestCase {
    name: "Party"

    function test_toggle_owner_cycles_and_switches() {
        compare(Party.toggleOwner("", "eDP-1"), "eDP-1");
        compare(Party.toggleOwner("eDP-1", "eDP-1"), "");
        compare(Party.toggleOwner("eDP-1", "HDMI-A-1"), "HDMI-A-1");
    }

    function test_close_owner_only_clears_its_screen() {
        compare(Party.closeOwner("eDP-1", "HDMI-A-1"), "eDP-1");
        compare(Party.closeOwner("eDP-1", "eDP-1"), "");
        compare(Party.closeOwner("eDP-1", ""), "");
    }

    function test_owner_checks_are_exact() {
        verify(Party.isOn("eDP-1", "eDP-1"));
        verify(!Party.isOn("eDP-1", "HDMI-A-1"));
        verify(!Party.isOn("", ""));
    }

    function test_clamp_and_lerp() {
        compare(Party.clamp01(-1), 0);
        compare(Party.clamp01(0.4), 0.4);
        compare(Party.clamp01(2), 1);
        compare(Party.lerp(10, 20, 0.25), 12.5);
    }

    function test_morph_rect_interpolates_every_edge() {
        const from = {x: 0, y: 8, width: 400, height: 40};
        const to = {x: 300, y: 200, width: 600, height: 600};
        const middle = Party.morphRect(0.5, from, to);

        compare(middle.x, 150);
        compare(middle.y, 104);
        compare(middle.width, 500);
        compare(middle.height, 320);
    }

    function test_bass_retains_only_the_low_band() {
        compare(Party.bass([]), 0);
        const treble = Array(32).fill(0);
        treble[0] = 1;
        treble[31] = 1;
        compare(Party.bass(treble), 0);
        const low = Array(32).fill(0);
        low[11] = low[12] = low[13] = low[14] = low[15] = 0.9;
        verify(Math.abs(Party.bass(low) - 0.9) < 0.000001);
        low[11] = low[12] = low[13] = low[14] = low[15] = 0;
        low[16] = low[17] = low[18] = low[19] = low[20] = 0.8;
        verify(Math.abs(Party.bass(low) - 0.8) < 0.000001);
        compare(Party.bass([0.5, 0.5, 0.5, 0.5, 0.5, 0.5]), 0.5);
    }

    function test_narrow_band_kicks_are_not_averaged_away() {
        for (let bin = 11; bin <= 20; ++bin) {
            const levels = Array(32).fill(0);
            levels[bin] = 1;
            verify(Party.bass(levels) > 0.7, "retain a kick concentrated in bin " + bin);
        }
    }

    function test_bass_flux_detects_new_bins_without_reacting_to_panning() {
        const before = Array(32).fill(0);
        before[15] = 0.8;
        const panned = Array(32).fill(0);
        panned[16] = 0.8;
        compare(Party.bassFlux(panned, before), 0, "moving stereo energy is not a new beat");
        const kick = panned.slice();
        kick[18] = 0.5;
        verify(Party.bassFlux(kick, panned) > 0.3, "a new bass frequency cuts through a held note");
        compare(Party.bassFlux(kick, []), 0);
        compare(Party.bassFlux(kick, kick), 0);
    }

    function test_flux_catches_a_beat_while_scalar_bass_is_held() {
        let state = Party.advanceImpact(null, 0.8, 16, true);
        for (let frame = 0; frame < 15; ++frame)
            state = Party.advanceImpact(state, 0.8, 16, true, undefined, true, 0);
        state = Party.advanceImpact(state, 0.8, 16, true, undefined, true, 0.1);
        verify(state.hit, "the maximum bass bin need not drop between beats");
        verify(state.strength > 0.2 && state.strength < 0.7);
        state = Party.advanceImpact(state, 0.6, 16, true, undefined, true, 0.06);
        state = Party.advanceImpact(state, 0.65, 48, true, undefined, true, 0.05);
        verify(!state.hit, "a delayed whole-band rise must not duplicate the flux hit");
    }

    function test_held_band_64ms_roll_catches_its_first_followup() {
        let state = Party.advanceImpact(null, 0.8, 16, true);
        for (let beat = 0; beat < 8; ++beat) {
            for (let frame = 0; frame < 3; ++frame)
                state = Party.advanceImpact(state, 0.8, 16, true, undefined, true, 0);
            state = Party.advanceImpact(state, 0.8, 16, true, undefined, true, 0.1);
            verify(state.hit, "every 64ms beat must land, including the first follow-up");
            verify(state.release < 50);
        }
    }

    function test_formation_anticipates_unfolds_and_settles() {
        const from = {x: 100, y: 8, width: 800, height: 34};
        const to = {x: 200, y: 200, width: 600, height: 600};
        compare(Party.formationRect(0, from, to), from);
        compare(Party.formationRect(1, from, to), to);
        verify(Party.formationRect(0.1, from, to).width < from.width);
        verify(Party.formationRect(0.78, from, to).height > to.height);
        let previous = Party.formationRect(0, from, to);
        for (let t = 0.01; t <= 1; t += 0.01) {
            const box = Party.formationRect(t, from, to);
            verify(box.width > 0 && box.height > 0);
            verify(Math.abs(box.x - previous.x) < 30);
            verify(Math.abs(box.y - previous.y) < 30);
            previous = box;
        }
    }

    function test_impact_attacks_then_releases_without_repeating_a_held_note() {
        let state = Party.advanceImpact(null, 1, 16, true);
        verify(state.hit);
        compare(state.envelope, 1, "the onset frame must hit at full strength");
        state = Party.advanceImpact(state, 1, 16, true);
        compare(state.envelope, 1);
        let hits = 1;
        for (let i = 0; i < 90; ++i) {
            state = Party.advanceImpact(state, 1, 16, true);
            hits += state.hit ? 1 : 0;
        }
        compare(hits, 1);
        compare(state.envelope, 0);
        state = Party.advanceImpact(state, 0, 16, true);
        state = Party.advanceImpact(state, 0.8, 16, true);
        verify(state.hit, "a new kick after release must retrigger");
    }

    function test_impact_refractory_period_and_subthreshold_noise() {
        let state = Party.idleImpact();
        for (let i = 0; i < 20; ++i) {
            state = Party.advanceImpact(state, i % 2 ? 0.07 : 0.02, 16, true);
            verify(!state.hit);
            compare(state.envelope, 0);
        }
        state = Party.advanceImpact(state, 1, 16, true);
        verify(state.hit);
        state = Party.advanceImpact(state, 0, 16, true);
        state = Party.advanceImpact(state, 1, 16, true);
        verify(!state.hit, "rapid noise must not trigger another impact");
        state = Party.advanceImpact(state, 0, 170, true);
        state = Party.advanceImpact(state, 1, 16, true);
        verify(state.hit);
    }

    function test_quieter_kicks_each_produce_an_impact() {
        let state = Party.advanceImpact(null, 0.55, 16, true);
        for (let frame = 0; frame < 12; ++frame)
            state = Party.advanceImpact(state, 0.15, 16, true);
        let hits = 0;
        for (let beat = 0; beat < 8; ++beat) {
            for (const value of [0.15, 0.3, 0.48, 0.55, 0.4, 0.25, 0.15, 0.15]) {
                state = Party.advanceImpact(state, value, 32, true);
                hits += state.hit ? 1 : 0;
            }
        }
        compare(hits, 8, "moderate beats must not need full-scale bass");
    }

    function test_gradual_kicks_over_sustained_bass_retrigger() {
        let state = Party.advanceImpact(null, 0.78, 16, true);
        let hits = 0;
        for (let beat = 0; beat < 8; ++beat) {
            for (let frame = 0; frame < 12; ++frame)
                state = Party.advanceImpact(state, 0.5, 16, true);
            for (const value of [0.54, 0.58, 0.62, 0.66, 0.7, 0.74, 0.78]) {
                state = Party.advanceImpact(state, value, 16, true);
                hits += state.hit ? 1 : 0;
            }
        }
        compare(hits, 8, "a kick can rise across multiple audio samples");
    }

    function test_fast_beats_are_not_halved_by_the_refractory_period() {
        let state = Party.idleImpact();
        let hits = 0;
        for (let beat = 0; beat < 8; ++beat) {
            state = Party.advanceImpact(state, 1, 16, true);
            hits += state.hit ? 1 : 0;
            for (let frame = 0; frame < 7; ++frame)
                state = Party.advanceImpact(state, 0, 16, true);
        }
        compare(hits, 8, "128ms-spaced kicks should all land");
    }

    function test_small_ripples_in_held_bass_do_not_pump() {
        let state = Party.advanceImpact(null, 0.7, 16, true);
        let hits = 0;
        for (let frame = 0; frame < 100; ++frame) {
            state = Party.advanceImpact(state, frame % 2 ? 0.7 : 0.68, 16, true);
            hits += state.hit ? 1 : 0;
        }
        compare(hits, 0);
    }

    function test_release_ticks_do_not_detect_stale_audio() {
        let state = Party.advanceImpact(null, 1, 16, true);
        state = Party.advanceImpact(state, 0, 16, true);
        state = Party.advanceImpact(state, 1, 16, true);
        verify(!state.hit, "a duplicate inside the cooldown is suppressed");
        for (let frame = 0; frame < 30; ++frame) {
            state = Party.advanceImpact(state, 1, 16, true, undefined, false);
            verify(!state.hit, "release ticks must not replay a suppressed onset");
        }
        state = Party.advanceImpact(state, 0, 16, true);
        state = Party.advanceImpact(state, 0.5, 16, true);
        verify(state.hit, "the next fresh kick still lands");
    }

    function test_impact_release_is_independent_of_frame_rate_and_resets() {
        const hit = Party.advanceImpact(null, 1, 16, true);
        let split = hit;
        for (let i = 0; i < 25; ++i)
            split = Party.advanceImpact(split, 1, 16, true);
        const single = Party.advanceImpact(hit, 1, 400, true);
        compare(split.envelope, single.envelope);
        compare(Party.advanceImpact(split, 1, 16, false), Party.idleImpact());
    }

    function test_impact_strength_scales_from_soft_to_hard() {
        let previous = 0;
        for (const level of [0.15, 0.25, 0.4, 0.6, 0.8, 1]) {
            const hit = Party.advanceImpact(null, level, 16, true);
            verify(hit.hit);
            verify(hit.envelope > previous, "stronger kicks deserve stronger motion");
            previous = hit.envelope;
        }
        const soft = Party.advanceImpact(null, 0.25, 16, true);
        const hard = Party.advanceImpact(null, 1, 16, true);
        verify(soft.envelope < hard.envelope * 0.25);
        const softShake = Party.impactShake(soft);
        const hardShake = Party.impactShake(hard);
        verify(Math.abs(softShake.x) < Math.abs(hardShake.x) * 0.25);
    }

    function test_small_accent_on_loud_bass_is_not_a_full_impact() {
        let state = Party.advanceImpact(null, 0.9, 16, true);
        for (let frame = 0; frame < 80; ++frame)
            state = Party.advanceImpact(state, 0.8, 16, true);
        state = Party.advanceImpact(state, 0.9, 16, true);
        verify(state.hit);
        verify(state.strength < 0.3, "local contrast matters even on a loud track");
    }

    function test_attack_follows_a_kick_rising_across_samples() {
        let state = Party.advanceImpact(null, 0.2, 16, true);
        let previous = state.envelope;
        let hits = 1;
        for (const value of [0.4, 0.7, 1]) {
            state = Party.advanceImpact(state, value, 16, true);
            hits += state.hit ? 1 : 0;
            verify(state.envelope > previous);
            previous = state.envelope;
        }
        compare(hits, 1, "strength can grow without detecting duplicate onsets");
        verify(state.envelope > 0.8, "the peak of the kick must receive its full punch");
    }

    function test_fast_rolls_get_distinct_shorter_lighter_impacts() {
        const isolated = Party.advanceImpact(null, 1, 16, true);
        let state = Party.idleImpact();
        let hits = 0;
        for (let beat = 0; beat < 16; ++beat) {
            state = Party.advanceImpact(state, 1, 16, true);
            hits += state.hit ? 1 : 0;
            if (beat > 0) {
                verify(state.release < isolated.release / 2);
                verify(state.strength < isolated.strength * 0.7);
            }
            for (let frame = 0; frame < 3; ++frame)
                state = Party.advanceImpact(state, 0, 16, true);
        }
        compare(hits, 16, "64ms rolls must not lose alternate beats");
        verify(state.envelope < 0.3, "the camera must release between rapid hits");
        state = Party.advanceImpact(state, 0, 2000, true);
        state = Party.advanceImpact(state, 1, 16, true);
        compare(state.release, isolated.release, "a breakdown resets the roll tempo");
        compare(state.strength, isolated.strength);
    }

    function test_a_rejected_second_attack_cannot_strengthen_the_first_hit() {
        let state = Party.advanceImpact(null, 0.2, 16, true);
        const strength = state.strength;
        let envelope = state.envelope;
        for (const level of [0, 0.4, 0.8, 1]) {
            state = Party.advanceImpact(state, level, 16, true);
            verify(!state.hit, "duplicate onsets inside the refractory period are consumed");
            compare(state.strength, strength, "a new attack cannot become the old kick's peak");
            verify(state.envelope <= envelope);
            envelope = state.envelope;
        }
    }

    function test_fast_beats_survive_jittered_audio_delivery() {
        for (const gaps of [[48], [48, 80]]) {
            let state = Party.advanceImpact(null, 1, 16, true);
            let hits = 1;
            for (let beat = 0; beat < 20; ++beat) {
                const gap = gaps[beat % gaps.length];
                state = Party.advanceImpact(state, 0, gap - 16, true);
                state = Party.advanceImpact(state, 1, 16, true);
                hits += state.hit ? 1 : 0;
                verify(state.release < 50 && state.strength < 0.7,
                    "accepted fast beats must also adapt release and impact");
            }
            compare(hits, 21, "render jitter must not drop a beat");
        }
    }

    function test_a_weaker_followup_does_not_snap_down_or_stack() {
        let state = Party.advanceImpact(null, 1, 16, true);
        state = Party.advanceImpact(state, 0, 48, true);
        const released = Party.advanceImpact(state, 0, 16, true, undefined, false);
        const soft = Party.advanceImpact(state, 0.2, 16, true);
        verify(soft.hit);
        verify(soft.envelope >= released.envelope, "keep the existing release continuous");
        verify(soft.envelope <= state.envelope, "a weak accent must not add to the heavy hit");
        const rest = Party.advanceImpact(soft, 0, 1600, true, undefined, false);
        compare(rest.envelope, 0);
    }

    function test_slow_crescendo_builds_without_repeated_impacts() {
        let state = Party.idleImpact();
        let hits = 0;
        let largestImpact = 0;
        let largestBuildup = 0;
        for (let frame = 0; frame < 240; ++frame) {
            state = Party.advanceImpact(state, frame / 240, 16, true);
            hits += state.hit ? 1 : 0;
            largestImpact = Math.max(largestImpact, state.envelope);
            largestBuildup = Math.max(largestBuildup, state.buildup);
        }
        verify(hits <= 1, "a volume swell is not a drum roll");
        verify(largestImpact < 0.35);
        verify(largestBuildup > 0.3, "a crescendo should visibly build tension");
        for (let frame = 0; frame < 180; ++frame)
            state = Party.advanceImpact(state, 0, 16, true);
        verify(state.buildup < 0.01);
        compare(state.envelope, 0);
    }

    function test_stalled_audio_releases_and_resets_detection() {
        let state = Party.advanceImpact(null, 1, 16, true);
        for (let frame = 0; frame < 300; ++frame) {
            state = Party.advanceImpact(state, 1, 16, true, undefined, false);
            verify(!state.hit);
        }
        compare(state.envelope, 0);
        verify(state.buildup < 0.01, "stale high bins must not sustain the camera");
        state = Party.advanceImpact(state, 0.5, 16, true);
        verify(state.hit, "reconnected audio must not inherit a stale high trough");
        compare(state.intervals.length, 0);
    }

    function test_invalid_values_and_delayed_frames_keep_motion_finite() {
        let state = Party.idleImpact();
        for (const dt of [0, -10, NaN, Infinity, 16, 8000]) {
            for (const level of [NaN, Infinity, -1, 0, 0.5, 2]) {
                state = Party.advanceImpact(state, level, dt, true);
                verify(Number.isFinite(state.envelope));
                verify(state.envelope >= 0 && state.envelope <= 1);
                verify(Number.isFinite(state.buildup));
                const shake = Party.impactShake(state);
                verify(Number.isFinite(shake.x) && Math.abs(shake.x) <= 1);
                verify(Number.isFinite(shake.y) && Math.abs(shake.y) <= 1);
            }
        }
    }

    function test_camera_adapts_on_the_first_fast_followup() {
        let impact = Party.idleImpact();
        let camera = Party.idleCamera();
        for (let beat = 0; beat < 6; ++beat) {
            const previousAge = impact.age;
            impact = Party.advanceImpact(impact, 1, 16, true);
            camera = Party.advanceCamera(camera, impact, previousAge, 16);
            for (let frame = 0; frame < 36; ++frame) {
                const age = impact.age;
                impact = Party.advanceImpact(impact, 0, 16, true);
                camera = Party.advanceCamera(camera, impact, age, 16);
            }
        }
        const age = impact.age;
        impact = Party.advanceImpact(impact, 1, 16, true);
        camera = Party.advanceCamera(camera, impact, age, 16);
        for (let beat = 0; beat < 12; ++beat) {
            for (let frame = 0; frame < 4; ++frame) {
                const oldCamera = camera;
                const previousAge = impact.age;
                impact = Party.advanceImpact(impact, frame === 3 ? 1 : 0, 16, true);
                camera = Party.advanceCamera(camera, impact, previousAge, 16);
                if (frame === 3 || beat > 0) {
                    verify(camera.density > 0.8, "protect the first fast beat before tempo adapts");
                    verify(Math.abs(camera.envelope - oldCamera.envelope) * 0.3 <= 0.0101,
                        "dense motion must stay below one percent zoom travel per 16ms");
                    verify(Math.abs(camera.x - oldCamera.x) < 0.03,
                        "changing direction must ease the existing recoil");
                }
                if (frame === 3)
                    verify(impact.hit, "camera smoothing preserves detected fast beats");
            }
        }
        for (let frame = 0; frame < 300; ++frame) {
            const previousAge = impact.age;
            impact = Party.advanceImpact(impact, 1, 16, true);
            camera = Party.advanceCamera(camera, impact, previousAge, 16);
        }
        compare(camera.envelope, 0);
        verify(camera.density < 0.01);
        impact = Party.advanceImpact(impact, 0, 16, true);
        const previousAge = impact.age;
        impact = Party.advanceImpact(impact, 1, 16, true);
        camera = Party.advanceCamera(camera, impact, previousAge, 16);
        compare(camera.envelope, impact.envelope, "an isolated beat regains its sharp attack");
    }

    function test_camera_handles_coincident_and_invalid_frame_times() {
        const impact = Party.advanceImpact(null, 1, 16, true);
        const first = Party.advanceCamera(null, impact, 10000, 16);
        for (const dt of [0, -1, NaN, Infinity]) {
            const fast = Object.assign({}, impact, {interval: 64});
            const camera = Party.advanceCamera(first, fast, 64, dt);
            compare(camera.envelope, first.envelope);
            compare(camera.x, first.x);
            compare(camera.y, first.y);
            verify(camera.density > 0.8);
        }
    }

    function test_sample_level_spans_the_array() {
        const levels = [0, 0.5, 1];
        compare(Party.sampleLevel(levels, 0, 3), 0);
        verify(Math.abs(Party.sampleLevel(levels, 1, 3) - 0.5) < 0.000001);
        compare(Party.sampleLevel(levels, 2, 3), 1);
        compare(Party.sampleLevel([], 2, 4), 0);
    }

    function test_shake_is_zero_at_rest_and_bounded() {
        const rest = Party.shake(0, 1.25, 3);
        compare(rest.x, 0);
        compare(rest.y, 0);
        compare(rest.rotation, 0);

        for (let time = 0; time < 4; time += 0.13) {
            const value = Party.shake(1, time, 7);
            verify(value.x >= -1 && value.x <= 1);
            verify(value.y >= -1 && value.y <= 1);
            verify(value.rotation >= -1 && value.rotation <= 1);
        }
    }

    function test_shake_is_deterministic() {
        const a = Party.shake(0.8, 2.2, 5);
        const b = Party.shake(0.8, 2.2, 5);
        compare(a.x, b.x);
        compare(a.y, b.y);
        compare(a.rotation, b.rotation);
    }
}
