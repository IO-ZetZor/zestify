import QtQuick
import QtTest
import "../../shell/lib/config.js" as ConfigLib

TestCase {
    name: "ConfigLib"

    function test_setValue_updates_nested_data() {
        const data = { theme: { transparency: 0.88 } };
        ConfigLib.setValue(data, "theme.transparency", 0.5);
        compare(data.theme.transparency, 0.5);
    }

    function test_setValue_creates_missing_intermediate_objects() {
        const data = {};
        ConfigLib.setValue(data, "theme.transparency", 0.5);
        compare(data.theme.transparency, 0.5);
    }

    function test_setValue_replaces_null_intermediate() {
        const data = {theme: null};
        ConfigLib.setValue(data, "theme.mode", "light");
        compare(data.theme.mode, "light");
    }

    function test_setValue_rejects_unsafe_or_empty_paths() {
        for (const path of ["__proto__.polluted", "constructor.prototype.polluted", "", "theme..mode"]) {
            let failed = false;
            try { ConfigLib.setValue({}, path, true); } catch (error) { failed = true; }
            verify(failed, path);
        }
        compare(({}).polluted, undefined);
    }

    function test_setValue_overwrites_existing_value() {
        const data = { bar: { height: 34 } };
        ConfigLib.setValue(data, "bar.height", 42);
        compare(data.bar.height, 42);
    }

    function test_getValue_returns_existing_value() {
        const data = { theme: { mode: "dark" } };
        compare(ConfigLib.getValue(data, "theme.mode"), "dark");
    }

    function test_getValue_returns_fallback_for_missing_key() {
        const data = {};
        compare(ConfigLib.getValue(data, "theme.transparency", 0.88), 0.88);
    }

    function test_getValue_returns_fallback_for_missing_intermediate() {
        const data = { theme: {} };
        compare(ConfigLib.getValue(data, "theme.transparency", 0.88), 0.88);
    }

    function test_setValue_boolean_roundtrip() {
        const data = { notifications: { dnd: false } };
        ConfigLib.setValue(data, "notifications.dnd", true);
        compare(ConfigLib.getValue(data, "notifications.dnd"), true);
    }

    function test_setValue_string_roundtrip() {
        const data = { theme: { mode: "dark" } };
        ConfigLib.setValue(data, "theme.mode", "light");
        compare(ConfigLib.getValue(data, "theme.mode"), "light");
    }

    function test_getValue_int_roundtrip() {
        const data = { bar: { height: 34 } };
        compare(ConfigLib.getValue(data, "bar.height"), 34);
    }
}
