import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 400
    height: 300

    Theme { id: fixtureTheme }

    EdgeVisualiser {
        id: topBars
        anchors.fill: parent
        edge: "top"
        barCount: 4
        levels: [0, 0.25, 0.75, 1]
        theme: fixtureTheme
        s: 1
    }

    EdgeVisualiser {
        id: leftBars
        anchors.fill: parent
        edge: "left"
        barCount: 4
        levels: [0.5, 0.5, 0.5, 0.5]
        theme: fixtureTheme
        s: 1
    }

    TestCase {
        name: "EdgeVisualiser"
        when: windowShown

        function init() {
            topBars.barCount = 4;
            topBars.levels = [0, 0.25, 0.75, 1];
            leftBars.barCount = 4;
            leftBars.levels = [0.5, 0.5, 0.5, 0.5];
            wait(10);
        }

        function test_top_bars_sit_on_the_top_edge_and_grow_inward() {
            const quiet = findChild(topBars, "edgeBar0");
            const loud = findChild(topBars, "edgeBar3");
            verify(quiet !== null);
            verify(loud !== null);
            compare(quiet.y, 0);
            compare(loud.y, 0);
            verify(loud.height > quiet.height, "louder bars must grow inward");
        }

        function test_left_bars_sit_on_the_left_edge_and_grow_inward() {
            const bar = findChild(leftBars, "edgeBar0");
            verify(bar !== null);
            compare(bar.x, 0);
            verify(bar.width > 0);
        }

        function test_levels_can_be_pushed_after_creation() {
            const before = findChild(topBars, "edgeBar1").height;
            topBars.levels = [0, 1, 0, 0];
            wait(10);
            const after = findChild(topBars, "edgeBar1").height;
            verify(after > before, "changing levels should update delegate heights");
        }

        function test_bar_count_controls_delegate_count() {
            topBars.barCount = 2;
            wait(10);
            verify(findChild(topBars, "edgeBar1") !== null);
            verify(findChild(topBars, "edgeBar2") === null);
        }
    }
}
