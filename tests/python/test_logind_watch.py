import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
import contextlib
import io


REPO = Path(__file__).resolve().parents[2]
WATCH = REPO / "scripts" / "logind-watch.py"


def load_watch_module():
    spec = importlib.util.spec_from_file_location("zestify_logind_watch", WATCH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LogindWatchTest(unittest.TestCase):
    def test_parses_prepare_for_sleep_true_and_false(self):
        module = load_watch_module()
        self.assertIs(module.parse_event(
            "signal time=1.0 sender=:1.2 -> destination=(null) serial=3 "
            "path=/org/freedesktop/login1; interface=org.freedesktop.login1.Manager; "
            "member=PrepareForSleep; signature=b; boolean true"
        ), True)
        self.assertIs(module.parse_event(
            "signal time=1.0 sender=:1.2 -> destination=(null) serial=4 "
            "path=/org/freedesktop/login1; interface=org.freedesktop.login1.Manager; "
            "member=PrepareForSleep; signature=b; boolean false"
        ), False)

    def test_ignores_unrelated_lines(self):
        module = load_watch_module()
        self.assertIsNone(module.parse_event("signal time=1.0 member=SomethingElse"))

    def test_inhibitor_released_only_after_confirmed_lock(self):
        module = load_watch_module()
        inhibitor = Mock()
        for rc in [0, 1]:
            inhibitor.reset_mock()
            with patch.object(module, "lock_before_sleep", return_value=True), \
                 patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], rc, "", "failed")) as run, \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                module.handle_sleep(True, inhibitor)
            self.assertIn("lock.py", run.call_args.args[0][1])
            self.assertEqual(inhibitor.release.call_count, 1 if rc == 0 else 0)

    def test_wake_reacquires_inhibitor(self):
        module = load_watch_module()
        inhibitor = Mock()
        with patch.object(module, "lock_before_sleep", return_value=True), contextlib.redirect_stdout(io.StringIO()):
            module.handle_sleep(False, inhibitor)
        inhibitor.release.assert_called_once()
        inhibitor.acquire.assert_called_once()

    def test_runs_dbus_monitor_and_emits_json_lines(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        bindir = root / "bin"
        bindir.mkdir()
        dbus_monitor = bindir / "dbus-monitor"
        dbus_monitor.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"signal time=1.0 member=PrepareForSleep; signature=b\" \"   boolean true\"\n"
            "printf '%s\\n' \"signal time=2.0 member=PrepareForSleep; signature=b; boolean false\"\n",
            encoding="utf-8",
        )
        dbus_monitor.chmod(0o755)
        config = root / "config/zestify"
        config.mkdir(parents=True)
        (config / "config.json").write_text('{"session":{"lockBeforeSleep":false}}')
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = str(config.parent)
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        result = subprocess.run(
            ["python3", str(WATCH)],
            env=env,
            text=True,
            capture_output=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            ['{"aboutToSleep": true}', '{"aboutToSleep": false}'],
        )


if __name__ == "__main__":
    unittest.main()
