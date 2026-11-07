import QtQuick
import QtTest
import "../../shell/lib/colour.js" as Colour

TestCase {
    name: "Colour"

    function test_normalizes_hex_values() {
        compare(Colour.normalizeHex("bfc4ee"), "#bfc4ee");
        compare(Colour.normalizeHex("#BF C4 EE".replace(/ /g, "")), "#bfc4ee");
    }

    function test_adds_alpha_channel() {
        compare(Colour.withAlpha("#bfc4ee", 0.25), "#40bfc4ee");
    }

    function test_detects_light_mode() {
        compare(Colour.isLight("light"), true);
        compare(Colour.isLight("dark"), false);
    }
}
