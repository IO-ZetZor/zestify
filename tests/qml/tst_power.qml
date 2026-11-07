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
}
