import QtQuick
import QtTest
import "../../shell/lib/visualiser.js" as Visualiser

TestCase {
    name: "Visualiser"

    function test_advance_moves_toward_target() {
        const result = Visualiser.advance([0, 0], [1, 0.5], 16, 180);

        verify(result.values[0] > 0 && result.values[0] < 1);
        verify(result.values[1] > 0 && result.values[1] < 0.5);
        verify(!result.settled);
    }

    function test_advance_settles_exactly_at_target() {
        const result = Visualiser.advance([1, 0.5], [1, 0.5], 16, 180);

        compare(result.values[0], 1);
        compare(result.values[1], 0.5);
        verify(result.settled);
    }

    function test_advance_is_time_independent() {
        // Two 8ms steps should land on the same value as one 16ms step.
        const twoSteps = Visualiser.advance(
            Visualiser.advance([0], [1], 8, 180).values, [1], 8, 180).values[0];
        const oneStep = Visualiser.advance([0], [1], 16, 180).values[0];

        verify(Math.abs(twoSteps - oneStep) < 0.000001,
               `8+8=${twoSteps} vs 16=${oneStep}`);
    }

    function test_advanced_values_never_overshoot() {
        let values = [0];

        for (let i = 0; i < 600; i++)
            values = Visualiser.advance(values, [1], 16, 180).values;

        verify(values[0] <= 1);
        verify(values[0] > 0.999);
    }

    function test_monstercat_carries_energy() {
        const smoothed = Visualiser.monstercat([1, 0, 0, 0, 0]);

        compare(smoothed[0], 1);
        verify(smoothed[1] > 0 && smoothed[1] < 1);
        verify(smoothed[2] > 0 && smoothed[2] < smoothed[1]);
        verify(smoothed[4] > 0, "right-to-left pass should reach the tail");
    }

    function test_monstercat_keeps_the_peak() {
        const smoothed = Visualiser.monstercat([0, 0, 0.8, 0, 0]);

        compare(smoothed[2], 0.8);
        verify(smoothed[1] > 0);
        verify(smoothed[3] > 0);
    }

    function test_monstercat_sides_do_not_bleed() {
        // Peak on the last left-channel bar; the right channel stays silent.
        const smoothed = Visualiser.monstercatSides([0, 0, 0, 0, 0, 0, 1, 0,
                                                    0, 0, 0, 0, 0, 0, 0, 0]);

        compare(smoothed[6], 1);
        for (let i = 8; i < 16; i++)
            compare(smoothed[i], 0);
    }

    function test_monstercat_sides_smooth_within_each_side() {
        const smoothed = Visualiser.monstercatSides([1, 0, 0, 0, 0, 0, 0, 0]);

        compare(smoothed[0], 1);
        verify(smoothed[1] > 0 && smoothed[1] < 1);
        verify(smoothed[2] > 0 && smoothed[2] < smoothed[1]);
        for (let i = 4; i < 8; i++)
            compare(smoothed[i], 0);
    }
}
