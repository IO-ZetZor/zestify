"""Check native-style launch ownership, child routing and window-level QSS."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch


SOURCE = Path(__file__).resolve().parents[2] / "data/dolphin/launch.py"
spec = importlib.util.spec_from_file_location("dolphin_profile_launcher", SOURCE)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class DolphinLauncherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="Dolphin user's ")
        self.profile = Path(self.temp.name)
        (self.profile / "dolphin.qss").write_text("QToolBar { border: none; }\n")
        self.process = Mock(pid=456)
        self.process.poll.return_value = None
        self.process.wait.return_value = 0

    def tearDown(self):
        self.temp.cleanup()

    def test_url_launch_owns_breeze_process_and_styles_all_main_windows(self):
        objects = "/MainApplication\n/dolphin/Dolphin_1\n/dolphin/Dolphin_1/actions\n/dolphin/Dolphin_2\n"
        with patch.dict(os.environ, {"PATH": "/usr/bin"}), \
             patch.object(launcher.shutil, "which", return_value="/usr/bin/qdbus6"), \
             patch.object(launcher.subprocess, "Popen", return_value=self.process) as spawn, \
             patch.object(launcher.subprocess, "run") as run:
            run.side_effect = [subprocess.CompletedProcess([], 0, objects),
                               subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0)]
            self.assertEqual(launcher.launch(["--select", "/tmp/a file"], self.profile), 0)
        command = spawn.call_args.args[0]
        self.assertEqual(command, ["/usr/bin/dolphin", "-style", "breeze", "--select", "/tmp/a file"])
        self.assertEqual(spawn.call_args.kwargs["env"]["PATH"], str(self.profile) + ":/usr/bin")
        calls = [call.args[0] for call in run.call_args_list]
        self.assertEqual([call[2] for call in calls[1:]], ["/dolphin/Dolphin_1", "/dolphin/Dolphin_2"])
        self.assertTrue(all(call[3] == "org.qtproject.Qt.QWidget.setStyleSheet" for call in calls[1:]))
        self.assertTrue(all(call[1] == "org.kde.dolphin-456" for call in calls))

    def test_daemon_waits_without_expectation_of_an_initial_window(self):
        with patch.object(launcher.shutil, "which", return_value="/usr/bin/qdbus6"), \
             patch.object(launcher.subprocess, "Popen", return_value=self.process) as spawn, \
             patch.object(launcher.subprocess, "run") as run:
            self.assertEqual(launcher.launch(["--daemon"], self.profile), 0)
        self.assertNotIn("--new-window", spawn.call_args.args[0])
        self.assertTrue(spawn.call_args.kwargs["env"]["PATH"].startswith(str(self.profile) + os.pathsep))
        run.assert_not_called()
        self.process.wait.assert_called_once()

    def test_startup_timeout_is_retried_and_explicit_new_window_is_preserved(self):
        with patch.object(launcher.shutil, "which", return_value="/usr/bin/qdbus6"), \
             patch.object(launcher.subprocess, "Popen", return_value=self.process) as spawn, \
             patch.object(launcher.subprocess, "run") as run, \
             patch.object(launcher.time, "sleep"):
            run.side_effect = [subprocess.TimeoutExpired("qdbus6", 2),
                               subprocess.CompletedProcess([], 0, "/dolphin/Dolphin_7\n"),
                               subprocess.CompletedProcess([], 0)]
            self.assertEqual(launcher.launch(["--new-window", "/tmp"], self.profile), 0)
        self.assertEqual(spawn.call_args.args[0].count("--new-window"), 1)
        self.assertEqual(run.call_count, 3)

    def test_existing_tab_forward_does_not_wait_on_an_exited_child_service(self):
        self.process.poll.return_value = 0
        with patch.object(launcher.shutil, "which", return_value="/usr/bin/qdbus6"), \
             patch.object(launcher.subprocess, "Popen", return_value=self.process) as spawn, \
             patch.object(launcher.subprocess, "run") as run:
            self.assertEqual(launcher.launch(["/tmp/folder"], self.profile), 0)
        self.assertNotIn("--new-window", spawn.call_args.args[0])
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
