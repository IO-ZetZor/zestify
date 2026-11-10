"""Spotify palettes, preserved user themes, and Spicetify reload behavior."""

import configparser
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.theme import apply_theme, theme_targets

ROOT = Path(__file__).resolve().parents[2]


class SpicetifyThemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.paths = Paths.from_env({"XDG_CONFIG_HOME": self.temp.name + "/config",
                                     "XDG_STATE_HOME": self.temp.name + "/state",
                                     "XDG_DATA_HOME": self.temp.name + "/data",
                                     "XDG_CACHE_HOME": self.temp.name + "/cache"})
        self.directory = self.paths.config_home / "spicetify"
        self.original = self.directory / "Themes/custom"
        self.original.mkdir(parents=True)
        (self.original / "color.ini").write_text("[old]\nmain=123456\n")
        (self.original / "user.css").write_text(".player { opacity: 0.5; }\n")
        (self.original / "theme.js").write_text("// user's blur controls\n")
        (self.original / "assets").mkdir()
        (self.original / "assets/icon.png").write_bytes(b"image")
        self.config = self.directory / "config-xpui.ini"
        self.config.write_text("[Setting]\ncurrent_theme=custom\ncolor_scheme=old\n"
                               "inject_css=1\nreplace_colors=1\ninject_theme_js=1\n"
                               "spotify_path=/test/spotify\n[AdditionalOptions]\n"
                               "custom_apps=marketplace\nextensions=personal.js\n"
                               "[Backup]\nversion=original\n")
        self.scheme = json.loads((ROOT / "data/schemes/nord.json").read_text())
        self.calls = []

    def apply(self, running=False, status=0, config=None):
        def run(command, **kwargs):
            self.calls.append((command, kwargs))
            return status
        with patch("zesti.theme._spotify_running", return_value=running):
            results = apply_theme(self.scheme, self.paths, config or {}, run)
        return next(result for result in results if result["target"] == "spicetify")

    def test_copies_user_style_selects_palette_and_refreshes_running_spotify(self):
        original = self.config.read_text()
        self.assertTrue(self.apply(running=True)["ok"])
        target = self.directory / "Themes/zestify"
        self.assertEqual((target / "user.css").read_bytes(), (self.original / "user.css").read_bytes())
        self.assertEqual((target / "theme.js").read_bytes(), (self.original / "theme.js").read_bytes())
        self.assertEqual((target / "assets/icon.png").read_bytes(), b"image")
        self.assertEqual((self.original / "color.ini").read_text(), "[old]\nmain=123456\n")
        parser = configparser.ConfigParser()
        parser.read(self.config)
        self.assertEqual(parser["Setting"]["current_theme"], "zestify")
        self.assertEqual(parser["Setting"]["color_scheme"], "zestify")
        self.assertEqual(parser["AdditionalOptions"]["extensions"], "personal.js")
        self.assertEqual(parser["AdditionalOptions"]["custom_apps"], "marketplace")
        self.assertEqual(parser["Backup"]["version"], "original")
        self.assertEqual(self.config.with_name("config-xpui.ini.zestify.bak").read_text(), original)
        parser.read(target / "color.ini")
        self.assertEqual(parser["zestify"]["button"], self.scheme["colours"]["primary"])
        self.assertEqual(parser["zestify"]["text"], self.scheme["colours"]["onSurface"])
        command, kwargs = self.calls[-1]
        self.assertEqual(command, ["spicetify", "refresh"])
        self.assertEqual(kwargs["env"]["SPICETIFY_CONFIG"], str(self.directory))

    def test_closed_spotify_is_not_launched_and_existing_assets_are_preserved(self):
        self.assertTrue(self.apply()["ok"])
        css = self.directory / "Themes/zestify/user.css"
        css.write_text("/* user's later edits */")
        self.assertTrue(self.apply()["ok"])
        self.assertEqual(css.read_text(), "/* user's later edits */")
        self.assertEqual(self.calls[-1][0], ["spicetify", "-n", "refresh"])

    def test_hook_failure_is_reported_and_other_targets_still_apply(self):
        result = self.apply(status=1)
        self.assertFalse(result["ok"])
        self.assertIn("refresh failed", result["error"])
        self.assertTrue((self.paths.config_home / "kitty/zestify-colors.conf").is_file())

    def test_unconfigured_spicetify_is_disabled_by_default(self):
        self.config.unlink()
        target = next(t for t in theme_targets(self.paths, {}) if t.name == "spicetify")
        self.assertFalse(target.enabled)
        self.assertTrue(self.apply()["ok"])
        self.assertEqual(self.calls, [])

    def test_disabled_spicetify_preserves_config_and_does_not_refresh(self):
        previous = self.config.read_text()
        self.assertTrue(self.apply(config={"theme": {"apply": {"spicetify": {"enabled": False}}}})["ok"])
        self.assertEqual(self.config.read_text(), previous)
        self.assertEqual(self.calls, [])

    def test_malformed_config_is_isolated_as_target_error(self):
        self.config.write_text("invalid configuration")
        result = self.apply()
        self.assertFalse(result["ok"])
        self.assertIn("invalid Spicetify", result["error"])
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
