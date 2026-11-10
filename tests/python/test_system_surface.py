import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


class SystemSurfaceTest(unittest.TestCase):
    def test_usage_dashboard_loads_and_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            temporary.joinpath("shell").symlink_to(REPO / "shell", target_is_directory=True)
            harness = temporary / "system.qml"
            harness.write_text((REPO / "tests/quickshell/system.qml").read_text().replace("../../shell/", "shell/"))
            env = dict(os.environ)
            env.pop("WAYLAND_DISPLAY", None)
            preview = Path(env.get("SYSTEM_PREVIEW", str(temporary / "system.png")))
            env.update({
                "HOME": directory,
                "XDG_CONFIG_HOME": str(temporary / "config"),
                "XDG_STATE_HOME": str(temporary / "state"),
                "XDG_CACHE_HOME": str(temporary / "cache"),
                "XDG_RUNTIME_DIR": str(runtime),
                "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software",
                "SYSTEM_PREVIEW": str(preview),
            })
            result = subprocess.run(
                ["quickshell", "--no-color", "-p", str(harness)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("SYSTEM PASS:", output)
            for error in ("SYSTEM FAIL:", "TypeError", "ReferenceError", "binding loop"):
                self.assertNotIn(error, output)
            self.assertTrue(preview.is_file(), output)
