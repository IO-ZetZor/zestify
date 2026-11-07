"""Screenshot and recording capture tests for zesti.

Injects fake process runners, notifier and clipboard so no real desktop tool or
the live desktop is touched.
"""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.capture import (
    CaptureError,
    CaptureResult,
    RecordOptions,
    CaptureServices,
    ScreenshotOptions,
    record_pause,
    record_start,
    record_stop,
    record_toggle,
    take_screenshot,
)


def fake_paths(env_overrides=None):
    env = {
        "XDG_STATE_HOME": "/tmp/zt/state",
        "XDG_CACHE_HOME": "/tmp/zt/cache",
        "XDG_CONFIG_HOME": "/tmp/zt/config",
    }
    if env_overrides:
        env.update(env_overrides)
    return Paths.from_env(env)


class Services:
    def __init__(self):
        self.calls = []
        self.notify_calls = []
        self.clipboard_calls = []

    def run(self, cmd, **kwargs):
        self.calls.append(list(cmd))
        return 0

    def start_detached(self, cmd, **kwargs):
        self.calls.append(list(cmd))
        return 0

    def notify(self, *a, **k):
        self.notify_calls.append((a, k))

    def clipboard(self, data):
        self.clipboard_calls.append(data)
        return 0


class ScreenshotTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.paths = fake_paths()

    def tearDown(self):
        self.temp.cleanup()

    def test_focused_monitor_capture_uses_grim_and_wl_copy(self):
        svc = Services()
        result = take_screenshot(
            ScreenshotOptions(), self.paths,
            CaptureServices(run=svc.run, notify=svc.notify, clipboard=svc.clipboard),
        )
        self.assertTrue(result.ok, result.error)
        self.assertTrue(any(c[0] == "grim" for c in svc.calls))
        self.assertTrue(any(c[0] == "wl-copy" for c in svc.calls))

    def test_region_passes_geometry_to_grim(self):
        svc = Services()
        take_screenshot(
            ScreenshotOptions(region="1920x1080+0+0"), self.paths,
            CaptureServices(run=svc.run),
        )
        self.assertTrue(any("1920x1080+0+0" in str(c) for c in svc.calls))

    def test_freeze_runs_grimblast_before_copy(self):
        svc = Services()
        take_screenshot(
            ScreenshotOptions(freeze=True), self.paths,
            CaptureServices(run=svc.run),
        )
        grimblast = [c for c in svc.calls if c[0] == "grimblast"]
        self.assertTrue(grimblast, "expected a grimblast call")
        self.assertEqual(grimblast[0][1:4], ["--freeze", "save", "area"])

    def test_caches_under_zestify(self):
        svc = Services()
        result = take_screenshot(
            ScreenshotOptions(), self.paths,
            CaptureServices(run=svc.run),
        )
        self.assertTrue(result.ok)
        self.assertTrue(str(result.path).startswith(str(self.paths.cache_home)))

    def test_cancellation_is_success_no_traceback(self):
        svc = Services()

        def run(cmd, **kwargs):
            if cmd[0] == "slurp":
                return 1  # user cancelled
            return 0

        result = take_screenshot(
            ScreenshotOptions(region="auto"), self.paths,
            CaptureServices(run=run),
        )
        self.assertTrue(result.ok)
        self.assertTrue(result.cancelled)

    def test_missing_grim_names_dependency(self):
        svc = Services()

        def run(cmd, **kwargs):
            if cmd[0] == "grim":
                raise FileNotFoundError("grim")
            return 0

        result = take_screenshot(
            ScreenshotOptions(), self.paths,
            CaptureServices(run=run),
        )
        self.assertFalse(result.ok)
        self.assertIn("grim", str(result.error))


class RecordingTest(unittest.TestCase):
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

    def test_record_start_writes_state_under_zestify(self):
        svc = Services()
        result = record_start(
            RecordOptions(), self.paths,
            CaptureServices(start_detached=svc.start_detached),
        )
        self.assertTrue(result.ok, result.error)
        self.assertTrue(str(result.path).startswith(str(self.paths.state_home)))

    def test_record_pause_sends_usr2(self):
        svc = Services()
        record_start(RecordOptions(), self.paths, CaptureServices(start_detached=svc.start_detached))
        svc.calls.clear()
        record_pause(self.paths, CaptureServices(run=svc.run, start_detached=svc.start_detached))
        self.assertTrue(any("-USR2" in str(c) or "USR2" in str(c) for c in svc.calls))

    def test_record_stop_moves_file_and_copies_uri(self):
        svc = Services()
        record_start(RecordOptions(), self.paths, CaptureServices(start_detached=svc.start_detached))
        svc.calls.clear()
        svc.clipboard_calls.clear()
        result = record_stop(True, self.paths, CaptureServices(
            start_detached=svc.start_detached, clipboard=svc.clipboard))
        self.assertTrue(result.ok, result.error)
        self.assertTrue(any("file://" in str(c) for c in svc.clipboard_calls))

    def test_missing_recorder_names_dependency(self):
        def start_detached(cmd, **kwargs):
            if cmd[0] == "gpu-screen-recorder":
                raise FileNotFoundError("gpu-screen-recorder")
            return 0

        result = record_start(
            RecordOptions(), self.paths, CaptureServices(start_detached=start_detached))
        self.assertFalse(result.ok)
        self.assertIn("gpu-screen-recorder", str(result.error))


class RecordToggleTest(unittest.TestCase):
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
        self.svc = Services()

    def tearDown(self):
        self.temp.cleanup()

    def test_toggle_starts_then_stops(self):
        svc = self.svc
        r1 = record_toggle(self.paths, CaptureServices(start_detached=svc.start_detached))
        self.assertTrue(r1.ok, r1.error)
        self.assertTrue(any(c[0] == "gpu-screen-recorder" for c in svc.calls))
        svc.calls.clear()
        r2 = record_toggle(self.paths, CaptureServices(start_detached=svc.start_detached))
        self.assertTrue(r2.ok, r2.error)


if __name__ == "__main__":
    unittest.main()
