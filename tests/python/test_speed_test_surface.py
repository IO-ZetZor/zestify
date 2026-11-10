import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


class SpeedTestSurfaceTest(unittest.TestCase):
    def run_surface(self, failure=False):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            scripts = temporary / "scripts"
            scripts.mkdir()
            countfile = temporary / "runs"
            (scripts / "speed-test.py").write_text(
                "import json, time\nfrom pathlib import Path\n"
                f"countfile = Path({str(countfile)!r})\n"
                "count = int(countfile.read_text()) + 1 if countfile.exists() else 1\n"
                "countfile.write_text(str(count))\n"
                "for stage in ['latency', 'download', 'upload']:\n"
                "    print(json.dumps({'type': 'progress', 'stage': stage}), flush=True)\n"
                "    time.sleep(0.15)\n"
                "if count == 3:\n"
                "    print(json.dumps({'type': 'error', 'error': 'Server unavailable. Try again.'}), flush=True)\n"
                "else:\n"
                "    print(json.dumps({'type': 'result', 'download': 123.4, 'upload': 56.7, 'latency': 12.3}), flush=True)\n"
            )
            temporary.joinpath("shell").symlink_to(REPO / "shell", target_is_directory=True)
            harness = temporary / "speedtest.qml"
            harness.write_text((REPO / "tests/quickshell/speedtest.qml").read_text().replace("../../shell/", "shell/"))
            env = dict(os.environ)
            env.pop("WAYLAND_DISPLAY", None)
            preview = Path(env.get("SPEEDTEST_PREVIEW", str(temporary / "network.png")))
            env.update({
                "HOME": directory,
                "XDG_CONFIG_HOME": str(temporary / "config"),
                "XDG_STATE_HOME": str(temporary / "state"),
                "XDG_CACHE_HOME": str(temporary / "cache"),
                "XDG_RUNTIME_DIR": str(runtime),
                "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software",
                "ZESTIFY_SCRIPTS": str(scripts),
                "PYTHON": str(temporary / "missing-python") if failure else "python3",
                "SPEEDTEST_FAILURE": "1" if failure else "0",
                "SPEEDTEST_PREVIEW": str(preview),
            })
            result = subprocess.run(["quickshell", "--no-color", "-p", str(harness)],
                env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("SPEEDTEST PASS:", output)
            for error in ("SPEEDTEST FAIL:", "TypeError", "ReferenceError", "binding loop"):
                self.assertNotIn(error, output)
            if not failure:
                self.assertEqual(countfile.read_text(), "4", output)
                self.assertTrue(preview.is_file(), output)

    def test_speedtest_controls_results_cancellation_errors_and_retry(self):
        self.run_surface()

    def test_missing_helper_does_not_stay_busy(self):
        self.run_surface(failure=True)


if __name__ == "__main__":
    unittest.main()
