import importlib.util
import json
import os
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
LOCK = REPO / "scripts" / "lock.py"
CLI = REPO / "bin" / "zestify"


def load_lock_module():
    spec = importlib.util.spec_from_file_location("zestify_lock", LOCK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SCHEME = {
    "name": "test",
    "mode": "dark",
    "colours": {
        "background": "040304",
        "onBackground": "f1e1eb",
        "surface": "040304",
        "surfaceContainerHigh": "0c070c",
        "primary": "e3bade",
        "onPrimary": "543653",
        "error": "f97386",
    },
}


class LockTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.state = self.home / ".local" / "state" / "zestify"
        self.state.mkdir(parents=True)
        (self.state / "scheme.json").write_text(json.dumps(SCHEME), encoding="utf-8")
        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        self.env["XDG_STATE_HOME"] = str(self.home / ".local" / "state")
        self.env["XDG_CONFIG_HOME"] = str(self.home / ".config")
        self.out = self.root / "hyprlock.conf"

    def tearDown(self):
        self.temp.cleanup()

    def run_lock(self, *args):
        return subprocess.run(
            ["python3", str(LOCK), *args],
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_config_only_writes_hyprlock_blocks_and_palette(self):
        result = self.run_lock("--config-only", "--out", str(self.out))
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        text = self.out.read_text(encoding="utf-8")
        self.assertIn("background {", text)
        self.assertIn("input-field {", text)
        self.assertIn("label {", text)
        self.assertIn("rgb(f1e1eb)", text)
        self.assertIn("rgb(e3bade)", text)
        self.assertIn("color = rgba(0c070ce0)", text)
        self.assertIn("inner_color = rgba(00000000)", text)
        self.assertIn("path =", text)

    def test_full_screen_lock_tint_follows_theme_transparency_and_bar_opacity(self):
        config = self.home / ".config" / "zestify" / "config.json"
        config.parent.mkdir(parents=True)
        for transparency, background_opacity, alpha in [(0.25, 0.8, "33"), (0.75, 0.8, "99"), (1, 1, "ff")]:
            config.write_text(json.dumps({"theme": {"transparency": transparency}, "bar": {"opacity": background_opacity}}))
            result = self.run_lock("--config-only", "--out", str(self.out))
            self.assertEqual(result.returncode, 0, result.stderr)
            text = self.out.read_text()
            blocks = text.split("shape {")[1:]
            full_screen = [block.split("}")[0] for block in blocks if "size = 100%, 100%" in block]
            self.assertTrue(full_screen)
            for block in full_screen:
                self.assertIn("color = rgba(0c070c" + alpha + ")", block)
            cards = [block.split("}")[0] for block in blocks if "size = 100%, 100%" not in block]
            for block in cards:
                self.assertIn("color = rgba(00000000)", block)
            self.assertIn("brightness = 1", text)

    def test_native_handoff_enables_screencopy_fade_and_matches_preview_clock_size(self):
        module = load_lock_module()
        text = module.build_config(SCHEME, screens=[{"name": "eDP-1", "s": 0.75}])
        self.assertIn("animation = fadeIn, 1, 3, smooth", text)
        clock = text.split('text = <span weight="light">$TIME</span>')[1].split("}")[0]
        self.assertIn("font_size = 50", clock)
        self.assertIn("position = 0, 150", clock)
        with patch.dict(os.environ, {**self.env, "HYPRLOCK_BIN": "hyprlock"}), \
                patch.object(module, "screen_configs", return_value=[]), \
                patch.object(module.subprocess, "Popen") as launch, patch.object(module.time, "sleep"):
            launch.return_value.poll.return_value = None
            launch.return_value.pid = 1234
            self.assertEqual(module.main(["--out", str(self.out)]), 0)
        self.assertEqual(launch.call_args_list[0].args[0], ["hyprlock", "--config", str(self.out)])

    def test_monitor_wallpaper_uses_normalized_override_before_global(self):
        module = load_lock_module()
        directory = self.state / "wallpaper" / "monitors"
        directory.mkdir(parents=True)
        (directory / "edp-1.txt").write_text("/pictures/laptop.mp4")
        (directory / "hdmi-a-1.txt").write_text("/pictures/portrait.png")
        (directory.parent / "path.txt").write_text("/pictures/global.png")
        with patch.dict(os.environ, self.env):
            self.assertEqual(module.current_wallpaper("eDP-1"), "/pictures/laptop.mp4")
            self.assertEqual(module.current_wallpaper("HDMI-A-1"), "/pictures/portrait.png")
            self.assertEqual(module.current_wallpaper("DP-2"), "/pictures/global.png")

    def test_monitors_keep_their_wallpapers_and_palettes_with_one_password_form(self):
        module = load_lock_module()
        directory = self.state / "wallpaper" / "monitors"
        directory.mkdir(parents=True)
        first = self.root / "laptop.png"
        second = self.root / "portrait.png"
        first.write_bytes(b"image")
        second.write_bytes(b"image")
        (directory / "edp-1.txt").write_text(str(first))
        (directory / "hdmi-a-1.txt").write_text(str(second))
        (directory / "hdmi-a-1-scheme.json").write_text(json.dumps({
            "palettes": {"dark": {"primary": "abcdef", "onSurface": "fedcba"}}
        }))
        outputs = [{"name": "eDP-1", "width": 1920, "height": 1200},
                   {"name": "HDMI-A-1", "width": 1366, "height": 768, "focused": True}]
        with patch.dict(os.environ, self.env), patch.object(module, "monitors", return_value=outputs):
            screens = module.screen_configs({})
            text = module.build_config(SCHEME, screens=screens)
        self.assertEqual(text.count("background {"), 2)
        self.assertEqual(text.count("input-field {"), 1)
        self.assertIn("monitor = eDP-1\n    path = " + str(first), text)
        self.assertIn("monitor = HDMI-A-1\n    path = " + str(second), text)
        self.assertIn("rgb(abcdef)", text)
        self.assertIn("rgb(fedcba)", text)
        self.assertIn("input-field {\n    monitor = HDMI-A-1", text)
        self.assertIn("text = Session locked", text)

    def test_palette_selects_light_mode_from_legacy_dual_mode_scheme(self):
        module = load_lock_module()
        result = module.palette({"colors": {
            "primary": {"light": {"color": "123456"}, "dark": {"color": "abcdef"}},
            "on_surface": {"light": {"color": "333333"}}
        }}, "light")
        self.assertEqual(result["primary"], "123456")
        self.assertEqual(result["onSurface"], "333333")

    def test_readiness_is_reported_only_after_compositor_locked_event(self):
        module = load_lock_module()
        log = self.root / "hyprlock.log"
        log.write_text("Resources gathered\n")
        checks = iter([True, True, False])

        def alive(pid):
            value = next(checks)
            if value and log.read_text().endswith("gathered\n"):
                # First pass sees preparation, the next sees lock readiness.
                return True
            return value

        def next_frame(delay):
            log.write_text("Resources gathered\nonLockLocked called\n")

        with patch.object(module, "process_alive", side_effect=alive), \
                patch.object(module.time, "sleep", side_effect=next_frame), \
                patch.object(module, "ipc_call") as ipc:
            module.watch(1234, str(log))
        self.assertEqual(ipc.call_args_list, [unittest.mock.call("lockState", "true"),
                                             unittest.mock.call("lockState", "false")])
        self.assertFalse(log.exists())

    def test_failed_locker_never_reports_locked(self):
        module = load_lock_module()
        log = self.root / "failed.log"
        log.write_text("Could not connect to compositor\n")
        with patch.object(module, "process_alive", side_effect=[True, False]), \
                patch.object(module.time, "sleep"), patch.object(module, "ipc_call") as ipc:
            module.watch(1234, str(log))
        ipc.assert_called_once_with("lockState", "false")
        self.assertFalse(log.exists())

    def test_video_frame_timeout_falls_back_without_breaking_lock(self):
        module = load_lock_module()
        video = self.root / "wallpaper.mp4"
        video.write_bytes(b"video")
        frame_env = {**self.env, "XDG_CACHE_HOME": str(self.root / "cache")}
        with patch.dict(os.environ, frame_env), patch.object(module.shutil, "which", return_value="ffmpeg"), \
                patch.object(module.subprocess, "run", side_effect=subprocess.TimeoutExpired("ffmpeg", 30)):
            self.assertEqual(module.lock_frame(str(video)), "")

    def test_wait_defaults_false(self):
        module = load_lock_module()
        self.assertFalse(module.parse_args([]).wait)
        self.assertTrue(module.parse_args(["--wait"]).wait)

    def test_watcher_command_is_detached_pid_watch(self):
        module = load_lock_module()
        command = module.watcher_command(1234)
        self.assertIn("--watch-pid", command)
        self.assertIn("1234", command)

    def test_process_alive_rejects_zombie_children(self):
        module = load_lock_module()
        process = subprocess.Popen(["true"])
        self.addCleanup(process.wait)
        time.sleep(0.1)
        self.assertFalse(module.process_alive(process.pid))

    def test_cli_dispatches_lock(self):
        result = subprocess.run(
            [str(CLI), "lock", "--config-only", "--out", str(self.out)],
            env=self.env,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertTrue(self.out.exists())


if __name__ == "__main__":
    unittest.main()
