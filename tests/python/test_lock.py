import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti import cli
from zesti.paths import Paths
from zesti.wallpaper import extract_palette_source

REPO = Path(__file__).resolve().parents[2]
LOCK = REPO / "scripts/lock.py"


def load_lock_module():
    spec = importlib.util.spec_from_file_location("zestify_lock", LOCK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def state(active=True, secure=False, generation=1, error=""):
    return {"active": active, "secure": secure, "generation": generation, "error": error}


class LockTest(unittest.TestCase):
    def setUp(self):
        self.module = load_lock_module()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_returns_only_after_compositor_confirmation(self):
        with patch.object(self.module, "ipc_call", return_value="1"), \
             patch.object(self.module, "lock_status", side_effect=[state(), state(secure=True)]) as status, \
             patch.object(self.module.time, "sleep"), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.module.request_lock(), 0)
        self.assertEqual(status.call_count, 2)

    def test_wait_stays_until_unlock(self):
        with patch.object(self.module, "ipc_call", return_value="1"), \
             patch.object(self.module, "lock_status", side_effect=[state(secure=True), state(secure=True), state(active=False)]) as status, \
             patch.object(self.module.time, "sleep"), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.module.request_lock(wait=True), 0)
        self.assertEqual(status.call_count, 3)

    def test_rejection_timeout_changed_generation_and_crash_fail(self):
        for response in [state(active=False, error="Rejected"), state(generation=2), state()]:
            with self.subTest(response=response), patch.object(self.module, "ipc_call", return_value="1"), \
                 patch.object(self.module, "lock_status", return_value=response):
                with self.assertRaises(RuntimeError):
                    self.module.request_lock(timeout=0)
        with patch.object(self.module, "ipc_call", side_effect=RuntimeError("Shell unavailable")), \
             contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.module.main([]), 1)

    def test_cli_requests_native_locker_and_forwards_wait(self):
        fake = self.root / "qs"
        calls = self.root / "calls"
        fake.write_text("#!/usr/bin/env python3\nimport json, os, sys\n"
                        "with open(os.environ['LOCK_TEST_CALLS'], 'a') as f: f.write(sys.argv[-1] + '\\n')\n"
                        "if sys.argv[-1] == 'lock': print(1)\n"
                        "else:\n"
                        " n = len(open(os.environ['LOCK_TEST_CALLS']).readlines())\n"
                        " print(json.dumps({'generation': 1, 'active': n < 3, 'secure': n < 3, 'error': ''}))\n")
        fake.chmod(0o755)
        env = {**os.environ, "QS_BIN": str(fake), "LOCK_TEST_CALLS": str(calls)}
        result = subprocess.run([str(REPO / "bin/zesti"), "lock", "--wait"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.read_text().splitlines(), ["lock", "lockStatus", "lockStatus"])
        self.assertTrue(json.loads(result.stdout)["ok"])

    def test_ipc_failure_and_invalid_status_are_errors(self):
        with patch.object(self.module.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "No instance")):
            with self.assertRaisesRegex(RuntimeError, "No instance"):
                self.module.ipc_call("lock")
        with patch.object(self.module, "ipc_call", return_value='{"secure": true}'):
            with self.assertRaises(RuntimeError): self.module.lock_status()

    def test_sleep_waits_for_secure_lock_and_never_suspends_on_failure(self):
        events = []
        def request(name, args):
            events.append((name, args))
            return 0
        def suspend(args, **kwargs):
            events.append(args)
            return subprocess.CompletedProcess(args, 0)
        with patch.object(cli, "_run_repo_script", side_effect=request), patch.object(cli.subprocess, "run", side_effect=suspend):
            self.assertEqual(cli._sleep(None), 0)
        self.assertEqual(events, [("lock", []), ["systemctl", "suspend-then-hibernate"]])
        with patch.object(cli, "_run_repo_script", return_value=1), patch.object(cli.subprocess, "run") as run:
            self.assertEqual(cli._sleep(None), 1)
            run.assert_not_called()

    def test_frame_paths_are_url_encoded_and_missing_wallpaper_is_safe(self):
        image = self.root / "wall paper #1.png"
        image.write_bytes(b"image")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(self.module.main(["--frame", str(image)]), 0)
        self.assertEqual(json.loads(output.getvalue())["url"], image.as_uri())
        self.assertEqual(self.module.lock_frame(str(self.root / "missing")), "")

    def test_video_timeout_does_not_block_locker(self):
        video = self.root / "wallpaper.mp4"
        video.write_bytes(b"video")
        with patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.root / "cache")}), \
             patch.object(self.module.shutil, "which", return_value="ffmpeg"), \
             patch.object(self.module.subprocess, "run", side_effect=subprocess.TimeoutExpired("ffmpeg", 30)):
            self.assertEqual(self.module.lock_frame(str(video)), "")

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is required")
    def test_short_video_produces_real_lock_and_palette_frames(self):
        video = self.root / "short.mp4"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        "color=c=blue:s=64x64:r=10", "-t", "0.2", str(video)], check=True)
        with patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.root / "cache")}):
            frame = Path(self.module.lock_frame(str(video)))
        self.assertTrue(frame.is_file())
        self.assertTrue(frame.read_bytes().startswith(b"\xff\xd8"))
        paths = Paths.from_env({"HOME": str(self.root)})
        def run(cmd, **kwargs):
            return subprocess.run(cmd, capture_output=True, **kwargs).returncode
        frame = extract_palette_source(video, paths, run)
        self.assertTrue(frame.read_bytes().startswith(b"\xff\xd8"))


if __name__ == "__main__":
    unittest.main()
