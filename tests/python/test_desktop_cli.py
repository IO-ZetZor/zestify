"""Desktop utility tests for zesti (clipboard, emoji, workspace, window).

Injects fake process runners and a fake HyprClient so no real desktop is used.
"""

import json
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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
            (0, b"\x89PNG\x00\xffexact bytes"),
            (0, ""),
        ])
        rc = clipboard_pick(False, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[0][0], ["cliphist", "list"])
        self.assertEqual(calls[1][0], ["fuzzel", "--dmenu"])
        self.assertEqual(calls[1][1], "10 cliphist-a\n20 cliphist-b\n")
        self.assertEqual(calls[2][0], ["cliphist", "decode"])
        self.assertEqual(calls[2][1], b"20 cliphist-b\n")
        self.assertEqual(calls[3][0], ["wl-copy"])
        self.assertEqual(calls[3][1], b"\x89PNG\x00\xffexact bytes")

    def test_clipboard_pick_cancellation_is_success(self):
        run, _ = make_runner([(0, "10 cliphist-a\n"), (1, "")])
        self.assertEqual(clipboard_pick(False, run), 0)

    def test_clipboard_pick_delete(self):
        run, calls = make_runner([
            (0, "10 cliphist-a\n"),
            (0, "10 cliphist-a\n"),
            (0, b"decoded clipboard"),
            (0, ""),
            (0, ""),
        ])
        rc = clipboard_pick(True, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[3][0], ["cliphist", "delete"])
        self.assertEqual(calls[3][1], "10 cliphist-a\n")

    def test_decoder_failure_is_not_copied(self):
        run, calls = make_runner([(0, "1 preview\n"), (0, "1 preview\n"), (7, b"")])
        self.assertEqual(clipboard_pick(False, run), 7)
        self.assertFalse(any(cmd[0] == "wl-copy" for cmd, _ in calls))

    def test_delete_failure_is_not_copied(self):
        run, calls = make_runner([(0, "1 preview\n"), (0, "1 preview\n"), (0, b"real data"), (5, "")])
        self.assertEqual(clipboard_pick(True, run), 5)
        self.assertFalse(any(cmd[0] == "wl-copy" for cmd, _ in calls))

    def test_real_subprocess_pipeline_preserves_binary_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = b"\x89PNG\x00\xffbinary data"
            tool = root / "tool.py"
            tool.write_text("import pathlib,sys\n"
                "command=sys.argv[1:]\n"
                "if command==['cliphist','list']: print('1 image preview')\n"
                "elif command[0]=='fuzzel': sys.stdout.write(sys.stdin.read())\n"
                "elif command==['cliphist','decode']: sys.stdout.buffer.write(" + repr(payload) + ")\n"
                "elif command[0]=='wl-copy': pathlib.Path(" + repr(str(root / 'clipboard')) + ").write_bytes(sys.stdin.buffer.read())\n")
            def run(cmd, **kwargs):
                kwargs.setdefault('capture_output', True)
                kwargs.setdefault('text', True)
                return subprocess.run([sys.executable, str(tool), *cmd], **kwargs)
            self.assertEqual(clipboard_pick(False, run), 0)
            self.assertEqual((root / 'clipboard').read_bytes(), payload)

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
            (0, "😃 happy face\n"),
            (0, ""),
        ])
        rc = emoji_pick(paths, run)
        self.assertEqual(rc, 0)
        self.assertEqual(calls[0][0], ["fuzzel", "--dmenu"])
        self.assertEqual(calls[1][0], ["wl-copy", "--type", "text/plain"])
        self.assertEqual(calls[1][1], "😃")

    def test_emoji_fetch_atomic_refresh(self):
        paths = Paths.from_env(self.env)
        fetched = []
        def opener(url):
            fetched.append(url)
            return "🎉\n🚀\n"
        rc = emoji_fetch(paths, opener)
        self.assertEqual(rc, 0)
        self.assertTrue(fetched)
        self.assertEqual(emoji_list(paths), "🎉\n🚀\n")

    def test_failed_or_empty_fetch_preserves_saved_data(self):
        paths = Paths.from_env(self.env)
        emoji_fetch(paths, lambda url: "🎉\n")
        for content in ("", "<html>service unavailable</html>", "not emoji"):
            self.assertEqual(emoji_fetch(paths, lambda url: content), 1)
            self.assertEqual(emoji_list(paths), "🎉\n")

    def test_unicode_source_is_converted_to_picker_rows(self):
        paths = Paths.from_env(self.env)
        source = "# Emoji test\n1F600 ; fully-qualified # 😀 E1.0 grinning face\n1F3FB ; component # 🏻 E1.0 light skin tone\n"
        self.assertEqual(emoji_fetch(paths, lambda url: source), 0)
        self.assertEqual(emoji_list(paths), "😀 grinning face\n")


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
        self.assertEqual(rc, 1)
        self.assertIn(("togglespecialworkspace", ("magic",)), commands)


