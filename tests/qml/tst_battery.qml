import QtQuick
import QtTest
import "../../shell/lib/battery.js" as Battery

TestCase {
    name: "Battery"

    function test_charging_and_unknown_icons() {
        compare(Battery.icon(-1, false), "󰂑");
        compare(Battery.icon(55, true), "󰂄");
    }

    function test_level_icons_follow_charge_boundaries() {
        const cases = [
            [0, "󰁺"],
            [10, "󰁺"],
            [11, "󰁻"],
            [20, "󰁻"],
            [21, "󰁼"],
            [30, "󰁼"],
            [31, "󰁽"],
            [40, "󰁽"],
            [41, "󰁾"],
            [50, "󰁾"],
            [51, "󰁿"],
            [60, "󰁿"],
            [61, "󰂀"],
            [70, "󰂀"],
            [71, "󰂁"],
            [80, "󰂁"],
            [81, "󰂂"],
            [90, "󰂂"],
            [91, "󰁹"],
            [100, "󰁹"]
        ];

        for (const entry of cases)
            compare(Battery.icon(entry[0], false), entry[1]);
    }

    function test_tone_prioritises_charging_then_level() {
        compare(Battery.tone(5, true), "charging");
        compare(Battery.tone(-1, false), "unknown");
        compare(Battery.tone(20, false), "danger");
        compare(Battery.tone(21, false), "warning");
        compare(Battery.tone(40, false), "warning");
        compare(Battery.tone(41, false), "healthy");
    }
}
