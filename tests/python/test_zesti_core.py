"""Core Zesti package: paths, config, parser, version."""

import json
import os
import tempfile
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path

from zesti.paths import Paths
from zesti.config import load_config, validate_config
from zesti.cli import build_parser, main


class PathsTest(unittest.TestCase):
    def test_home_fallback_uses_the_supplied_environment(self):
        p = Paths.from_env({"HOME": "/tmp/isolated-user", "XDG_CONFIG_HOME": ""})
        self.assertEqual(p.config_home, Path("/tmp/isolated-user/.config"))
        self.assertEqual(p.data_home, Path("/tmp/isolated-user/.local/share"))
        self.assertEqual(p.state_home, Path("/tmp/isolated-user/.local/state"))
        self.assertEqual(p.cache_home, Path("/tmp/isolated-user/.cache"))

    def test_xdg_overrides_produce_zestify_paths(self):
        env = {
            "XDG_CONFIG_HOME": "/tmp/xc/config",
            "XDG_DATA_HOME": "/tmp/xd/data",
            "XDG_STATE_HOME": "/tmp/xs/state",
            "XDG_CACHE_HOME": "/tmp/xc/cache",
        }
        p = Paths.from_env(env)
        self.assertEqual(str(p.config_home), "/tmp/xc/config")
        self.assertEqual(str(p.state_home), "/tmp/xs/state")
        self.assertEqual(str(p.cache_home), "/tmp/xc/cache")
        self.assertEqual(str(p.config_file), "/tmp/xc/config/zestify/config.json")
        self.assertEqual(str(p.scheme_file), "/tmp/xs/state/zestify/scheme.json")
        self.assertEqual(
            str(p.wallpaper_dir), "/tmp/xs/state/zestify/wallpaper"
        )
        self.assertEqual(
            str(p.monitor_dir),
            "/tmp/xs/state/zestify/wallpaper/monitors",
        )
        self.assertEqual(str(p.migration_file), "/tmp/xs/state/zestify/migration.json")

    def test_paths_are_immutable(self):
        env = {"XDG_CONFIG_HOME": "/tmp/xc/config"}
        p = Paths.from_env(env)
        with self.assertRaises((AttributeError, FrozenInstanceError)):
            p.config_home = Path("/tmp/elsewhere")


class AtomicWriteTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_atomic_write_replaces_complete_file(self):
        from zesti.paths import atomic_write
        target = self.root / "a" / "file.json"
        atomic_write(target, '{"ok": true}')
        self.assertTrue(target.exists())
        self.assertEqual(target.read_text(), '{"ok": true}')

    def test_atomic_json_writes_valid_json(self):
        from zesti.paths import atomic_json
        target = self.root / "state.json"
        atomic_json(target, {"a": 1, "b": [1, 2]})
        data = json.loads(target.read_text())
        self.assertEqual(data, {"a": 1, "b": [1, 2]})


class ConfigTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.defaults_path = self.root / "config" / "default.json"
        self.defaults_path.parent.mkdir(parents=True)
        self.defaults_path.write_text(
            json.dumps({"theme": {"mode": "dark"}, "osd": {"enabled": True}})
        )
        self.user_path = self.root / "user.json"
        self.user_path.write_text(
            json.dumps({"theme": {"transparency": 0.5}})
        )

    def tearDown(self):
        self.temp.cleanup()

    def test_load_config_partial_user_deep_merges(self):
        result = load_config(self.defaults_path, self.user_path)
        self.assertEqual(result["theme"]["mode"], "dark")
        self.assertEqual(result["theme"]["transparency"], 0.5)

    def test_load_config_does_not_mutate_defaults(self):
        raw = self.defaults_path.read_text()
        load_config(self.defaults_path, self.user_path)
        self.assertEqual(self.defaults_path.read_text(), raw)

    def test_invalid_top_level_json_reported(self):
        self.user_path.write_text("{not json")
        with self.assertRaises(ValueError):
            load_config(self.defaults_path, self.user_path)


class ParserTest(unittest.TestCase):
    def test_help_lists_every_command_family(self):
        parser = build_parser(prog="zesti")
        help_text = parser.format_help()
        for family in [
            "shell",
            "wallpaper",
            "theme",
            "scheme",
            "capture",
            "clipboard",
            "emoji",
            "workspace",
            "window",
            "lock",
            "sleep",
            "volume",
            "mic",
            "brightness",
            "config",
            "cache",
            "doctor",
            "install",
            "update",
            "version",
        ]:
            self.assertIn(family, help_text)

    def test_version_prints_stable_string(self):
        parser = build_parser(prog="zesti")
        with self.assertRaises(SystemExit) as raised:
            parser.parse_args(["--version"])
        self.assertEqual(raised.exception.code, 0)


class MainTest(unittest.TestCase):
    def test_main_help_returns_zero(self):
        self.assertEqual(main(["--help"]), 0)

    def test_main_version_returns_zero(self):
        self.assertEqual(main(["version"]), 0)


if __name__ == "__main__":
    unittest.main()
