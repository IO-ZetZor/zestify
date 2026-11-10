import QtQuick
import QtTest
import "../../shell/lib/power.js" as Power

TestCase {
    name: "Power"

    function test_progress_accumulates_and_clamps() {
        compare(Power.progressAfter(0, 350, 700), 0.5);
        compare(Power.progressAfter(0.6, 350, 700), 1);
        compare(Power.progressAfter(0.2, 0, 700), 0.2);
        compare(Power.progressAfter(0, 100, 0), 1);
        compare(Power.progressAfter(1, -100, 700), 1);
    }

    function test_completion_threshold() {
        verify(Power.completes(0.5, 350, 700));
        verify(!Power.completes(0.4, 350, 700));
    }

    function test_fill_geometry_clamps_and_grows_upward() {
        var empty = Power.fillGeometry(0, 100);
        compare(empty.y, 100);
        compare(empty.height, 0);

        var half = Power.fillGeometry(0.5, 100);
        compare(half.y, 50);
        compare(half.height, 50);

        var full = Power.fillGeometry(1, 100);
        compare(full.y, 0);
        compare(full.height, 100);

        var clamped = Power.fillGeometry(2, 100);
        compare(clamped.y, 0);
        compare(clamped.height, 100);

        var invalid = Power.fillGeometry(-1, -20);
        compare(invalid.y, 0);
        compare(invalid.height, 0);

        var nonFinite = Power.fillGeometry(NaN, Infinity);
        compare(nonFinite.y, 0);
        compare(nonFinite.height, 0);
    }
}
