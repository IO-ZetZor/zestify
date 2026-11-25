import QtQuick
import QtTest
import "../../shell/lib/party.js" as Party
import "../../shell/lib/visualiser.js" as Visualiser

TestCase {
    name: "PartyAnalysis"

    function bins(value, index) {
        const result = Array(32).fill(0);
        result[15 - (index || 0)] = value;
        result[16 + (index || 0)] = value;
        return result;
    }

    function test_constant_energy_pitch_changes_do_not_trigger() {
        let state = Party.advanceAnalysis(null, bins(0.2), 16.67);
        verify(state.onset);
        for (let frame = 0; frame < 180; ++frame) {
            state = Party.advanceAnalysis(state, bins(0.2, Math.floor(frame / 6) % 5), 16.67);
            verify(!state.onset, "moving a held note between bass bins is not an impact");
        }
    }

    function test_panning_does_not_trigger() {
        let state = Party.advanceAnalysis(null, bins(0.2), 16.67);
        for (let frame = 0; frame < 120; ++frame) {
            const next = bins(0.2);
            next[frame % 2 ? 15 : 16] = 0;
            state = Party.advanceAnalysis(state, next, 16.67);
            verify(!state.onset);
        }
    }

    function test_new_energy_over_held_bass_is_detected() {
        let state = Party.advanceAnalysis(null, bins(0.15), 16.67);
        for (let frame = 0; frame < 30; ++frame)
            state = Party.advanceAnalysis(state, bins(0.15), 16.67);
        const kick = bins(0.15);
        kick[12] = 0.2;
        kick[19] = 0.2;
        state = Party.advanceAnalysis(state, kick, 16.67);
        verify(state.onset, "an overlapping kick must add genuine bass energy");
    }

    function test_display_gain_cannot_change_impact_strength() {
        const levels = bins(0.035);
        const lowGain = Visualiser.displayLevels(1, levels, 16.67);
        const highGain = Visualiser.displayLevels(0.02, levels, 16.67);
        verify(highGain.values[15] > lowGain.values[15] * 10);
        const analysis = Party.advanceAnalysis(null, levels, 16.67);
        const impact = Party.advanceImpact(null, analysis.level, 16.67, true, undefined, true, 0, analysis);
        verify(impact.hit);
        verify(impact.intrinsicStrength > 0 && impact.intrinsicStrength < 0.1);
        compare(levels[15], 0.035);
    }

    function test_weaker_adjacent_kick_over_a_held_note_is_detected() {
        let state = Party.advanceAnalysis(null, bins(0.2), 16.67);
        for (let frame = 0; frame < 60; ++frame)
            state = Party.advanceAnalysis(state, bins(0.2), 16.67);
        const kick = bins(0.2);
        kick[14] = 0.1;
        kick[17] = 0.1;
        state = Party.advanceAnalysis(state, kick, 16.67);
        verify(state.onset);
    }

    function test_source_spacing_survives_zero_time_delivery() {
        let analysis = Party.idleAnalysis();
        let impact = Party.idleImpact();
        for (let frame = 0; frame < 80; ++frame) {
            analysis = Party.advanceAnalysis(analysis, bins(frame % 4 === 0 ? 0.2 : 0), 16.67);
            impact = Party.advanceImpact(impact, analysis.level, 0, true, undefined, true, 0, analysis);
            if (frame % 4 === 0) {
                verify(impact.hit);
                if (frame > 0)
                    verify(Math.abs(impact.gap - 66.68) < 0.01);
            }
        }
    }

    function test_rhythm_ignores_weak_subdivisions_and_decays() {
        let rhythm = Party.idleRhythm();
        let sequence = 0;
        for (let frame = 0; frame < 48; ++frame)
            rhythm = Party.advanceRhythm(rhythm,
                {hit: true, sequence: ++sequence, intrinsicStrength: frame % 4 === 0 ? 0.8 : 0.08}, 125);
        verify(Math.abs(rhythm.period - 500) < 1);
        verify(rhythm.confidence > 0.65);
        rhythm = Party.advanceRhythm(rhythm, {hit: false, sequence: sequence, intrinsicStrength: 0.08}, 5000);
        verify(rhythm.confidence < 0.15);
    }

    function test_irregular_attacks_do_not_gain_confidence_on_render_ticks() {
        let rhythm = Party.idleRhythm();
        let sequence = 0;
        for (const gap of [330, 711, 259, 1090, 457, 826, 603])
            rhythm = Party.advanceRhythm(rhythm, {hit: true, sequence: ++sequence, intrinsicStrength: 0.8}, gap);
        verify(rhythm.confidence < 0.6);
        const confidence = rhythm.confidence;
        for (let frame = 0; frame < 60; ++frame)
            rhythm = Party.advanceRhythm(rhythm, {hit: false, sequence: sequence, intrinsicStrength: 0.8}, 16.67);
        verify(rhythm.confidence < confidence || confidence === 0);
        rhythm = Party.advanceRhythm(rhythm, {hit: false, sequence: sequence, intrinsicStrength: 0}, Infinity);
        verify(Number.isFinite(rhythm.time));
    }

    function test_tint_does_not_flash_on_batched_onsets() {
        let tint = 0.1;
        compare(Party.advanceTint(tint, 1, 0), tint);
        for (let frame = 0; frame < 120; ++frame) {
            const next = Party.advanceTint(tint, frame % 4 === 0 ? 1 : 0, 16.67);
            verify(Math.abs(next - tint) * 0.055 < 0.002);
            tint = next;
        }
        for (let frame = 0; frame < 150; ++frame)
            tint = Party.advanceTint(tint, 0, 16.67);
        compare(tint, 0);
    }

    function test_rhythm_follows_a_tempo_change() {
        let rhythm = Party.idleRhythm();
        let sequence = 0;
        for (let beat = 0; beat < 12; ++beat)
            rhythm = Party.advanceRhythm(rhythm, {hit: true, sequence: ++sequence, intrinsicStrength: 0.8}, 500);
        verify(Math.abs(rhythm.period - 500) < 1);
        for (let beat = 0; beat < 8; ++beat)
            rhythm = Party.advanceRhythm(rhythm, {hit: true, sequence: ++sequence, intrinsicStrength: 0.8}, 700);
        verify(Math.abs(rhythm.period - 700) < 1);
        verify(rhythm.confidence > 0.3);
    }

    function test_weak_subdivisions_do_not_inflate_rhythm_confidence() {
        let rhythm = Party.idleRhythm();
        let sequence = 0;
        for (let beat = 0; beat < 8; ++beat)
            rhythm = Party.advanceRhythm(rhythm, {hit: true, sequence: ++sequence, intrinsicStrength: 0.8}, 500);
        const confidence = rhythm.confidence;
        for (let beat = 0; beat < 10; ++beat)
            rhythm = Party.advanceRhythm(rhythm, {hit: true, sequence: ++sequence, intrinsicStrength: 0.03}, 60);
        verify(rhythm.confidence < confidence);
    }
}
