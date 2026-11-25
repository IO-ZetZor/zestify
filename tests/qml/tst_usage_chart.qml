import QtQuick
import QtTest
import "../../shell/components"
import "../../shell/lib/usage.js" as Usage

Item {
    width: 400; height: 220
    Theme { id: theme }
    UsageChart { id: chart; width: 400; height: 140; theme: theme; capacity: 8 }
    TestCase {
        name: "UsageChart"
        when: windowShown
        function init() {
            chart.width = 400; chart.height = 140;
            chart.values = [10, 20, 30, 40, 50, 60, 70, 80];
            chart.secondaryValues = [80, 70, 60, 50, 40, 30, 20, 10];
            chart.maximum = 100;
            chart.rebuild();
            wait(50);
        }
        function assertMatchesFullPaint() {
            const plot = findChild(chart, "usagePlot");
            wait(50);
            const partial = grabImage(chart);
            plot.requestPaint();
            wait(50);
            const full = grabImage(chart);
            for (let y = 0; y < chart.height; y++)
                for (let x = 0; x < chart.width; x++)
                    compare(partial.pixel(x, y), full.pixel(x, y), "pixel " + x + "," + y);
        }
        function test_partial_edit_and_secondary_removal_match_full_repaint() {
            chart.values = [10, 20, 30, 85, 50, 60, 70, 80];
            assertMatchesFullPaint();
            chart.secondaryValues = [];
            assertMatchesFullPaint();
            chart.values = [];
            assertMatchesFullPaint();
        }
        function test_rolling_resize_and_rescale_match_full_repaint() {
            chart.values = [20, 30, 40, 50, 60, 70, 80, 90];
            assertMatchesFullPaint();
            chart.width = 360;
            chart.maximum = 200;
            assertMatchesFullPaint();
        }
        function test_dirty_span_includes_adjacent_segments() {
            const before = Usage.points([10, 20, 30, 40, 50, 60, 70, 80], 8, 100, 350, 100);
            const same = Usage.points([10, 20, 30, 40, 50, 60, 70, 80], 8, 100, 350, 100);
            compare(Usage.dirtySpan(before, same, 350, 5), null);
            const after = Usage.points([10, 20, 30, 85, 50, 60, 70, 80], 8, 100, 350, 100);
            const span = Usage.dirtySpan(before, after, 350, 5);
            compare(span.x, 95); compare(span.right, 205);
            const shifted = Usage.points([20, 30, 40, 50, 60, 70, 80, 90], 8, 100, 350, 100);
            const whole = Usage.dirtySpan(before, shifted, 350, 5);
            compare(whole.x, 0); compare(whole.right, 350);
        }
    }
}
