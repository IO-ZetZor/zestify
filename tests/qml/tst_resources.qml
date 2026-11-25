import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 500
    height: 100

    Theme { id: fixtureTheme }
    QtObject {
        id: telemetry
        property real cpuPercent: 0
        property real ramUsed: 1073741824
        property real ramTotal: 16 * 1073741824
    }
    QtObject { id: motion; property bool calm: false }
    Resources { id: resources; theme: fixtureTheme; stats: telemetry; motion: motion }
    SignalSpy { id: clicks; target: resources; signalName: "clicked" }

    TestCase {
        name: "Resources"
        when: windowShown

        function init() {
            resources.stats = telemetry;
            resources.s = 1;
            fixture.visible = true;
            motion.calm = false;
            telemetry.cpuPercent = 0;
            clicks.clear();
        }

        function test_strict_threshold_data() {
            return [
                {tag: "idle", cpu: 0, shown: false},
                {tag: "near-threshold", cpu: 89.9, shown: false},
                {tag: "threshold", cpu: 90, shown: false},
                {tag: "above-threshold", cpu: 90.01, shown: true},
                {tag: "full-load", cpu: 100, shown: true},
                {tag: "invalid", cpu: NaN, shown: false},
                {tag: "infinite", cpu: Infinity, shown: false}
            ];
        }

        function test_strict_threshold(data) {
            telemetry.cpuPercent = data.cpu;
            compare(resources.visible, data.shown);
            compare(resources.animating, data.shown);
        }

        function test_missing_stats() {
            resources.stats = null;
            verify(!resources.visible);
            verify(!resources.animating);
        }

        function test_pulse_stops_below_threshold_and_when_hidden() {
            telemetry.cpuPercent = 95;
            tryVerify(() => resources.pulse > 0.1);
            fixture.visible = false;
            verify(!resources.animating);
            compare(resources.pulse, 0);
            fixture.visible = true;
            tryVerify(() => resources.pulse > 0.1);
            telemetry.cpuPercent = 90;
            verify(!resources.visible);
            verify(!resources.animating);
            compare(resources.pulse, 0);
            wait(100);
            compare(resources.pulse, 0);
        }

        function test_calm_mode_and_click() {
            telemetry.cpuPercent = 95;
            motion.calm = true;
            verify(resources.visible);
            verify(!resources.animating);
            compare(resources.pulse, 0);
            mouseClick(resources);
            compare(clicks.count, 1);
        }

        function test_high_load_does_not_resize_the_icon() {
            for (const scale of [1, 1.5]) {
                resources.s = scale;
                telemetry.cpuPercent = 91;
                const width = resources.implicitWidth;
                for (const value of [91, 95, 99, 100]) {
                    telemetry.cpuPercent = value;
                    telemetry.ramUsed = value / 100 * telemetry.ramTotal;
                    wait(20);
                    compare(resources.implicitWidth, width);
                    compare(resources.implicitHeight, 22 * scale);
                }
            }
        }
    }
}