class WindowTest(unittest.TestCase):
    class FakeHypr:
        def __init__(self):
            self.commands = []
            self.windows = [{"address": "0xabc", "class": "firefox", "title": "picture-in-picture", "monitor": 0, "size": [1280, 720]}]

        def message(self, command):
            if command == 'j/clients':
                return self.windows
            if command == 'j/activewindow':
                return self.windows[0]
            if command == 'j/monitors':
                return [{'id': 0, 'x': 0, 'y': 0, 'width': 1920, 'height': 1080, 'scale': 1}]
            raise AssertionError(command)

        def dispatch(self, name, arguments):
            self.commands.append((name, arguments))
            return True

    def test_window_resize_valid(self):
        hypr = self.FakeHypr()
        self.assertEqual(window_resize("firefox", "resize", 1280, 720, hypr), 0)
        self.assertEqual(hypr.commands, [('resizewindowpixel', 'exact 1280 720,address:0xabc')])

    def test_window_resize_invalid_size_exits_2(self):
        self.assertEqual(window_resize("firefox", "resize", -1, 720), 2)

    def test_window_move_accepts_negative_and_zero_coordinates(self):
        hypr = self.FakeHypr()
        self.assertEqual(window_resize("firefox", "move", -1920, 0, hypr), 0)
        self.assertEqual(hypr.commands, [("movewindowpixel", "exact -1920 0,address:0xabc")])

    def test_window_pip(self):
        hypr = self.FakeHypr()
        self.assertEqual(window_pip("picture-in-picture", hypr), 0)
        self.assertEqual(hypr.commands[0], ('setfloating', 'address:0xabc'))
        self.assertEqual(hypr.commands[-1], ('pin', 'address:0xabc'))
        self.assertIn(('resizewindowpixel', 'exact 480 270,address:0xabc'), hypr.commands)

    def test_window_invalid_regex_and_missing_match_are_errors(self):
        hypr = self.FakeHypr()
        self.assertEqual(window_resize('[', 'resize', 100, 100, hypr), 2)
        self.assertEqual(window_resize('nomatch', 'resize', 100, 100, hypr), 1)
        self.assertEqual(hypr.commands, [])

    def test_window_malformed_geometry_returns_failure_without_dispatch(self):
        hypr = self.FakeHypr()
        hypr.windows[0]['size'] = []
        self.assertEqual(window_pip('firefox', hypr), 1)
        self.assertEqual(hypr.commands, [])

    def test_window_watch(self):
        class Stream:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def connect(self, address): pass
            def makefile(self, mode):
                return io.BytesIO(b'workspace>>1\nopenwindow>>abc,1,firefox,title\nclosewindow>>abc\n')
        output = io.StringIO()
        with patch('zesti.desktop.socket.socket', return_value=Stream()):
            self.assertEqual(window_watch(Path('/tmp/fake.socket'), output), 0)
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([event['event'] for event in events], ['openwindow', 'closewindow'])


if __name__ == "__main__":
    unittest.main()
