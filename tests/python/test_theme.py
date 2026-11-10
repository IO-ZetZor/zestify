"""Application theme rendering tests for zesti.

All application configurations live in temporary XDG homes. Reload commands
are injected so the tests never signal the user's desktop applications.
"""

import configparser
import copy
import json
import tempfile
import threading
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path

from zesti.paths import Paths
from zesti.theme import (
    ThemeError,
    ThemeTarget,
    apply_theme,
    render_template,
    theme_targets,
)


def fake_paths(env_overrides=None):
    env = {
        "XDG_STATE_HOME": "/tmp/zt/state",
        "XDG_CACHE_HOME": "/tmp/zt/cache",
        "XDG_CONFIG_HOME": "/tmp/zt/config",
        "XDG_DATA_HOME": "/tmp/zt/data",
    }
    if env_overrides:
        env.update(env_overrides)
    return Paths.from_env(env)


SCHEME = {
    "mode": "dark",
    "variant": "tonal-spot",
    "colours": {
        "primary": "8bceff",
        "onPrimary": "1a1c1e",
        "secondary": "b7c9d9",
        "onSecondary": "21323e",
        "tertiary": "d1bce7",
        "onTertiary": "382b49",
        "surface": "1a1c1e",
        "surfaceVariant": "43474b",
        "onSurface": "e2e2e2",
        "onSurfaceVariant": "c3c7cb",
        "background": "1a1c1e",
        "onBackground": "e2e2e2",
        "outline": "8d9195",
        "error": "ff5449",
        "onError": "690005",
        **{f"term{i}": f"{i + 32:02x}{i + 64:02x}{i + 96:02x}" for i in range(16)},
    },
    "metadata": {"name": "test", "flavour": "tonalspot", "mode": "dark", "variant": "tonal-spot", "colours": 6},
}


DUAL_SCHEME = copy.deepcopy(SCHEME)
DUAL_SCHEME["palettes"] = {
    "dark": copy.deepcopy(SCHEME["colours"]),
    "light": dict(SCHEME["colours"], background="f8fafc", surface="f8fafc",
                  onBackground="18212a", onSurface="18212a", primary="27628b"),
}


