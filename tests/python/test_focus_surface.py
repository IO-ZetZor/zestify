import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]


class FocusSurfaceTest(unittest.TestCase):
    def test_focus_card_session_and_notifications(self):
        with tempfile.TemporaryDirectory(prefix="zestify-focus-") as directory:
            temporary = Path(directory)
            config_dir = temporary / "config/zestify"
            config_dir.mkdir(parents=True)
            config_dir.joinpath("config.json").write_text(json.dumps({
                "theme": {"apply": False}, "focus": {"dnd": False},
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
            harness = temporary / "focus.qml"
            harness.write_text((REPO / "tests/quickshell/focus.qml").read_text().replace("../../shell/", "shell/"))
            result = subprocess.run(
                ["dbus-run-session", "qs", "--no-color", "-p", str(harness)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("FOCUS PASS:", output)
            for error in ["FOCUS FAIL:", "TypeError", "ReferenceError", "Binding loop"]:
                self.assertNotIn(error, output)


if __name__ == "__main__":
    unittest.main()
