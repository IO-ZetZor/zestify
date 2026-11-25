"""Controls tests for zesti (volume, mic, brightness, config).

Injects a fake process runner so no real desktop tool is touched.
"""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.controls import volume, mic, brightness, config_command
from zesti.cli import main


class Result:
    def __init__(self, returncode, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def make_runner(queue):
    calls = []

    def run(cmd, **kwargs):
        calls.append(list(cmd))
        if not queue:
            return Result(1, "", "no scripted response")
        entry = queue.pop(0)
        rc, out = entry[0], entry[1]
        err = entry[2] if len(entry) > 2 else ""
        return Result(rc, out, err)

    return run, calls


class VolumeTest(unittest.TestCase):
    def test_cli_dispatch_uses_the_control_runner_contract(self):
        for argv, expected in [(["volume", "set", "75"], ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK", "75%"]),
                               (["mic", "mute"], ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE", "toggle"]),
                               (["brightness", "up"], ["brightnessctl", "s", "5%+"])]:
            with self.subTest(argv=argv), patch("zesti.controls._default_run", return_value=Result(3)) as run:
                self.assertEqual(main(argv), 3)
                run.assert_called_once_with(expected)

    def test_volume_up_down_mute_set(self):
        run, calls = make_runner([
            (0, ""), (0, ""), (0, ""), (0, ""),
        ])
        self.assertEqual(volume("up", run), 0)
        self.assertEqual(volume("down", run), 0)
        self.assertEqual(volume("mute", run), 0)
        self.assertEqual(volume("set", 75, run), 0)
        self.assertIn(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK", "toggle"], calls)
        self.assertIn(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK", "75%"], calls)

    def test_volume_invalid_exits_2(self):
        self.assertEqual(volume("frobnicate", 10, lambda *a, **k: Result(0, "")), 2)


class BrightnessTest(unittest.TestCase):
    def test_brightness_up_down_set(self):
        run, calls = make_runner([
            (0, ""), (0, ""), (0, ""),
        ])
        self.assertEqual(brightness("up", run), 0)
        self.assertEqual(brightness("down", run), 0)
        self.assertEqual(brightness("set", 60, run), 0)
        self.assertIn(["brightnessctl", "s", "5%+"], calls)
        self.assertIn(["brightnessctl", "s", "60%"], calls)

    def test_brightness_invalid_exits_2(self):
        self.assertEqual(brightness("frobnicate", 10, lambda *a, **k: Result(0, "")), 2)


class ConfigCommandTest(unittest.TestCase):
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
        }
        self.paths = Paths.from_env(self.env)

    def tearDown(self):
        self.temp.cleanup()

    def test_config_path_shows_path(self):
        rc, out = config_command("path", self.paths)
        self.assertEqual(rc, 0)
        self.assertIn("zestify/config.json", out)

    def test_config_show_prints_config(self):
        self.paths.config_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.config_file.write_text("{\"theme\": {\"mode\": \"dark\"}}")
        rc, out = config_command("show", self.paths)
        self.assertEqual(rc, 0)
        self.assertIn("dark", out)

    def test_config_validate_reports_ok(self):
        self.paths.config_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.config_file.write_text("{\"theme\": {\"mode\": \"dark\"}}")
        rc, out = config_command("validate", self.paths)
        self.assertEqual(rc, 0)
        self.assertIn("valid", out.lower())

    def test_config_edit_unknown_action_exits_2(self):
        rc, out = config_command("frobnicate", self.paths)
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
