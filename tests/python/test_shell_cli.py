"""Shell lifecycle and legacy-compatibility tests for zesti."""

import json
import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, Mock

from zesti.shell import (
    list_instances,
    start_shell,
    stop_shell,
    shell_status,
    shell_open,
    shell_show,
    shell_call,
    shell_logs,
    shell_restart,
)
from zesti.compat import normalize_legacy_args


class NormalizeLegacyArgsTest(unittest.TestCase):
    def test_unknown_command_passthrough(self):
        self.assertEqual(normalize_legacy_args(["start"]), ["shell", "start"])
        self.assertEqual(normalize_legacy_args(["status"]), ["shell", "status"])

    def test_ipc_maps_to_shell_open(self):
        self.assertEqual(normalize_legacy_args(["ipc", "launcher"]), ["shell", "open", "launcher"])
        self.assertEqual(normalize_legacy_args(["ipc", "wallpaper"]), ["shell", "open", "wallpaper"])

    def test_wallpaper_command_maps_to_set(self):
        self.assertEqual(
            normalize_legacy_args(["wallpaper", "FILE", "--monitor", "eDP-1"]),
            ["wallpaper", "set", "FILE", "--monitor", "eDP-1"],
        )

    def test_random_mapped(self):
        self.assertEqual(
            normalize_legacy_args(["random", "DIR", "--all"]),
            ["wallpaper", "random", "DIR", "--all"],
        )

    def test_list_and_thumb_mapped(self):
        self.assertEqual(normalize_legacy_args(["list"]), ["wallpaper", "list"])
        self.assertEqual(normalize_legacy_args(["thumb", "FILE"]), ["wallpaper", "thumb", "FILE"])

    def test_proxy_and_cache_mapped(self):
        self.assertEqual(
            normalize_legacy_args(["proxy", "ensure", "--source", "S"]),
            ["proxy", "ensure", "--source", "S"],
        )
        self.assertEqual(normalize_legacy_args(["cache", "status"]), ["cache", "status"])

    def test_control_commands_passthrough(self):
        for cmd in ["lock", "sleep", "volume", "brightness", "mic"]:
            self.assertEqual(normalize_legacy_args([cmd, "up"]), [cmd, "up"])

    def test_no_deprecation_text(self):
        # normalize_legacy_args is pure; it never prints warnings.
        self.assertEqual(normalize_legacy_args(["start"]), ["shell", "start"])


