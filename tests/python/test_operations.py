"""Operations tests for zesti (doctor, install, update, run_repo_script).

Injects fake process runners and git so no real repository or desktop is used.
"""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.operations import doctor, run_repo_script, install, update, DoctorReport


class Result:
    def __init__(self, returncode, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def make_runner(queue):
    calls = []

    def run(cmd, **kwargs):
        calls.append(list(cmd))
        if not queue:
            return Result(0, "", "")
        entry = queue.pop(0)
        rc, out = entry[0], entry[1]
        err = entry[2] if len(entry) > 2 else ""
        return Result(rc, out, err)

    return run, calls


class DoctorTest(unittest.TestCase):
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

    def test_doctor_separates_required_and_optional(self):
        lookup = lambda tool: "/bin/" + tool if tool in ("qs", "python3", "ffmpeg", "brightnessctl", "wpctl") else None
        with patch("subprocess.run", side_effect=AssertionError("doctor must not launch tools")):
            report = doctor(self.paths, lookup=lookup)
        self.assertIsInstance(report, DoctorReport)
        self.assertEqual(report["required_missing"], [])
        self.assertIn("matugen", report["optional_missing"])

    def test_doctor_json(self):
        report = doctor(self.paths, lookup=lambda tool: "/bin/" + tool, json_output=True)
        self.assertIsInstance(report, str)
        data = json.loads(report)
        self.assertIn("required", data)


class RunRepoScriptTest(unittest.TestCase):
    def test_run_repo_script_invokes_lock(self):
        repo = Path(tempfile.mkdtemp())
        lock = repo / "scripts" / "lock.py"
        lock.parent.mkdir(parents=True)
        lock.write_text("#!/usr/bin/env python3\nimport sys\nprint(sys.argv[1:])\n")
        lock.chmod(0o755)
        run, calls = make_runner([(0, "ok", "")])
        rc = run_repo_script("lock", ["--wait"], repo, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[0][1:3], ["--wait"])


class InstallTest(unittest.TestCase):
    def test_install_invokes_repo_script(self):
        repo = Path(tempfile.mkdtemp())
        installer = repo / "install.sh"
        installer.parent.mkdir(parents=True, exist_ok=True)
        installer.write_text("#!/usr/bin/env sh\necho installed\n")
        installer.chmod(0o755)
        run, calls = make_runner([(0, "installed", "")])
        rc = install(repo, [], run)
        self.assertEqual(rc, 0)
        self.assertTrue(any("install.sh" in str(c) for c in calls))


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        (self.repo / ".git").mkdir()
        (self.repo / "scripts").mkdir()
        installer = self.repo / "install.sh"
        installer.write_text("#!/usr/bin/env sh\necho installed\n")
        installer.chmod(0o755)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_update_clean_attached_branch_pulls_and_reinstalls(self):
        commands = []
        def run(cmd, **kwargs):
            commands.append(list(cmd))
            if cmd[:2] == ["git", "pull"]:
                return Result(0, "Already up to date.", "")
            if cmd[0] == "install.sh" or (cmd and cmd[0].endswith("install.sh")):
                return Result(0, "installed", "")
            return Result(0, "", "")
        services = {
            "run": run,
            "is_attached": lambda: True,
            "is_dirty": lambda: False,
            "is_detached": lambda: False,
            "has_upstream": lambda: True,
            "shell_was_running": lambda: False,
        }
        rc = update(self.repo, check_only=False, services=services)
        self.assertEqual(rc, 0)
        self.assertTrue(any("--ff-only" in c for c in commands))
        self.assertEqual(commands[-1], [str(self.repo / "install.sh"), "--no-start"])

    def test_update_propagates_installer_failure_without_restart(self):
        restarted = []
        run, calls = make_runner([(0, ""), (7, "")])
        services = {"run": run, "is_attached": lambda: True, "is_dirty": lambda: False,
                    "is_detached": lambda: False, "has_upstream": lambda: True,
                    "shell_was_running": lambda: True, "restart_shell": lambda: restarted.append(True)}
        self.assertEqual(update(self.repo, services=services), 7)
        self.assertEqual(restarted, [])

    def test_update_restarts_only_a_previously_running_shell(self):
        run, calls = make_runner([(0, ""), (0, "")])
        services = {"run": run, "is_attached": lambda: True, "is_dirty": lambda: False,
                    "is_detached": lambda: False, "has_upstream": lambda: True,
                    "shell_was_running": lambda: True, "restart_shell": lambda: 9}
        self.assertEqual(update(self.repo, services=services), 9)

    def test_update_dirty_refused_without_reset(self):
        commands = []
        def run(cmd, **kwargs):
            commands.append(list(cmd))
            return Result(0, "", "")
        services = {
            "run": run,
            "is_attached": lambda: True,
            "is_dirty": lambda: True,
            "is_detached": lambda: False,
            "has_upstream": lambda: True,
        }
        rc = update(self.repo, check_only=False, services=services)
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(c[:2] == ["git", "pull"] for c in commands))


class RealGitUpdateTest(unittest.TestCase):
    def test_checks_actual_dirty_detached_and_upstream_state(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            def git(*args):
                return subprocess.run(["git", "-C", directory, *args], check=True,
                                      text=True, capture_output=True)
            git("init", "--initial-branch=main")
            (repo / "file").write_text("initial")
            git("add", "file")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "initial")
            git("update-ref", "refs/remotes/origin/main", "HEAD")
            git("config", "remote.origin.url", directory)
            git("config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")
            git("branch", "--set-upstream-to=origin/main")
            self.assertEqual(update(repo, check_only=True), 0)
            (repo / "untracked").write_text("keep this user work")
            self.assertEqual(update(repo, check_only=True), 1)
            self.assertEqual((repo / "untracked").read_text(), "keep this user work")
            (repo / "untracked").unlink()
            git("checkout", "--detach")
            self.assertEqual(update(repo, check_only=True), 1)
            git("checkout", "main")
            git("branch", "--unset-upstream")
            self.assertEqual(update(repo, check_only=True), 1)
            self.assertEqual(update(repo / "missing", check_only=True), 1)


if __name__ == "__main__":
    unittest.main()
