"""Operations tests for zesti (doctor, install, update, run_repo_script).

Injects fake process runners and git so no real repository or desktop is used.
"""

import json
import os
import stat
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
        def run(cmd, **kwargs):
            # qs present, matugen missing
            if cmd[0] in ("qs", "python3", "ffmpeg", "hyprlock", "brightnessctl", "wpctl"):
                return Result(0, "", "")
            return Result(1, "", "not found")
        report = doctor(self.paths, run)
        self.assertIsInstance(report, DoctorReport)
        self.assertEqual(report["required_missing"], [])
        self.assertIn("matugen", report["optional_missing"])

    def test_doctor_json(self):
        def run(cmd, **kwargs):
            return Result(0, "", "")
        report = doctor(self.paths, run, json_output=True)
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
        rc = run_repo_script("lock", ["--config-only"], repo, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[0][1:3], ["--config-only"])


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
        }
        rc = update(self.repo, check_only=False, services=services)
        self.assertEqual(rc, 0)
        self.assertTrue(any("--ff-only" in c for c in commands))

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


if __name__ == "__main__":
    unittest.main()