def kitty_settings(path):
    """Read Kitty's whitespace-separated settings, independent of formatting."""
    return dict(line.split(None, 1) for line in path.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#"))


class RenderTemplateTest(unittest.TestCase):
    def test_exact_hex_without_hash(self):
        self.assertEqual(render_template("{primary}", SCHEME["colours"], "dark"), "8bceff")

    def test_hash_prefix(self):
        self.assertEqual(render_template("{primary}", SCHEME["colours"], "dark", hash_prefix=True), "#8bceff")

    def test_hash_prefix_idempotent(self):
        self.assertEqual(render_template("#{primary}", SCHEME["colours"], "dark", hash_prefix=True), "#8bceff")

    def test_explicit_hash_prefix_is_preserved_without_option(self):
        self.assertEqual(render_template("#{primary}", SCHEME["colours"], "dark"), "#8bceff")
        self.assertEqual(render_template("#{primary}", {"primary": "#8bceff"}, "dark"), "#8bceff")

    def test_literal_css_braces_and_color_placeholders(self):
        text = "window { color: #{primary}; }\nbutton:hover { border-color: #{error}; }\n"
        self.assertEqual(render_template(text, SCHEME["colours"], "dark"),
                         "window { color: #8bceff; }\nbutton:hover { border-color: #ff5449; }\n")

    def test_mode_substitution(self):
        self.assertEqual(render_template("mode={mode}", SCHEME["colours"], "light"), "mode=light")

    def test_multiple_placeholders(self):
        text = "bg={background} fg={onPrimary} err={error}"
        self.assertEqual(render_template(text, SCHEME["colours"], "dark"), "bg=1a1c1e fg=1a1c1e err=ff5449")

    def test_unknown_placeholder_fails(self):
        with self.assertRaises(ThemeError):
            render_template("{noSuchColour}", SCHEME["colours"], "dark")
        with self.assertRaises(ThemeError):
            render_template("window { color: #{noSuchColour}; }", SCHEME["colours"], "dark")


class ThemeTargetTest(unittest.TestCase):
    def test_theme_target_immutable(self):
        t = ThemeTarget(name="t", enabled=True, template="{primary}", output=Path("/tmp/x"))
        with self.assertRaises(FrozenInstanceError):
            t.name = "other"


class ApplyThemeTest(unittest.TestCase):
    def test_legacy_raw_palette_selects_requested_mode(self):
        scheme = {"mode": "dark", "colors": {
            "surface": {"dark": {"color": "#101010"}, "light": {"color": "#f0f0f0"}},
            "on_surface": {"dark": {"color": "#eeeeee"}, "light": {"color": "#111111"}},
            "primary": {"dark": {"color": "#abcdef"}, "light": {"color": "#123456"}},
        }}
        output = self.home / "legacy.conf"
        config = {"theme": {"mode": "light", "apply": {"legacy": {
            "template": "background=#{background}\nforeground=#{onBackground}\naccent=#{primary}\n",
            "output": str(output)
        }}}}
        results = apply_theme(scheme, self.paths, config, run=lambda *a, **k: 0)
        self.assertTrue(next(result for result in results if result["target"] == "legacy")["ok"])
        self.assertEqual(output.read_text(), "background=#f0f0f0\nforeground=#111111\naccent=#123456\n")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
        }
        self.paths = Paths.from_env(self.env)
        self.paths.state_home.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.temp.cleanup()

    def _config(self, targets):
        return {"theme": {"apply": targets}}

    def apply(self, config=None, scheme=SCHEME):
        results = apply_theme(scheme, self.paths, config or {}, run=lambda *a, **k: 0)
        self.assertTrue(results)
        self.assertEqual([r for r in results if not r["ok"]], [], results)
        return results

    def write_config(self, relative, contents):
        path = self.paths.config_home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def test_shipped_templates_render_to_application_locations(self):
        expected = {
            "colors": "kitty/zestify-colors.conf",
            "gtk": "zestify/theme/gtk.css",
            "qt": "qtengine/zestify.colors",
            "fuzzel": "fuzzel/fuzzel.ini",
            "cava": "cava/config",
        }
        targets = {target.name: target for target in theme_targets(self.paths, {})}
        self.apply()
        for name, relative in expected.items():
            with self.subTest(target=name):
                path = self.paths.config_home / relative
                self.assertEqual(targets[name].output, path)
                self.assertTrue(path.is_file(), relative)
                self.assertTrue(path.read_text().strip(), relative)
                self.assertNotIn("{primary}", path.read_text())
                self.assertFalse((self.paths.state_home / "zestify" / f"{name}.rendered").exists())
        settings = kitty_settings(self.paths.config_home / expected["colors"])
        self.assertEqual(settings["background"], "#1a1c1e")
        self.assertEqual(settings["foreground"], "#e2e2e2")
        for i in range(16):
            self.assertEqual(settings[f"color{i}"], "#" + SCHEME["colours"][f"term{i}"])
        gtk = (self.paths.config_home / expected["gtk"]).read_text()
        self.assertIn("@define-color", gtk)
        self.assertNotIn("[Theme]", gtk)

    def test_kitty_include_is_idempotent_preserves_fonts_and_first_backup(self):
        original = "# My terminal\nfont_family SF Mono\nfont_size 12\nbackground #000000\n"
        config = self.write_config("kitty/kitty.conf", original)
        colours = self.paths.config_home / "kitty/zestify-colors.conf"
        include = f"include {colours}"
        self.apply()
        backup = config.with_name(config.name + ".zestify.bak")
        self.assertEqual(backup.read_text(), original)
        self.assertIn(original.rstrip(), config.read_text())
        self.assertEqual(config.read_text().splitlines().count(include), 1)
        self.assertEqual(config.read_text().splitlines()[-1], include)
        edited = config.read_text().replace("font_size 12", "font_size 14")
        config.write_text(edited)
        self.apply({"theme": {"mode": "light"}}, DUAL_SCHEME)
        self.apply({"theme": {"mode": "dark"}}, DUAL_SCHEME)
        self.assertIn("font_size 14", config.read_text())
        self.assertEqual(config.read_text().splitlines().count(include), 1)
        self.assertEqual(backup.read_text(), original)

    def test_gtk_migration_preserves_custom_css_and_is_idempotent(self):
        original = "window { font-size: 11pt; }\n@define-color personal #123456;\n"
        configs = [self.write_config(f"gtk-{version}/gtk.css", original)
                   for version in ("3.0", "4.0")]
        include = '@import url("' + (self.paths.config_home / "zestify/theme/gtk.css").as_uri() + '");'
        self.apply()
        self.apply()
        for config in configs:
            with self.subTest(version=config.parent.name):
                self.assertIn(original.rstrip(), config.read_text())
                self.assertEqual(config.read_text().splitlines().count(include),
                                 0 if config.parent.name == "gtk-3.0" else 1)
                if config.read_text() != original:
                    self.assertEqual(config.with_name(config.name + ".zestify.bak").read_text(), original)

    def test_qtengine_selects_palette_preserving_font_style_and_other_settings(self):
        original = {
            "theme": {"font": {"family": "SF Pro", "size": 11}, "style": "Darkly",
                      "iconTheme": "YAMIS", "colorScheme": "/old/palette.colors"},
            "misc": {"singleClickActivate": False},
        }
        text = json.dumps(original)
        config = self.write_config("qtengine/config.json", text)
        self.apply()
        expected = copy.deepcopy(original)
        expected["theme"]["colorScheme"] = str(self.paths.config_home / "qtengine/zestify.colors")
        self.assertEqual(json.loads(config.read_text()), expected)
        self.assertEqual(config.with_name(config.name + ".zestify.bak").read_text(), text)
        self.apply()
        self.assertEqual(json.loads(config.read_text()), expected)
        self.assertEqual(config.with_name(config.name + ".zestify.bak").read_text(), text)

    def test_ini_color_sections_merge_without_losing_other_settings(self):
        cases = [
            ("fuzzel/fuzzel.ini", "colors",
             "# personal launcher\n[main]\nfont=SF Pro:size=12\n[colors]\nbackground=000000ff\n"
             "[border]\nwidth=2\n[colors]\ntext=000000ff\n", "main", "font", "SF Pro:size=12"),
            ("cava/config", "color",
             "# personal visualizer\n[general]\nframerate=30\n[color]\nforeground='#000000'\n"
             "[smoothing]\nnoise_reduction=40\n[color]\nbackground='#000000'\n", "general", "framerate", "30"),
        ]
        configs = [(self.write_config(relative, original), section, original, keep_section, key, value)
                   for relative, section, original, keep_section, key, value in cases]
        self.apply()
        self.apply()
        for config, section, original, keep_section, key, value in configs:
            with self.subTest(target=config.parent.name):
                parser = configparser.ConfigParser(interpolation=None)
                parser.read_string(config.read_text())
                self.assertEqual(parser[keep_section][key], value)
                self.assertEqual(config.read_text().count(f"[{section}]"), 1)
                self.assertTrue(parser[section]["text" if section == "colors" else "foreground"])
                self.assertIn(original.splitlines()[0], config.read_text())
                self.assertEqual(config.with_name(config.name + ".zestify.bak").read_text(), original)
                if section == "colors":
                    self.assertEqual(parser["border"]["width"], "2")
                    self.assertEqual(parser[section]["text"], "e2e2e2ff")
                else:
                    self.assertEqual(parser["smoothing"]["noise_reduction"], "40")
                    self.assertEqual(parser[section]["foreground"].strip("'\""), "#8bceff")

    def test_config_mode_selects_live_palette_instead_of_stored_colours(self):
        self.apply({"theme": {"mode": "light"}}, DUAL_SCHEME)
        colours = self.paths.config_home / "kitty/zestify-colors.conf"
        self.assertEqual(kitty_settings(colours)["background"], "#f8fafc")
        self.assertEqual(kitty_settings(colours)["foreground"], "#18212a")
        self.apply({"theme": {"mode": "dark"}}, DUAL_SCHEME)
        self.assertEqual(kitty_settings(colours)["background"], "#1a1c1e")
        self.assertEqual(kitty_settings(colours)["foreground"], "#e2e2e2")

    def test_disabled_builtin_target_suppresses_default_and_include(self):
        config = self._config({"colors": {"enabled": False}})
        targets = [target for target in theme_targets(self.paths, config) if target.name == "colors"]
        self.assertEqual(len(targets), 1)
        self.assertFalse(targets[0].enabled)
        self.apply(config)
        self.assertFalse((self.paths.config_home / "kitty/zestify-colors.conf").exists())
        self.assertFalse((self.paths.config_home / "kitty/kitty.conf").exists())

    def test_overridden_builtin_target_replaces_default_by_name(self):
        output = self.home / "custom-colours.txt"
        config = self._config({"colors": {"output": str(output), "template": "accent=#{primary}",
                                         "renderer": "template"}})
        targets = [target for target in theme_targets(self.paths, config) if target.name == "colors"]
        self.assertEqual(len(targets), 1)
        self.apply(config)
        self.assertEqual(output.read_text(), "accent=#8bceff")
        self.assertFalse((self.paths.config_home / "kitty/zestify-colors.conf").exists())

    def test_application_theming_can_be_disabled_globally(self):
        self.assertEqual(apply_theme(SCHEME, self.paths, {"theme": {"apply": False}},
                                     run=lambda *a, **k: 0), [])
        self.assertFalse(self.paths.config_home.exists())

    def test_applies_enabled_targets_and_skips_disabled(self):
        out_ok = self.home / "ok.sh"
        out_skip = self.home / "skip.sh"
        config = self._config({
            "ok": {"enabled": True, "template": "bg={background}", "output": str(out_ok)},
            "skip": {"enabled": False, "template": "bg={background}", "output": str(out_skip)},
        })
        results = apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
        by_name = {r["target"]: r for r in results}
        self.assertTrue(by_name["ok"]["ok"])
        self.assertEqual(out_ok.read_text().strip(), "bg=1a1c1e")
        self.assertTrue(by_name["skip"]["ok"])  # skipped counts as ok/no-op
        self.assertFalse(out_skip.exists())

    def test_failure_isolation(self):
        out_good = self.home / "good.sh"
        out_bad = self.home / "bad.sh"
        config = self._config({
            "good": {"enabled": True, "template": "bg={background}", "output": str(out_good)},
            "bad": {"enabled": True, "template": "nope={noSuchColour}", "output": str(out_bad)},
        })
        results = apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
        by_name = {r["target"]: r for r in results}
        self.assertTrue(by_name["good"]["ok"])
        self.assertEqual(out_good.read_text().strip(), "bg=1a1c1e")
        self.assertFalse(by_name["bad"]["ok"])
        self.assertIn("error", by_name["bad"])
        self.assertFalse(out_bad.exists())

    def test_output_writes_are_atomic_no_temp_left(self):
        out = self.home / "out.sh"
        config = self._config({
            "t": {"enabled": True, "template": "x={primary}", "output": str(out)},
        })
        apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
        self.assertTrue(out.exists())
        self.assertEqual(out.read_text().strip(), "x=8bceff")
        leftovers = [p for p in self.paths.state_home.rglob("*") if p.suffix in (".tmp", ".bak")]
        self.assertEqual(leftovers, [])

    def test_concurrent_calls_serialize_on_theme_lock(self):
        out1 = self.home / "a.sh"
        out2 = self.home / "b.sh"
        config = self._config({
            "t": {"enabled": True, "template": "x={primary}", "output": str(out1)},
        })
        barrier = threading.Barrier(2)
        errors = []

        def worker(path):
            try:
                barrier.wait()
                apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        t1 = threading.Thread(target=worker, args=(out1,))
        t2 = threading.Thread(target=worker, args=(out1,))
        t1.start(); t2.start(); t1.join(); t2.join()
        self.assertEqual(errors, [])
        self.assertTrue(out1.exists())


class ThemeTargetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.data = self.root / "data" / "templates"
        self.data.mkdir(parents=True)
        (self.data / "colors.sh").write_text("bg={background}\n")

    def tearDown(self):
        self.temp.cleanup()

    def test_theme_targets_discovers_data_templates(self):
        paths = fake_paths()
        config = {"theme": {"apply": {}}}
        targets = theme_targets(paths, config, data_dir=self.data)
        names = {t.name for t in targets}
        self.assertIn("colors", names)


if __name__ == "__main__":
    unittest.main()
