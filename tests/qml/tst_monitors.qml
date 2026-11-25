import QtQuick
import QtTest
import "../../shell/lib/monitors.js" as Monitors

TestCase {
    name: "MonitorWidgets"
    function test_primary_hotplug_fallback_always_keeps_a_pill() {
        const screens = [{name: "HDMI-A-1"}, {name: "eDP-1"}];
        compare(Monitors.primaryName(screens, "eDP-1"), "eDP-1");
        const fallback = Monitors.primaryName(screens.slice(0, 1), "eDP-1");
        compare(fallback, "HDMI-A-1");
        compare(Monitors.widgetMode(fallback, fallback, "none", {"HDMI-A-1": "focus"}), "pill");
        compare(Monitors.primaryName([], "eDP-1"), "");
    }
    function test_secondary_defaults_overrides_and_invalid_config() {
        compare(Monitors.widgetMode("HDMI-A-1", "eDP-1", "focus", {}), "focus");
        compare(Monitors.widgetMode("HDMI-A-1", "eDP-1", "pill", {}), "pill");
        compare(Monitors.widgetMode("HDMI-A-1", "eDP-1", "focus", {"HDMI-A-1": "none"}), "none");
        compare(Monitors.widgetMode("DP-1.2", "eDP-1", "pill", {"DP-1.2": "focus"}), "focus");
        compare(Monitors.widgetMode("DP-1", "eDP-1", "bad", null), "focus");
    }
}
