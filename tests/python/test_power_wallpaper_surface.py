import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


class PowerWallpaperSurfaceTest(unittest.TestCase):
    def test_integrated_panels_render_at_supported_sizes(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            temporary.joinpath("shell").symlink_to(REPO / "shell", target_is_directory=True)
            harness = temporary / "power-wallpaper.qml"
            harness.write_text((REPO / "tests/quickshell/power-wallpaper.qml").read_text().replace("../../shell/", "shell/"))
            env = dict(os.environ)
            env.pop("WAYLAND_DISPLAY", None)
            previews = Path(env.get("POWER_WALLPAPER_PREVIEW", str(temporary / "previews")))
            previews.mkdir(exist_ok=True)
            env.update({
                "HOME": directory,
                "XDG_CONFIG_HOME": str(temporary / "config"),
                "XDG_STATE_HOME": str(temporary / "state"),
                "XDG_CACHE_HOME": str(temporary / "cache"),
                "XDG_RUNTIME_DIR": str(runtime),
                "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software",
                "POWER_WALLPAPER_PREVIEW": str(previews),
            })
            result = subprocess.run(
                ["quickshell", "--no-color", "-p", str(harness)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("POWER WALLPAPER PASS:", output)
            for error in ("POWER WALLPAPER FAIL:", "TypeError", "ReferenceError", "binding loop"):
                self.assertNotIn(error, output)
            for phase in range(5):
                for panel in ("power", "wallpaper"):
                    self.assertTrue((previews / f"{panel}-{phase}.png").is_file(), output)
