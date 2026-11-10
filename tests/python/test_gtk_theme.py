"""GTK palette notifications and cava reloads are scoped to their consumers."""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.theme import _reload_cava, apply_theme
from tests.python.test_theme import SCHEME, DUAL_SCHEME


class GtkThemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.paths = Paths.from_env({"XDG_CONFIG_HOME": str(self.root / "config"),
                                     "XDG_DATA_HOME": str(self.root / "data"),
                                     "XDG_STATE_HOME": str(self.root / "state")})
        self.calls = []
        for name in ("personal", "personal-dark"):
            for version in ("3.0", "4.0"):
                directory = self.paths.data_home / f"themes/{name}/gtk-{version}"
                directory.mkdir(parents=True)
                (directory / "gtk.css").write_text("/* base theme */\n")
        self.settings = self.paths.config_home / "gtk-3.0/settings.ini"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text("# keep me\n[Settings]\ngtk-theme-name=personal-dark\n"
                                 "gtk-font-name=Personal Font 12\ngtk-application-prefer-dark-theme=1\n"
                                 "[Other]\nsetting=preserved\n")

    def apply(self, mode="light"):
        def run(command, **kwargs):
            self.calls.append(command)
            return 0
        results = apply_theme(DUAL_SCHEME, self.paths, {"theme": {"mode": mode}}, run)
        self.assertEqual([r for r in results if not r["ok"]], [], results)
        return json.loads((self.paths.config_home / "zestify/theme/gtk-state.json").read_text())

    def test_mode_palette_slots_and_preserved_base_settings(self):
        first = self.apply()
        self.assertEqual(first["base"], "personal-dark")
        self.assertIn("gtk-application-prefer-dark-theme=0", self.settings.read_text())
        self.assertIn("gtk-font-name=Personal Font 12", self.settings.read_text())
        self.assertIn("# keep me", self.settings.read_text())
        self.assertIn("[Other]\nsetting=preserved", self.settings.read_text())
        self.assertEqual(self.apply(), first)
        second = self.apply("dark")
        self.assertNotEqual(first["slot"], second["slot"])
        self.assertIn("gtk-application-prefer-dark-theme=1", self.settings.read_text())
        for state, mode in ((first, "light"), (second, "dark")):
            css = self.paths.data_home / f"themes/Zestify-{mode}-{state['slot']}/gtk-3.0/gtk.css"
            self.assertIn((self.paths.data_home / f"themes/personal{'-dark' if mode == 'dark' else ''}/gtk-3.0/gtk.css").as_uri(), css.read_text())
            self.assertIn("#f8fafc" if mode == "light" else "#1a1c1e", css.read_text())

    def test_migration_removes_stale_owned_colors_preserving_rules_and_custom_colors(self):
        css = self.settings.parent / "gtk.css"
        palette = self.paths.config_home / "zestify/theme/gtk.css"
        css.write_text('@define-color primary #112233;\n@define-color personal #abcdef;\n'
                       'window { font-size: 12px; }\n@import url("' + palette.as_uri() + '");\n')
        self.apply()
        self.assertNotIn("#112233", css.read_text())
        self.assertNotIn(palette.as_uri(), css.read_text())
        self.assertIn("@define-color personal #abcdef", css.read_text())
        self.assertIn("font-size: 12px", css.read_text())

    def test_publishes_only_to_matching_session(self):
        self.apply()
        self.assertEqual(self.calls, [])
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.paths.config_home),
                                    "ZESTI_DESKTOP_CONFIG_HOME": str(self.paths.config_home),
                                    "DBUS_SESSION_BUS_ADDRESS": "test-session"}):
            self.apply()
        self.assertEqual(self.calls, [["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "Zestify-light-a"],
                                     ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-light"]])

    def test_temporary_cli_environment_does_not_publish_to_inherited_desktop_bus(self):
        with patch.dict(os.environ, {"HOME": str(self.root), "XDG_CONFIG_HOME": str(self.paths.config_home),
                                    "DBUS_SESSION_BUS_ADDRESS": "inherited-real-session"}):
            os.environ.pop("ZESTI_DESKTOP_CONFIG_HOME", None)
            self.apply()
        self.assertEqual(self.calls, [])


class CavaReloadTest(unittest.TestCase):
    def test_signals_only_matching_configs_and_session(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = Paths.from_env({"XDG_CONFIG_HOME": str(root / "config")})
            output = paths.config_home / "cava/config"
            proc_root = root / "proc"
            for pid, args, config in (("101", ["cava"], paths.config_home),
                                      ("102", ["cava", "-p", str(output)], paths.config_home),
                                      ("103", ["cava", "-p", str(paths.config_home / "zestify/cava.conf")], paths.config_home),
                                      ("104", ["cava"], root / "other")):
                proc = proc_root / pid
                proc.mkdir(parents=True)
                (proc / "comm").write_text("cava\n")
                (proc / "environ").write_bytes(b"HOME=/tmp\0XDG_CONFIG_HOME=" + os.fsencode(config) + b"\0")
                (proc / "cmdline").write_bytes(b"\0".join(os.fsencode(arg) for arg in args) + b"\0")
            calls = []
            _reload_cava(output, paths, lambda command: calls.append(command) or 0, proc_root)
            self.assertEqual(sorted(calls), [["kill", "-USR2", "101"], ["kill", "-USR2", "102"]])
