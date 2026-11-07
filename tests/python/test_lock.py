import importlib.util
import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
LOCK = REPO / "scripts" / "lock.py"
CLI = REPO / "bin" / "zestify"


def load_lock_module():
    spec = importlib.util.spec_from_file_location("zestify_lock", LOCK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SCHEME = {
    "name": "test",
    "mode": "dark",
    "colours": {
        "background": "040304",
        "onBackground": "f1e1eb",
        "surface": "040304",
        "surfaceContainerHigh": "0c070c",
        "primary": "e3bade",
        "onPrimary": "543653",
        "error": "f97386",
    },
}


class LockTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.state = self.home / ".local" / "state" / "zestify"
        self.state.mkdir(parents=True)
        (self.state / "scheme.json").write_text(json.dumps(SCHEME), encoding="utf-8")
        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        self.env["XDG_STATE_HOME"] = str(self.home / ".local" / "state")
        self.env["XDG_CONFIG_HOME"] = str(self.home / ".config")
        self.out = self.root / "hyprlock.conf"

    def tearDown(self):
        self.temp.cleanup()

    def run_lock(self, *args):
        return subprocess.run(
            ["python3", str(LOCK), *args],
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_config_only_writes_hyprlock_blocks_and_palette(self):
        result = self.run_lock("--config-only", "--out", str(self.out))
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        text = self.out.read_text(encoding="utf-8")
        self.assertIn("background {", text)
        self.assertIn("input-field {", text)
        self.assertIn("label {", text)
        self.assertIn("rgb(f1e1eb)", text)
        self.assertIn("rgb(e3bade)", text)
        self.assertIn("rgb(0c070c)", text)
        self.assertIn("path =", text)

    def test_wait_defaults_false(self):
        module = load_lock_module()
        self.assertFalse(module.parse_args([]).wait)
        self.assertTrue(module.parse_args(["--wait"]).wait)

    def test_watcher_command_is_detached_pid_watch(self):
        module = load_lock_module()
        command = module.watcher_command(1234)
        self.assertIn("--watch-pid", command)
        self.assertIn("1234", command)

    def test_process_alive_rejects_zombie_children(self):
        module = load_lock_module()
        process = subprocess.Popen(["true"])
        self.addCleanup(process.wait)
        time.sleep(0.1)
        self.assertFalse(module.process_alive(process.pid))

    def test_cli_dispatches_lock(self):
        result = subprocess.run(
            [str(CLI), "lock", "--config-only", "--out", str(self.out)],
            env=self.env,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertTrue(self.out.exists())


if __name__ == "__main__":
    unittest.main()
