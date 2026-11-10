import QtQuick
import QtTest
import "../../shell/lib/usage.js" as Usage

TestCase {
    name: "Usage"

    function test_partial_history_ends_at_now() {
        const points = Usage.points([0, 50, 100], 5, 100, 100, 80);
        compare(points.length, 3);
        compare(points[0].x, 50);
        compare(points[2].x, 100);
        compare(points[0].y, 80);
        compare(points[1].y, 40);
        compare(points[2].y, 0);
    }

    function test_hover_ignores_unsampled_history() {
        compare(Usage.sampleAt([20, 40], 5, 0), null);
        compare(Usage.sampleAt([20, 40], 5, 0.75), 20);
        compare(Usage.sampleAt([20, 40], 5, 1), 40);
        compare(Usage.sampleAt([], 5, 1), null);
    }

    function test_network_scale_covers_both_directions() {
        compare(Usage.scaleFor([1025], [4097]), 8192);
        compare(Usage.scaleFor([], []), 1024);
    }

    function test_values_stay_inside_graph() {
        const points = Usage.points([-10, 110, NaN], 3, 100, 100, 80);
        compare(points[0].y, 80);
        compare(points[1].y, 0);
        compare(points[2].y, 80);
        compare(Usage.percent(50, 0), 0);
        compare(Usage.percent(200, 100), 100);
    }
}
