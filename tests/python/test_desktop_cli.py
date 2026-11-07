"""Desktop utility tests for zesti (clipboard, emoji, workspace, window).

Injects fake process runners and a fake HyprClient so no real desktop is used.
"""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from zesti.hypr import HyprClient
from zesti.paths import Paths
from zesti.desktop import (
    clipboard_pick,
    emoji_list,
    emoji_pick,
    emoji_fetch,
    toggle_workspace,
    window_resize,
    window_pip,
    window_watch,
    EMOJIS_FILE,
)


class Result:
    def __init__(self, returncode, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def make_runner(queue):
    calls = []

    def run(cmd, input=None, **kwargs):
        calls.append((list(cmd), input))
        if not queue:
            return Result(1, "", "no scripted response")
        entry = queue.pop(0)
        rc, out = entry[0], entry[1]
        err = entry[2] if len(entry) > 2 else ""
        return Result(rc, out, err)

    return run, calls


class ClipboardTest(unittest.TestCase):
    def test_clipboard_pick_pipelines_exact_bytes(self):
        run, calls = make_runner([
            (0, "10 cliphist-a\n20 cliphist-b\n"),
            (0, "20 cliphist-b\n"),
            (0, ""),
        ])
        rc = clipboard_pick(False, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[0][0], ["cliphist", "list"])
        self.assertEqual(calls[1][0], ["fuzzel"])
        self.assertEqual(calls[1][1], "10 cliphist-a\n20 cliphist-b\n")
        self.assertEqual(calls[2][0], ["wl-copy"])
        self.assertEqual(calls[2][1], "20 cliphist-b\n")

    def test_clipboard_pick_cancellation_is_success(self):
        run, _ = make_runner([(0, "10 cliphist-a\n"), (1, "")])
        self.assertEqual(clipboard_pick(False, run), 0)

    def test_clipboard_pick_delete(self):
        run, calls = make_runner([
            (0, "10 cliphist-a\n"),
            (0, "10 cliphist-a\n"),
            (0, ""),
            (0, ""),
        ])
        rc = clipboard_pick(True, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[2][0], ["cliphist", "delete", "10 cliphist-a\n"])

    def test_missing_cliphist_returns_one_naming_it(self):
        def run(cmd, **kwargs):
            if cmd[0] == "cliphist":
                raise FileNotFoundError("cliphist")
            return Result(0, "")
        self.assertEqual(clipboard_pick(False, run), 1)


class EmojiTest(unittest.TestCase):
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

    def tearDown(self):
        self.temp.cleanup()

    def test_emoji_list_reads_zestify_data(self):
        out = emoji_list(Paths.from_env(self.env))
        self.assertIsInstance(out, str)
        self.assertGreater(len(out), 0)

    def test_emoji_pick_uses_fuzzel_and_wl_copy(self):
        paths = Paths.from_env(self.env)
        run, calls = make_runner([
            (0, "😀\n😃\n😄\n"),
            (0, "😃\n"),
            (0, ""),
        ])
        rc = emoji_pick(paths, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[1][0], ["wl-copy"])

    def test_emoji_fetch_atomic_refresh(self):
        paths = Paths.from_env(self.env)
        fetched = []
        def opener(url):
            fetched.append(url)
            return "🎉\n🚀\n"
        rc = emoji_fetch(paths, opener)
        self.assertEqual(rc, 0)
        self.assertTrue(fetched)


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home)
        self.env = {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
        }
        (self.home / ".config" / "zestify").mkdir(parents=True)
        (self.home / ".config" / "zestify" / "config.json").write_text(
            json.dumps({"toggles": {"magic": "workspace 2"}})
        )

    def test_toggle_workspace_uses_hypr_dispatch(self):
        paths = Paths.from_env(self.env)
        config = {"toggles": {"magic": "workspace 2"}}
        commands = []
        class FakeHypr:
            def dispatch(self, name, *args):
                commands.append((name, args))
                return True
        rc = toggle_workspace("magic", config, FakeHypr())
        self.assertEqual(rc, 0)
        self.assertIn(("workspace", ("2",)), commands)

    def test_toggle_workspace_falls_back_to_togglespecialworkspace(self):
        commands = []
        class FakeHypr:
            def dispatch(self, name, *args):
                commands.append((name, args))
                return False
        paths = Paths.from_env(self.env)
        config = {"toggles": {}}
        rc = toggle_workspace("magic", config, FakeHypr())
        self.assertEqual(rc, 0)
        self.assertIn(("togglespecialworkspace", ("magic",)), commands)


class WindowTest(unittest.TestCase):
    def test_window_resize_valid(self):
        self.assertEqual(window_resize("firefox", "resize", 1280, 720), 0)

    def test_window_resize_invalid_size_exits_2(self):
        self.assertEqual(window_resize("firefox", "resize", -1, 720), 2)

    def test_window_pip(self):
        self.assertEqual(window_pip("picture-in-picture"), 0)

    def test_window_watch(self):
        self.assertEqual(window_watch(), 0)


if __name__ == "__main__":
    unittest.main()
