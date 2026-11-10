import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


class SettingsSurfaceTest(unittest.TestCase):
    def test_controls_apply_to_config_and_theme(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            config_dir = temporary / "config/zestify"
            config_dir.mkdir(parents=True)
            config_dir.joinpath("config.json").write_text(json.dumps({
                "theme": {"transparency": 0.5}, "bar": {"opacity": 0.8},
            }))
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ)
            env.pop("WAYLAND_DISPLAY", None)
            env.update({
                "HOME": directory,
                "XDG_CONFIG_HOME": str(temporary / "config"),
                "XDG_STATE_HOME": str(temporary / "state"),
                "XDG_CACHE_HOME": str(temporary / "cache"),
                "XDG_RUNTIME_DIR": str(runtime),
                "QT_QPA_PLATFORM": "offscreen",
            })
            temporary.joinpath("shell").symlink_to(REPO / "shell", target_is_directory=True)
            harness = temporary / "settings.qml"
            harness.write_text((REPO / "tests/quickshell/settings.qml").read_text().replace("../../shell/", "shell/"))
            result = subprocess.run(
                ["quickshell", "--no-color", "-p", str(harness)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("SETTINGS PASS:", output)
            self.assertNotIn("SETTINGS FAIL:", output)
            self.assertNotIn("TypeError", output)
            self.assertNotIn("ReferenceError", output)
