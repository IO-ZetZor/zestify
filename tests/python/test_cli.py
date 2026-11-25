import io
import json
import os
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from zesti.capture import CaptureResult
from zesti.cli import main
from zesti.paths import Paths


REPO = Path(__file__).resolve().parents[2]
CLI = REPO / "bin" / "zestify"


class CliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.qs = self.bin / "qs"
        self.qs.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\"\n")
        self.qs.chmod(0o755)
        self.env = os.environ.copy()
        self.env["QS_BIN"] = str(self.qs)

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args):
        return subprocess.run(
            [str(CLI), *args],
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_start_uses_detached_named_config(self):
        result = self.run_cli("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-c zestify", result.stdout)
        self.assertIn("-n", result.stdout)
        self.assertIn("-d", result.stdout)

    def test_status_calls_ping_ipc(self):
        log = self.root / "qs-status.log"
        self.env["QS_STATUS_LOG"] = str(log)
        self.qs.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$QS_STATUS_LOG\"\nprintf 'pong\\n'\n")
        result = self.run_cli("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "pong")
        self.assertEqual(log.read_text().strip(), "ipc -c zestify call zestify ping")

    def test_call_forwards_zero_or_multiple_arguments(self):
        for arguments in [(), ("theme.transparency", "0.5")]:
            with self.subTest(arguments=arguments):
                result = self.run_cli("shell", "call", "zestify", "setConfig", *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), " ".join([
                    "ipc", "-c", "zestify", "call", "zestify", "setConfig", *arguments,
                ]))

    def test_stop_calls_quit_ipc(self):
        result = self.run_cli("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "")

    def test_logs_reads_named_config_log(self):
        result = self.run_cli("logs")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "-c zestify log")


class CanonicalDispatchTest(unittest.TestCase):
    def test_proxy_forwards_the_configurable_frame_limit(self):
        for argv, fps in [([], 24), (["--max-fps", "15"], 15)]:
            with self.subTest(argv=argv), patch("zesti.cli._run_repo_script", return_value=5) as helper:
                self.assertEqual(main(["proxy", "ensure", "--source", "video.mp4",
                    "--width", "1920", "--height", "1080", *argv]), 5)
                helper.assert_called_once_with("wallpaper-proxy", ["proxy", "ensure", "--source", "video.mp4",
                    "--width", "1920", "--height", "1080", "--codec", "h264", "--crf", "20", "--max-fps", str(fps)])

    def test_clipboard_actions_and_legacy_flag_reach_the_picker(self):
        for argv, delete in [(["clipboard"], False), (["clipboard", "pick"], False),
                             (["clipboard", "delete"], True), (["clipboard", "--delete"], True)]:
            with self.subTest(argv=argv), patch("zesti.desktop.clipboard_pick", return_value=7) as picker:
                self.assertEqual(main(argv), 7)
                picker.assert_called_once_with(delete=delete)

    def test_capture_region_options_reach_the_backend(self):
        for command, handler in [(["capture", "screenshot"], "take_screenshot"),
                                 (["capture", "record", "start"], "record_start")]:
            for argv, region in [([], None), (["--region"], "auto"),
                                 (["--region", "64x32-100+0"], "64x32-100+0")]:
                with self.subTest(command=command, argv=argv), \
                     patch("zesti.capture." + handler, return_value=CaptureResult(True, cancelled=True)) as backend, \
                     redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main([*command, *argv]), 0)
                    options, paths, services = backend.call_args.args
                    self.assertEqual(options.region, region)
                    self.assertIsInstance(paths, Paths)
                    self.assertEqual(services.run.__name__, "_default_run")
                    self.assertTrue(json.loads(output.getvalue())["cancelled"])

    def test_recording_defaults_to_system_audio_and_can_opt_out(self):
        for argv, sound in [([], True), (["--sound"], True), (["--no-sound"], False)]:
            with self.subTest(argv=argv), patch("zesti.capture.record_start", return_value=CaptureResult(True)) as backend, redirect_stdout(io.StringIO()):
                self.assertEqual(main(["capture", "record", "start", *argv]), 0)
                self.assertEqual(backend.call_args.args[0].sound, sound)

    def test_cache_prune_forwards_each_keep_flag(self):
        for argv in ([], ["--keep", "first", "--keep", "second"]):
            with self.subTest(argv=argv), patch("zesti.cli._run_repo_script", return_value=5) as helper:
                self.assertEqual(main(["cache", "prune", *argv]), 5)
                helper.assert_called_once_with("wallpaper-proxy", ["cache", "prune", *argv])

    def test_config_editor_arguments_and_failures_reach_the_cli(self):
        with patch.dict(os.environ, {"EDITOR": "'/tmp/editor with spaces' --wait"}), \
             patch("zesti.controls.subprocess.run", return_value=subprocess.CompletedProcess([], 6)) as editor:
            self.assertEqual(main(["config", "edit"]), 6)
            editor.assert_called_once_with(
                ["/tmp/editor with spaces", "--wait", str(Paths.from_env(os.environ).config_file)], check=False)
        with patch.dict(os.environ, {"EDITOR": "missing-editor"}), \
             patch("zesti.controls.subprocess.run", side_effect=FileNotFoundError), \
             redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(["config", "edit"]), 1)
            self.assertIn("missing editor: missing-editor", output.getvalue())


if __name__ == "__main__":
    unittest.main()