class ShellLifecycleTest(unittest.TestCase):
    def _runner(self, outputs):
        """Return a fake Runner Mock whose run() repeats the given outputs."""
        outputs = list(outputs)
        index = [0]

        def run(cmd, **kwargs):
            out = outputs[min(index[0], len(outputs) - 1)] if outputs else ""
            index[0] += 1
            return out

        return Mock(side_effect=run)

    def test_start_when_no_instance_launches_detached(self):
        run = self._runner(["No running instances"])
        with patch("zesti.shell.sleep"):
            rc = start_shell(
                type("NS", (), {"foreground": False, "log_rules": None})(),
                run=run,
            )
        self.assertEqual(rc, 0)
        launches = [c.args[0] for c in run.call_args_list
                    if c.args and c.args[0] and c.args[0][0] == "qs"
                    and "-c" in c.args[0]]
        self.assertIn(["qs", "-c", "zestify", "-n", "-d"], launches)

    def test_start_when_already_running_is_success(self):
        run = self._runner([json.dumps([{"pid": 123, "shell_id": "abc"}])])
        rc = start_shell(type("NS", (), {})(), run=run)
        self.assertEqual(rc, 0)
        # No launch attempted.
        self.assertEqual(run.call_count, 1)

    def test_failed_start_reports_quickshell_diagnostic(self):
        run = Mock(side_effect=['No running instances', subprocess.CalledProcessError(
            1, ['qs'], stderr='Could not load shell.qml')])
        diagnostic = io.StringIO()
        with contextlib.redirect_stderr(diagnostic):
            rc = start_shell(type('NS', (), {})(), run=run)
        self.assertEqual(rc, 1)
        self.assertIn('Could not load shell.qml', diagnostic.getvalue())

    def test_foreground_and_log_rules_reach_quickshell(self):
        run = self._runner(['No running instances'])
        start_shell(type('NS', (), {'foreground': True, 'log_rules': 'qtengine.*=true'})(), run=run)
        self.assertEqual(run.call_args.args[0],
                         ['qs', '-c', 'zestify', '-n', '--log-rules', 'qtengine.*=true'])

    def test_stop_graceful_then_force_after_timeout(self):
        pids = [100, 101]
        run = self._runner([json.dumps([{"pid": p} for p in pids])])
        killed = []
        sleeps = []

        with patch("zesti.shell.sleep", lambda s: sleeps.append(s)), patch(
            "zesti.shell.os"
        ) as fake_os:
            fake_os.kill = lambda pid, sig: killed.append((pid, sig))
            rc = stop_shell(run=run, timeout=0.01)
        self.assertEqual(rc, 0)
        # Every PID gets SIGTERM then SIGKILL after timeout.
        self.assertIn((100, 15), killed)
        self.assertIn((101, 15), killed)
        self.assertIn((100, 9), killed)
        self.assertIn((101, 9), killed)

    def test_stop_no_instances_is_success(self):
        run = self._runner(["No running instances"])
        rc = stop_shell(run=run)
        self.assertEqual(rc, 0)

    def test_status_json_accepts_ping_response(self):
        run = self._runner(["pong\n"])
        rc = shell_status(run=run, json_output=True)
        self.assertEqual(rc, 0)

    def test_status_malformed_list_is_runtime_failure(self):
        run = self._runner(["not json at all"])
        rc = shell_status(run=run, json_output=True)
        self.assertEqual(rc, 1)

    def test_restart_waits_for_empty_before_launch(self):
        run = self._runner(
            [
                json.dumps([{"pid": 1}]),  # instances still present
                "No running instances",     # now empty -> launch
            ]
        )
        killed = []
        with patch("zesti.shell.sleep"), patch(
            "zesti.shell.os"
        ) as fake_os:
            fake_os.kill = lambda pid, sig: killed.append((pid, sig))
            rc = shell_restart(run=run)
        self.assertEqual(rc, 0)
        launch = [c.args[0] for c in run.call_args_list if c.args[0][0] == "qs"]
        self.assertIn(["qs", "-c", "zestify", "-n", "-d"], launch)

    def test_start_and_restart_publish_custom_desktop_config_identity(self):
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": "/tmp/custom-desktop-config"}):
            for action in ("start", "restart"):
                with self.subTest(action=action):
                    run = self._runner(["No running instances"])
                    if action == "start":
                        start_shell(type("NS", (), {})(), run=run)
                    else:
                        shell_restart(run=run)
                    self.assertEqual(run.call_args.kwargs["env"]["ZESTI_DESKTOP_CONFIG_HOME"],
                                     "/tmp/custom-desktop-config")


class ShellHandlersTest(unittest.TestCase):
    def test_open_reports_missing_shell_instead_of_success(self):
        run = Mock(side_effect=subprocess.CalledProcessError(1, ['qs'], stderr='No running instances'))
        diagnostic = io.StringIO()
        with contextlib.redirect_stderr(diagnostic):
            rc = shell_open(type('NS', (), {'surface': 'launcher'})(), run=run)
        self.assertEqual(rc, 1)
        self.assertIn('No running instances', diagnostic.getvalue())

    def test_plain_status_reports_absent_shell(self):
        self.assertEqual(shell_status(run=lambda *a, **k: 'No running instances'), 1)

    def test_open_shell_open(self):
        run = lambda cmd, **kwargs: ""
        rc = shell_open(type("NS", (), {"surface": "launcher"})(), run=run)
        self.assertEqual(rc, 0)

    def test_call_and_show_and_logs_return_zero(self):
        run = lambda cmd, **kwargs: ""
        ns_call = type("NS", (), {"target": "zestify", "function": "ping", "arg": []})()
        self.assertEqual(shell_call(ns_call, run=run), 0)
        self.assertEqual(shell_show(type("NS", (), {})(), run=run), 0)
        self.assertEqual(shell_logs(type("NS", (), {})(), run=run), 0)


class ListInstancesTest(unittest.TestCase):
    def test_uses_quickshell_instance_list_command(self):
        run = Mock(return_value='[{"pid": 123}]')
        self.assertEqual(list_instances(run), [{"pid": 123}])
        run.assert_called_once_with(["qs", "list", "-c", "zestify", "--json"], check=False)

    def test_no_instances_text(self):
        run = lambda cmd, **kwargs: "No running instances"
        self.assertEqual(list_instances(run), [])

    def test_valid_json_list(self):
        run = lambda cmd, **kwargs: json.dumps([{"pid": 1}])
        self.assertEqual(list_instances(run), [{"pid": 1}])

    def test_malformed_json_returns_empty(self):
        run = lambda cmd, **kwargs: "{broken"
        self.assertEqual(list_instances(run), [])


if __name__ == "__main__":
    unittest.main()
