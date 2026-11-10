import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/surfaces"
import "../../shell/singletons"

ShellRoot {
    id: root

    Theme {
        id: theme
        transparency: Config.theme.transparency
        mode: Config.theme.mode
        scheme: ({
            colors: {
                primary: { dark: { color: "80aabb" }, light: { color: "225566" } }
            }
        })
    }

    Item {
        width: 760
        height: 600

        ConfigSurface {
            id: surface
            anchors.fill: parent
            theme: theme
        }

        PillBody {
            id: body
            theme: theme
            backgroundOpacity: Config.bar.opacity
        }
    }

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    function find(item, predicate) {
        if (predicate(item))
            return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; i++) {
            const result = root.find(children[i], predicate);
            if (result)
                return result;
        }
        return null;
    }

    function rowFor(path) {
        return root.find(surface, item => item.modelData && item.modelData.path === path);
    }

    function run() {
        try {
            let toggles = 0;
            for (const section of surface.sections) {
                for (const entry of section.rows) {
                    if (entry.kind !== "boolean")
                        continue;
                    const row = root.rowFor(entry.path);
                    const toggle = row ? root.find(row, item => typeof item.toggled === "function") : null;
                    root.check(toggle !== null, "Missing toggle: " + entry.path);
                    const before = Config.value(entry.path, entry.fallback);
                    toggle.toggled();
                    root.check(Config.value(entry.path) === !before, "Toggle did not apply: " + entry.path);
                    root.check(toggle.checked === !before, "Toggle did not update: " + entry.path);
                    toggle.toggled();
                    root.check(Config.value(entry.path) === before, "Toggle did not restore: " + entry.path);
                    toggles++;
                }
            }
            root.check(toggles > 10, "Settings rows were not loaded");

            const transparencyRow = root.rowFor("theme.transparency");
            const slider = root.find(transparencyRow, item => typeof item.moveTo === "function");
            root.check(slider !== null && slider.width > 0, "Missing transparency slider");
            for (const value of [0.25, 0.75]) {
                slider.moveTo(slider.width * value);
                root.check(Math.abs(Config.theme.transparency - value) < 0.01, "Slider did not update config during movement");
                root.check(Math.abs(body.gradient.stops[0].color.a - value * Config.bar.opacity) < 0.01,
                    "Pill did not update transparency during movement");
            }
            const modeRow = root.rowFor("theme.mode");
            const choice = root.find(modeRow, item => typeof item.chosen === "function");
            choice.chosen("light");
            root.check(String(theme.accent) === "#225566", "Light mode did not apply");
            choice.chosen("dark");
            root.check(String(theme.accent) === "#80aabb", "Dark mode did not apply");
            console.log("SETTINGS PASS: " + toggles + " toggles, live transparency, live theme mode");
        } catch (error) {
            console.error("SETTINGS FAIL: " + error);
        }
        Qt.quit();
    }

    Timer {
        interval: 100
        running: true
        onTriggered: root.run()
    }
}
