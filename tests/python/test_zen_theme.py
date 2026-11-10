"""Zen profile integration preserves user rules and follows native GTK roles."""

import tempfile
import unittest
from pathlib import Path

from zesti import zen
from zesti.paths import Paths
from zesti.theme import apply_theme, theme_targets
from tests.python.test_theme import SCHEME


class ZenThemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.paths = Paths.from_env({"XDG_CONFIG_HOME": str(self.home / ".config"),
                                     "XDG_DATA_HOME": str(self.home / ".local/share"),
                                     "XDG_STATE_HOME": str(self.home / ".local/state")})
        self.root = self.paths.config_home / "zen"
        self.profile = self.root / "personal"
        self.profile.mkdir(parents=True)
        self.ini = self.root / "profiles.ini"
        self.ini.write_text("[Profile0]\nPath=personal\nIsRelative=1\n")

    def apply(self, config=None):
        results = apply_theme(SCHEME, self.paths, config or {}, run=lambda *a, **k: 0)
        return next(result for result in results if result["target"] == "zen")

    def test_profiles_with_spaces_absolute_paths_and_legacy_root(self):
        extra = self.home / "another profile"
        extra.mkdir()
        with self.ini.open("a") as handle:
            handle.write(f"[Profile1]\nPath={extra}\nIsRelative=0\n")
        legacy = self.home / ".zen"
        legacy.mkdir()
        (legacy / "profiles.ini").write_text(f"[Profile0]\nPath={extra}\nIsRelative=0\n")
        self.assertEqual(zen.profiles(self.paths), [self.profile, extra])

    def test_import_and_prefs_are_idempotent_and_preserve_user_settings(self):
        css = self.profile / "chrome/userChrome.css"
        css.parent.mkdir()
        original_css = "/* personal rules */\n:root { font-size: 12px; }\n"
        css.write_text(original_css)
        prefs = self.profile / "user.js"
        original_prefs = 'user_pref("browser.tabs.warnOnClose", true);\n'
        prefs.write_text(original_prefs)
        result = self.apply()
        self.assertTrue(result["ok"])
        self.assertTrue(result["restart_required"])
        first_css, first_prefs = css.read_text(), prefs.read_text()
        result = self.apply()
        self.assertTrue(result["ok"])
        self.assertFalse(result["restart_required"])
        self.assertEqual(css.read_text(), first_css)
        self.assertEqual(prefs.read_text(), first_prefs)
        self.assertIn(original_css, first_css)
        self.assertIn(original_prefs.strip(), first_prefs)
        self.assertEqual(prefs.with_name("user.js.zestify.bak").read_text(), original_prefs)
        self.assertEqual(css.with_name("userChrome.css.zestify.bak").read_text(), original_css)
        self.assertTrue(first_css.startswith('@import url("file:'))
        self.assertEqual(first_prefs.count("// >>> zestify-theme >>>"), 1)
        self.assertIn('user_pref("zen.view.window.scheme", 2)', first_prefs)
        rendered = (self.paths.config_home / "zestify/theme/zen.css").read_text()
        self.assertIn("SelectedItem", rendered)

    def test_mod_styles_and_transparency_preferences_are_preserved(self):
        registry = self.profile / "zen-themes.json"
        mods = self.profile / "chrome/zen-themes.css"
        mods.parent.mkdir()
        registry.write_text('{"transparent": {"name": "Transparent Zen", "enabled": true}}')
        mods.write_text('#zen-toolbar-background { background: transparent !important; }\n')
        prefs = self.profile / "user.js"
        prefs.write_text('user_pref("zen.widget.linux.transparency", true);\n'
                         'user_pref("mod.sameerasw.zen_transparent_sidebar_enabled", true);\n')
        originals = {path: path.read_bytes() for path in (registry, mods, prefs)}
        self.assertTrue(self.apply()["ok"])
        self.assertEqual(registry.read_bytes(), originals[registry])
        self.assertEqual(mods.read_bytes(), originals[mods])
        self.assertIn(originals[prefs].decode().strip(), prefs.read_text())

    def test_stylesheet_changes_require_restart_but_palette_mode_changes_do_not(self):
        self.assertTrue(self.apply()["restart_required"])
        self.assertFalse(self.apply({"theme": {"mode": "light"}})["restart_required"])
        result = self.apply({"theme": {"apply": {"zen": {"template": ":root { color: FieldText; }"}}}})
        self.assertTrue(result["ok"])
        self.assertTrue(result["restart_required"])

    def test_unconfigured_or_disabled_browser_creates_no_profile_files(self):
        self.ini.unlink()
        self.assertFalse(next(t for t in theme_targets(self.paths, {}) if t.name == "zen").enabled)
        self.assertTrue(self.apply()["ok"])
        self.assertFalse((self.profile / "user.js").exists())
        self.ini.write_text("[Profile0]\nPath=personal\n")
        self.assertTrue(self.apply({"theme": {"apply": {"zen": {"enabled": False}}}})["ok"])
        self.assertFalse((self.profile / "user.js").exists())

    def test_malformed_profile_config_is_isolated_to_browser_target(self):
        self.ini.write_text("not an ini file")
        self.assertFalse(self.apply()["ok"])
        self.assertTrue((self.paths.config_home / "kitty/zestify-colors.conf").exists())

    def test_disabled_or_failed_gtk_target_reports_browser_dependency(self):
        for spec in ({"enabled": False}, {"template": "#{missingColour}"}):
            with self.subTest(gtk=spec):
                result = self.apply({"theme": {"apply": {"gtk": spec}}})
                self.assertFalse(result["ok"])
                self.assertIn("requires the GTK", result["error"])

    def test_incomplete_owned_pref_block_is_reported_without_overwriting_user_js(self):
        prefs = self.profile / "user.js"
        original = "// >>> zestify-theme >>>\n// personal data\n"
        prefs.write_text(original)
        result = self.apply()
        self.assertFalse(result["ok"])
        self.assertIn("incomplete", result["error"])
        self.assertEqual(prefs.read_text(), original)
