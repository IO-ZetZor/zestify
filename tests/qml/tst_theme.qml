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

    function test_wallpaper_palette_switches_mode_live() {
        const theme = themeComponent.createObject(null, {
            mode: "dark",
            scheme: {
                colors: {
                    primary: { dark: { color: "#80aabb" }, light: { color: "#225566" } },
                    on_surface: { dark: { color: "#eeeeee" }, light: { color: "#111111" } },
                    surface: { dark: { color: "#111111" }, light: { color: "#eeeeee" } }
                }
            }
        });
        verify(theme !== null);
        compare(String(theme.accent), "#80aabb");
        compare(String(theme.surface), "#111111");
        theme.mode = "light";
        compare(String(theme.accent), "#225566");
        compare(String(theme.surface), "#eeeeee");
        compare(String(theme.cream), "#111111");
        theme.destroy();
    }

    function test_saved_palette_switches_mode_live() {
        const theme = themeComponent.createObject(null, {
            mode: "dark",
            scheme: {
                colours: { primary: "80aabb" },
                palettes: { dark: { primary: "80aabb" }, light: { primary: "225566" } }
            }
        });
        verify(theme !== null);
        compare(String(theme.accent), "#80aabb");
        theme.mode = "light";
        compare(String(theme.accent), "#225566");
        theme.destroy();
    }
}
