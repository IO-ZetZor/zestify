import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]


class PillSurfaceTest(unittest.TestCase):
    def test_launcher_cpu_warning_and_balanced_layout(self):
        with tempfile.TemporaryDirectory(prefix="zestify-pill-ui-") as directory:
            stage = Path(directory)
            shutil.copytree(REPO / "shell", stage / "shell")
            source = (REPO / "tests/quickshell/pill-ui.qml").read_text()
            (stage / "shell/shell.qml").write_text(source.replace("../../shell/", ""))
            runtime = stage / "runtime"
            runtime.mkdir(mode=0o700)
            preview = Path(os.environ.get("PILL_UI_PREVIEW", str(stage / "preview.png")))
            env = dict(os.environ,
                       XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(stage / "config"),
                       XDG_STATE_HOME=str(stage / "state"),
                       XDG_CACHE_HOME=str(stage / "cache"),
                       QT_QPA_PLATFORM="offscreen",
                       QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                       PILL_UI_PREVIEW=str(preview))
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(
                ["dbus-run-session", "qs", "--no-color", "-p", str(stage / "shell")],
                env=env, capture_output=True, text=True, timeout=20,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("PILL UI PASS:", output)
            for error in ["PILL UI FAIL:", "TypeError", "ReferenceError", "Binding loop"]:
                self.assertNotIn(error, output)
            self.assertTrue(preview.is_file(), output)


if __name__ == "__main__":
    unittest.main()
