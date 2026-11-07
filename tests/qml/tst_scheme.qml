import QtQuick
import QtTest
import "../../shell/lib/scheme.js" as Scheme

TestCase {
    name: "Scheme"

    function test_prefers_monitor_scheme() {
        const global = { colours: { surface: "#111111" } };
        const monitors = { "HDMI-A-1": { colours: { surface: "#222222" } } };
        compare(Scheme.pick(global, monitors, "HDMI-A-1").colours.surface, "#222222");
    }

    function test_falls_back_to_global_scheme() {
        const global = { colours: { surface: "#111111" } };
        const monitors = { "HDMI-A-1": { colours: { surface: "#222222" } } };
        compare(Scheme.pick(global, monitors, "eDP-1").colours.surface, "#111111");
    }

    function test_falls_back_to_builtin_dark_scheme() {
        const scheme = Scheme.pick(null, null, "missing");
        compare(typeof scheme.colours.surface, "string");
        verify(scheme.colours.surface.length > 0);
        compare(scheme.mode, "dark");
    }
}
