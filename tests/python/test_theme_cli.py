"""Application-theme CLI integration through temporary XDG configurations."""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from zesti.paths import Paths


REPO = Path(__file__).resolve().parents[2]
ZESTI = REPO / "bin/zesti"

DARK = {
    "primary": "8bceff", "onPrimary": "173348",
    "secondary": "b7c9d9", "onSecondary": "21323e",
    "tertiary": "d1bce7", "onTertiary": "382b49",
    "surface": "1a1c1e", "surfaceVariant": "43474b",
    "onSurface": "e2e2e2", "onSurfaceVariant": "c3c7cb",
    "background": "1a1c1e", "onBackground": "e2e2e2",
    "outline": "8d9195", "error": "ff5449", "onError": "690005",
}
LIGHT = dict(DARK, background="f8fafc", surface="f8fafc",
             onBackground="18212a", onSurface="18212a", primary="27628b")
SCHEME = {
    "name": "test", "mode": "dark", "colours": DARK,
    "palettes": {"dark": DARK, "light": LIGHT},
}


class ThemeCliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = dict(os.environ)
        self.env.update({
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "DBUS_SESSION_BUS_ADDRESS": "",
            "WAYLAND_DISPLAY": "",
            "DISPLAY": "",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        # App reloads may run only in the test environment. Intercept the kill
        # executable as an extra guard beyond the adapter's XDG process filter.
        self.bin = self.root / "bin"
        self.bin.mkdir()
        kill = self.bin / "kill"
        kill.write_text("#!/bin/sh\nexit 0\n")
        kill.chmod(0o755)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env.get("PATH", "")
        self.paths = Paths.from_env(self.env)
        self.config = {"monitor": {"primary": "eDP-1"}, "theme": {"mode": "dark", "apply": True}}
        self.write_json(self.paths.config_file, self.config)
        self.write_json(self.paths.scheme_file, SCHEME)

    def tearDown(self):
        self.temp.cleanup()

    def write_json(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def run_zesti(self, *args):
        return subprocess.run([sys.executable, str(ZESTI), *args], env=self.env,
                              text=True, capture_output=True, timeout=20)

    def settings(self):
        path = self.paths.config_home / "kitty/zestify-colors.conf"
        return dict(line.split(None, 1) for line in path.read_text().splitlines()
                    if line.strip() and not line.lstrip().startswith("#"))

    def assert_application_outputs(self, result):
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertTrue(json.loads(result.stdout)["ok"], result.stdout)
        self.assertEqual(self.settings()["background"], "#1a1c1e")
        self.assertEqual(self.settings()["foreground"], "#e2e2e2")
        for relative in ("zestify/theme/gtk.css", "qtengine/zestify.colors", "fuzzel/fuzzel.ini", "cava/config"):
            self.assertTrue((self.paths.config_home / relative).is_file(), relative)
        kitty_config = self.paths.config_home / "kitty/kitty.conf"
        self.assertIn("include " + str(self.paths.config_home / "kitty/zestify-colors.conf"), kitty_config.read_text())

    def test_theme_apply_runs_real_application_adapters(self):
        self.assert_application_outputs(self.run_zesti("theme", "apply"))

    def test_scheme_apply_runs_real_application_adapters(self):
        self.assert_application_outputs(self.run_zesti("scheme", "apply"))

    def test_wallpaper_cli_applies_generated_palette_to_apps(self):
        image = self.root / "wallpaper.png"
        Image.new("RGB", (8, 8), (23, 41, 54)).save(image)
        result = self.run_zesti("wallpaper", "set", str(image), "--all")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertTrue(json.loads(result.stdout)["ok"])
        generated = json.loads(self.paths.scheme_file.read_text())["palettes"]["dark"]
        self.assertEqual(self.settings()["background"], "#" + generated["background"])
        self.assertEqual(self.settings()["foreground"], "#" + generated["onBackground"])
        self.assertEqual(self.settings()["cursor"], "#" + generated["primary"])
        self.assertTrue((self.paths.config_home / "zestify/theme/gtk.css").is_file())
        self.assertTrue((self.paths.config_home / "qtengine/zestify.colors").is_file())

    def test_config_mode_updates_generated_colors_for_both_apply_commands(self):
        self.assert_application_outputs(self.run_zesti("theme", "apply"))
        self.config["theme"]["mode"] = "light"
        self.write_json(self.paths.config_file, self.config)
        light = self.run_zesti("scheme", "apply")
        self.assertEqual(light.returncode, 0, light.stderr or light.stdout)
        self.assertEqual(self.settings()["background"], "#f8fafc")
        self.assertEqual(self.settings()["foreground"], "#18212a")
        self.config["theme"]["mode"] = "dark"
        self.write_json(self.paths.config_file, self.config)
        self.assert_application_outputs(self.run_zesti("theme", "apply"))
        self.assertEqual(json.loads(self.paths.scheme_file.read_text()), SCHEME)

    def test_theme_list_identifies_targets_and_application_paths(self):
        result = self.run_zesti("theme", "list")
        self.assertEqual(result.returncode, 0, result.stderr)
        targets = {target["name"]: target for target in json.loads(result.stdout)}
        self.assertTrue({"colors", "gtk", "qt", "fuzzel", "cava"} <= targets.keys())
        self.assertEqual(targets["colors"]["output"], str(self.paths.config_home / "kitty/zestify-colors.conf"))
        self.assertEqual(targets["qt"]["output"], str(self.paths.config_home / "qtengine/zestify.colors"))
        self.assertTrue(targets["colors"]["enabled"])
        self.assertFalse((self.paths.config_home / "kitty/kitty.conf").exists())

    def test_theme_show_reports_config_selected_palette(self):
        self.config["theme"]["mode"] = "light"
        self.write_json(self.paths.config_file, self.config)
        result = self.run_zesti("theme", "show")
        self.assertEqual(result.returncode, 0, result.stderr)
        shown = json.loads(result.stdout)
        self.assertEqual(shown["mode"], "light")
        self.assertEqual(shown["colours"]["primary"], LIGHT["primary"])
        self.assertEqual(shown["colours"]["background"], LIGHT["background"])
        self.assertFalse((self.paths.config_home / "kitty/kitty.conf").exists())

    def test_primary_override_selects_apps_and_secondary_override_does_not(self):
        self.paths.monitor_dir.mkdir(parents=True, exist_ok=True)
        primary = copy.deepcopy(SCHEME)
        primary["palettes"]["dark"]["background"] = "112233"
        secondary = copy.deepcopy(SCHEME)
        secondary["palettes"]["dark"]["background"] = "445566"
        (self.paths.monitor_dir / "edp-1.txt").write_text("/temporary/primary.png")
        (self.paths.monitor_dir / "dp-1.txt").write_text("/temporary/secondary.png")
        self.write_json(self.paths.monitor_dir / "edp-1-scheme.json", primary)
        self.write_json(self.paths.monitor_dir / "dp-1-scheme.json", secondary)
        result = self.run_zesti("theme", "apply")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(self.settings()["background"], "#112233")
        # An empty primary wallpaper override makes its old scheme inactive.
        (self.paths.monitor_dir / "edp-1.txt").write_text("")
        result = self.run_zesti("theme", "apply")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(self.settings()["background"], "#1a1c1e")

    def test_target_failure_is_reported_without_rolling_back_palette_or_other_outputs(self):
        self.config["theme"]["apply"] = {
            "broken": {"template": "color=#{missingRole}", "output": str(self.root / "broken.txt")},
        }
        self.write_json(self.paths.config_file, self.config)
        result = self.run_zesti("theme", "apply")
        self.assertEqual(result.returncode, 1, result.stdout)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        failures = [target for target in payload["targets"] if not target["ok"]]
        self.assertEqual([target["target"] for target in failures], ["broken"])
        self.assertIn("missingRole", failures[0]["error"])
        self.assertIn("broken", result.stderr)
        self.assertEqual(self.settings()["background"], "#1a1c1e")
        self.assertEqual(json.loads(self.paths.scheme_file.read_text()), SCHEME)
        self.assertFalse((self.root / "broken.txt").exists())

    def test_global_theme_disable_leaves_app_configs_untouched(self):
        self.config["theme"]["apply"] = False
        self.write_json(self.paths.config_file, self.config)
        result = self.run_zesti("theme", "apply")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertTrue(json.loads(result.stdout)["ok"])
        self.assertFalse((self.paths.config_home / "kitty/kitty.conf").exists())


if __name__ == "__main__":
    unittest.main()
