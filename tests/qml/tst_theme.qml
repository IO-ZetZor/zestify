import QtQuick
import QtTest
import "../../shell/components"

TestCase {
    name: "Theme"

    Component {
        id: themeComponent
        Theme {}
    }

    function test_maps_scheme_colours() {
        const theme = themeComponent.createObject(null, {
            scheme: {
                colours: {
                    onSurface: "#e6e4f0",
                    primary: "#bfc4ee",
                    error: "#f97386",
                    surface: "#020305"
                }
            }
        });
        compare(String(theme.cream), "#e6e4f0");
        compare(String(theme.accent), "#bfc4ee");
        compare(String(theme.danger), "#f97386");
        compare(String(theme.surface), "#020305");
        theme.destroy();
    }

    function test_applies_alpha() {
        const theme = themeComponent.createObject(null, { scheme: { colours: {} } });
        compare(String(theme.withAlpha("#bfc4ee", 0.25)), "#40bfc4ee");
        theme.destroy();
    }
}
