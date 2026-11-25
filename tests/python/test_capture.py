"""Capture regression tests; synthetic tools never access the desktop."""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti import capture as capture_mod
from zesti.capture import (
    CaptureServices, RecordOptions, ScreenshotOptions,
    record_pause, record_start, record_status, record_stop, record_toggle, take_screenshot,
)

PNG = b"\x89PNG\r\n\x1a\nsynthetic PNG payload"
MONITORS = [{"name": "DP-1", "focused": False, "refreshRate": 60},
            {"name": "eDP-1", "focused": True, "refreshRate": 120}]


class Services:
    def __init__(self):
        self.calls = []
        self.kwargs = []
        self.notify_calls = []
        self.clipboard_calls = []

    def run(self, cmd, **kwargs):
        self.calls.append(list(cmd))
        self.kwargs.append(kwargs)
        if cmd[0] == "hyprctl":
            return subprocess.CompletedProcess(cmd, 0, json.dumps(MONITORS))
        if cmd[0] == "slurp":
            return subprocess.CompletedProcess(cmd, 0, "-50,30 640x360\n")
        if cmd[0] in ("grim", "grimblast"):
            Path(cmd[-1]).write_bytes(PNG)
        return subprocess.CompletedProcess(cmd, 0, "")

    def notify(self, *args):
        self.notify_calls.append(args)

    def clipboard(self, data):
        self.clipboard_calls.append(data)
        return 0


class CaptureFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.paths = Paths.from_env({"HOME": str(self.root),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_CONFIG_HOME": str(self.root / "config")})
        self.svc = Services()


class ScreenshotTest(CaptureFixture):
    def test_focused_monitor_capture_copies_png_bytes(self):
        result = take_screenshot(ScreenshotOptions(), self.paths, CaptureServices(run=self.svc.run))
        self.assertTrue(result.ok, result.error)
        self.assertEqual(self.svc.calls[1][:-1], ["grim", "-o", "eDP-1"])
        self.assertEqual(self.svc.calls[2], ["wl-copy", "--type", "image/png"])
        self.assertEqual(self.svc.kwargs[2]["input"], PNG)
        self.assertFalse(self.svc.kwargs[2]["text"])
        self.assertEqual(Path(result.path).read_bytes(), PNG)
        self.assertIn("zestify/screenshots", result.path)

    def test_region_uses_selector_geometry(self):
        result = take_screenshot(ScreenshotOptions(region="auto"), self.paths, CaptureServices(run=self.svc.run))
        self.assertTrue(result.ok, result.error)
        self.assertEqual(self.svc.calls[1][1:3], ["-g", "-50,30 640x360"])

    def test_explicit_region_does_not_launch_selector(self):
        result = take_screenshot(ScreenshotOptions(region="1920x1080+0+0"), self.paths, CaptureServices(run=self.svc.run))
        self.assertTrue(result.ok, result.error)
        self.assertEqual(self.svc.calls[0][1:3], ["-g", "0,0 1920x1080"])
        self.assertFalse(any(call[0] == "slurp" for call in self.svc.calls))

    def test_freeze_uses_one_backend_and_copies_its_result(self):
        result = take_screenshot(ScreenshotOptions(freeze=True), self.paths, CaptureServices(run=self.svc.run))
        self.assertTrue(result.ok, result.error)
        self.assertEqual(self.svc.calls[0][:-1], ["grimblast", "--freeze", "save", "area"])
        self.assertEqual([cmd[0] for cmd in self.svc.calls], ["grimblast", "wl-copy"])

    def test_cancellation_is_success_without_capture(self):
        for rc, out in [(1, ""), (0, "")]:
            with self.subTest(rc=rc):
                result = take_screenshot(ScreenshotOptions(region="auto"), self.paths,
                    CaptureServices(run=lambda cmd, **kw: subprocess.CompletedProcess(cmd, rc, out)))
                self.assertTrue(result.ok)
                self.assertTrue(result.cancelled)

    def test_missing_grim_names_dependency(self):
        def run(cmd, **kwargs):
            if cmd[0] == "grim":
                raise FileNotFoundError("grim")
            return self.svc.run(cmd, **kwargs)
        result = take_screenshot(ScreenshotOptions(), self.paths, CaptureServices(run=run))
        self.assertFalse(result.ok)
        self.assertIn("grim", result.error)

    def test_backend_success_without_file_is_failure(self):
        result = take_screenshot(ScreenshotOptions(region="1x1+0+0"), self.paths,
            CaptureServices(run=lambda cmd, **kw: subprocess.CompletedProcess(cmd, 0, "")))
        self.assertFalse(result.ok)
        self.assertIn("produce", result.error)

    def test_clipboard_failure_preserves_saved_image(self):
        def run(cmd, **kwargs):
            result = self.svc.run(cmd, **kwargs)
            if cmd[0] == "wl-copy":
                result.returncode = 1
            return result
        result = take_screenshot(ScreenshotOptions(), self.paths, CaptureServices(run=run))
        self.assertFalse(result.ok)
        self.assertEqual(Path(result.path).read_bytes(), PNG)

    def test_real_subprocess_pipeline_with_synthetic_tools(self):
        tool = self.root / "tool.py"
        tool.write_text("import pathlib,sys\n"
            "cmd=sys.argv[1]\n"
            "if cmd == 'grim': pathlib.Path(sys.argv[-1]).write_bytes(" + repr(PNG) + ")\n"
            "elif cmd == 'wl-copy': pathlib.Path(" + repr(str(self.root / "clipboard")) + ").write_bytes(sys.stdin.buffer.read())\n")
        def run(cmd, **kwargs):
            kwargs.setdefault("capture_output", True)
            kwargs.setdefault("text", True)
            return subprocess.run([sys.executable, str(tool), *cmd], **kwargs)
        result = take_screenshot(ScreenshotOptions(region="1x1+0+0"), self.paths, CaptureServices(run=run))
        self.assertTrue(result.ok, result.error)
        self.assertEqual((self.root / "clipboard").read_bytes(), PNG)


class ClipboardProcessTest(CaptureFixture):
    def setUp(self):
        super().setUp()
        self.worker_pid = self.root / "worker.pid"
        self.finished = self.root / "worker.finished"
        self.tool = self.root / "clipboard-owner.py"
        self.tool.write_text("""import os, sys, time
from pathlib import Path
sys.stdin.buffer.read()
pid = os.fork()
if pid == 0:
    # Model wl-copy's owner: close stdin/stdout but retain inherited stderr.
    os.close(0)
    os.close(1)
    time.sleep(1)
    Path(sys.argv[2]).touch()
    os._exit(0)
Path(sys.argv[1]).write_text(str(pid))
""")
        self.addCleanup(self.stop_worker)

    def stop_worker(self):
        if self.worker_pid.exists():
            try:
                os.kill(int(self.worker_pid.read_text()), signal.SIGTERM)
            except ProcessLookupError:
                pass

    def clipboard_run(self, cmd, **kwargs):
        return capture_mod._default_run(
            [sys.executable, str(self.tool), str(self.worker_pid), str(self.finished)], **kwargs)

    def test_screenshot_returns_while_clipboard_owner_is_alive(self):
        def run(cmd, **kwargs):
            if cmd[0] == "wl-copy":
                return self.clipboard_run(cmd, **kwargs)
            return self.svc.run(cmd, **kwargs)
        result = take_screenshot(ScreenshotOptions(region="1x1+0+0"), self.paths,
                                 CaptureServices(run=run))
        self.assertTrue(result.ok, result.error)
        self.assertTrue(self.worker_pid.exists())
        self.assertFalse(self.finished.exists(), "Capture waited for the background clipboard owner")

    def test_recording_uri_returns_while_clipboard_owner_is_alive(self):
        default_run = capture_mod._default_run
        with patch("zesti.capture._default_run", side_effect=lambda cmd, **kwargs: default_run(
                [sys.executable, str(self.tool), str(self.worker_pid), str(self.finished)], **kwargs)):
            self.assertEqual(capture_mod._default_clipboard("file:///tmp/recording.mp4"), 0)
        self.assertTrue(self.worker_pid.exists())
        self.assertFalse(self.finished.exists(), "Recording waited for the background clipboard owner")


class RecordingTest(CaptureFixture):
    def setUp(self):
        super().setUp()
        self.children = []
        self.recorder = self.root / "recorder.py"
        self.recorder.write_text("""import os,signal,sys,time
from pathlib import Path
output=Path(sys.argv[sys.argv.index('-o')+1])
output.write_bytes(b'initial')
def stop(sig,frame):
    with output.open('ab') as file: file.write(b' finalized')
    sys.exit(0)
def pause(sig,frame):
    output.with_suffix('.paused').write_text('paused')
signal.signal(signal.SIGINT,stop)
signal.signal(signal.SIGUSR2,pause)
while True: time.sleep(0.02)
""")
        self.addCleanup(self.cleanup_children)
        self.services = CaptureServices(run=self.svc.run,
            start_detached=self.start_detached, clipboard=self.svc.clipboard)

    def cleanup_children(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=3)

    def start_detached(self, cmd, **kwargs):
        self.svc.calls.append(list(cmd))
        child = subprocess.Popen([sys.executable, str(self.recorder), *cmd[1:]])
        self.children.append(child)
        return child

    def start(self):
        result = record_start(RecordOptions(), self.paths, self.services)
        self.assertTrue(result.ok, result.error)
        return result

    def test_record_start_uses_native_flags_and_tracks_identity(self):
        result = self.start()
        command = next(cmd for cmd in self.svc.calls if cmd[0] == "gpu-screen-recorder")
        self.assertEqual(command[1:9], ["-w", "eDP-1", "-f", "120", "-c", "mp4", "-a", "default_output"])
        marker = self.paths.state_home / "zestify/record/recording"
        state = json.loads(marker.read_text())
        self.assertEqual(state["pid"], self.children[0].pid)
        self.assertTrue(state["start_ticks"].isdigit())
        self.assertEqual(state["output"], result.path)
        self.assertTrue(result.recording)

    def test_recording_without_sound_omits_system_audio(self):
        result = record_start(RecordOptions(sound=False), self.paths, self.services)
        self.assertTrue(result.ok, result.error)
        command = next(cmd for cmd in self.svc.calls if cmd[0] == "gpu-screen-recorder")
        self.assertNotIn("-a", command)

    def test_custom_microphone_arguments_preserve_system_audio(self):
        self.paths.config_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.config_file.write_text(json.dumps({"record": {"extraArgs": ["-a", "default_input", "-ac", "aac"]}}))
        self.start()
        command = next(cmd for cmd in self.svc.calls if cmd[0] == "gpu-screen-recorder")
        self.assertEqual(command[7:-2], ["-a", "default_output", "-a", "default_input", "-ac", "aac"])

    def test_status_tracks_owned_process_without_changing_marker(self):
        self.assertEqual(record_status(self.paths), {"recording": False, "path": None, "error": None})
        self.assertFalse((self.paths.state_home / "zestify/record").exists())
        started = self.start()
        marker = self.paths.state_home / "zestify/record/recording"
        original = marker.read_bytes()
        self.assertEqual(record_status(self.paths), {"recording": True, "path": started.path, "error": None})
        self.assertEqual(marker.read_bytes(), original)
        self.children[0].terminate()
        self.children[0].wait(timeout=2)
        status = record_status(self.paths)
        self.assertFalse(status["recording"])
        self.assertIn("unexpectedly", status["error"])
        self.assertEqual(marker.read_bytes(), original)

    def test_status_rejects_reused_identity_without_signaling(self):
        self.start()
        marker = self.paths.state_home / "zestify/record/recording"
        state = json.loads(marker.read_text())
        state["start_ticks"] = "0"
        marker.write_text(json.dumps(state))
        status = record_status(self.paths)
        self.assertFalse(status["recording"])
        self.assertIn("reused", status["error"])
        self.assertIsNone(self.children[0].poll())

    def test_record_pause_signals_only_owned_recorder(self):
        result = self.start()
        paused = record_pause(self.paths, self.services)
        self.assertTrue(paused.ok, paused.error)
        path = Path(result.path).with_suffix('.paused')
        deadline = time.monotonic() + 2
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(path.exists())
        self.assertFalse(any(cmd[0] == 'pkill' for cmd in self.svc.calls))

    def test_record_stop_waits_for_finalization_and_copies_uri(self):
        started = self.start()
        result = record_stop(True, self.paths, self.services)
        self.assertTrue(result.ok, result.error)
        self.assertFalse(result.recording)
        self.children[0].wait(timeout=2)
        self.assertEqual(Path(result.path).read_bytes(), b'initial finalized')
        self.assertEqual(result.path, started.path)
        self.assertEqual(self.svc.clipboard_calls, [Path(result.path).as_uri()])
        self.assertFalse((self.paths.state_home / 'zestify/record/recording').exists())

    def test_failed_launcher_never_creates_state(self):
        result = record_start(RecordOptions(), self.paths,
            CaptureServices(run=self.svc.run, start_detached=lambda cmd: 1))
        self.assertFalse(result.ok)
        self.assertFalse((self.paths.state_home / 'zestify/record/recording').exists())

    def test_immediate_exit_is_failure(self):
        def launch(cmd):
            child = subprocess.Popen([sys.executable, '-c', 'raise SystemExit(7)'])
            self.children.append(child)
            return child
        result = record_start(RecordOptions(), self.paths, CaptureServices(run=self.svc.run, start_detached=launch))
        self.assertFalse(result.ok)
        self.assertIn('startup', result.error)

    def test_missing_output_is_not_fabricated(self):
        self.start()
        child = self.children[0]
        with patch('zesti.capture.signal.pidfd_send_signal', side_effect=lambda fd, sig: child.terminate()):
            source = next((self.paths.state_home / 'zestify/record').glob('*.mp4'))
            source.unlink()
            result = record_stop(False, self.paths, self.services)
        self.assertFalse(result.ok)
        self.assertFalse(list((self.paths.state_home / 'zestify/record').glob('*.mp4')))

    def test_exited_recorder_reports_failure_and_clears_stale_state(self):
        self.start()
        self.children[0].terminate()
        self.children[0].wait(timeout=2)
        result = record_stop(False, self.paths, self.services)
        self.assertFalse(result.ok)
        self.assertIn('unexpectedly', result.error)
        self.assertTrue(Path(result.path).exists())
        self.assertFalse((self.paths.state_home / 'zestify/record/recording').exists())

    def test_rebooted_state_never_signals_an_unrelated_process(self):
        self.start()
        marker = self.paths.state_home / 'zestify/record/recording'
        state = json.loads(marker.read_text())
        state['boot_id'] = 'previous-boot'
        marker.write_text(json.dumps(state))
        with patch('zesti.capture.signal.pidfd_send_signal') as send_signal:
            result = record_stop(False, self.paths, self.services)
        self.assertFalse(result.ok)
        send_signal.assert_not_called()
        self.assertIsNone(self.children[0].poll())

    def test_reused_pid_identity_is_rejected_without_signal(self):
        self.start()
        marker = self.paths.state_home / 'zestify/record/recording'
        state = json.loads(marker.read_text())
        state['start_ticks'] = '0'
        marker.write_text(json.dumps(state))
        with patch('zesti.capture.signal.pidfd_send_signal') as send_signal:
            result = record_stop(False, self.paths, self.services)
        self.assertFalse(result.ok)
        self.assertIn('reused', result.error)
        send_signal.assert_not_called()
        self.assertIsNone(self.children[0].poll())

    def test_missing_recorder_names_dependency(self):
        def launch(cmd):
            raise FileNotFoundError('gpu-screen-recorder')
        result = record_start(RecordOptions(), self.paths, CaptureServices(run=self.svc.run, start_detached=launch))
        self.assertFalse(result.ok)
        self.assertIn('gpu-screen-recorder', result.error)

    def test_toggle_starts_then_stops(self):
        self.assertTrue(record_toggle(self.paths, self.services).ok)
        command = next(cmd for cmd in self.svc.calls if cmd[0] == "gpu-screen-recorder")
        self.assertEqual(command[7:9], ["-a", "default_output"])
        self.assertTrue(record_toggle(self.paths, self.services).ok)

    def test_default_recorder_lifecycle_across_cli_processes(self):
        recorder = self.root / 'gpu-screen-recorder'
        recorder.write_text('#!' + sys.executable + '\n' + self.recorder.read_text())
        recorder.chmod(0o755)
        env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'],
            XDG_STATE_HOME=str(self.paths.state_home), XDG_CONFIG_HOME=str(self.paths.config_home),
            XDG_CACHE_HOME=str(self.paths.cache_home))
        preamble = ('import json,os; from dataclasses import asdict; from zesti.capture import *; '
                    'from zesti.paths import Paths; paths=Paths.from_env(os.environ); ')
        started = subprocess.run([sys.executable, '-c', preamble +
            'print(json.dumps(asdict(record_start(RecordOptions(region="1x1+0+0"),paths,CaptureServices()))))'],
            env=env, capture_output=True, text=True, timeout=5)
        result = json.loads(started.stdout)
        self.assertTrue(result['ok'], result)
        stopped = subprocess.run([sys.executable, '-c', preamble +
            'print(json.dumps(asdict(record_stop(False,paths,CaptureServices()))))'],
            env=env, capture_output=True, text=True, timeout=5)
        final = json.loads(stopped.stdout)
        self.assertTrue(final['ok'], final)
        self.assertEqual(Path(final['path']).read_bytes(), b'initial finalized')


if __name__ == '__main__':
    unittest.main()
