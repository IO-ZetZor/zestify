import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


class GpuStatsTest(unittest.TestCase):
    def run_stats(self, failure=False):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            scripts = temporary / "scripts"
            scripts.mkdir()
            devices = [
                {"id": "intel", "utilization": 20},
                {"id": "amd", "utilization": 40},
            ]
            (scripts / "gpu-monitor.py").write_text(
                "import sys\nfor request in sys.stdin:\n"
                f"    print({json.dumps(json.dumps(devices))}, flush=True)\n"
            )
            temporary.joinpath("shell").symlink_to(REPO / "shell", target_is_directory=True)
            harness = temporary / "gpu.qml"
            harness.write_text((REPO / "tests/quickshell/gpu.qml").read_text().replace("../../shell/", "shell/"))
            env = dict(os.environ)
            env.pop("WAYLAND_DISPLAY", None)
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
                "GPU_FAILURE_TEST": "1" if failure else "0",
            })
            result = subprocess.run(["quickshell", "--no-color", "-p", str(harness)],
                env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("GPU PASS:", output)
            for error in ("GPU FAIL:", "TypeError", "ReferenceError", "binding loop"):
                self.assertNotIn(error, output)

    def test_gpu_collector_polling_histories_stop_restart(self):
        self.run_stats()

    def test_gpu_collector_failed_start_is_unavailable(self):
        self.run_stats(failure=True)

    def test_real_monitor_stdin_protocol(self):
        result = subprocess.run(["python3", str(REPO / "scripts/gpu-monitor.py")],
            input="sample\nsample\n", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        samples = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(samples), 2)
        for devices in samples:
            self.assertIsInstance(devices, list)
            self.assertEqual(len({device["id"] for device in devices}), len(devices))
            for device in devices:
                self.assertIn(device["status"], ("active", "suspended"))


if __name__ == "__main__":
    unittest.main()
