import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
AUTOSTART_ORIGINAL = '    hl.exec_cmd("caelestia shell")\n'


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.conf = self.home / ".config" / "hypr" / "conf"
        self.conf.mkdir(parents=True)
        write(
            self.conf / "autostart.lua",
            "hl.on(\"hyprland.start\", function()\n" + AUTOSTART_ORIGINAL + "end)\n",
        )
        write(
            self.conf / "binds.lua",
            'local C = require("conf.const")\nlocal M = C.mod\n'
            'hl.bind(M .. " + Escape", hl.dsp.exec_cmd("caelestia shell lock lock"))\n',
        )
        write(self.home / ".config" / "hypr" / "hyprland.lua", 'require("conf.binds")\n')
        for name in (
            "qs", "ffmpeg", "hyprlock", "jq", "cava",
            "brightnessctl", "wpctl", "systemctl", "pkill",
        ):
            self.stub(name)
        self.stub("pgrep", "exit 1\n")
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        self.env["XDG_CONFIG_HOME"] = str(self.home / ".config")
        self.env["XDG_STATE_HOME"] = str(self.home / ".local" / "state")
        self.env["XDG_CACHE_HOME"] = str(self.home / ".cache")

    def tearDown(self):
        self.temp.cleanup()

    def stub(self, name, body="exit 0\n"):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run(
            [str(REPO / name), *args],
            cwd=REPO,
            env=self.env,
            text=True,
            capture_output=True,
        )

    def install(self, *args):
        result = self.run_script("install.sh", "--no-start", *args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_fresh_install_creates_links_blocks_and_config(self):
        self.install()
        self.assertTrue((self.home / ".config/quickshell/zestify").is_symlink())
        self.assertTrue((self.home / ".local/bin/zesti").is_symlink())
        self.assertTrue((self.home / ".local/bin/zestify").is_symlink())
        self.assertTrue((self.home / ".config/zestify/config.json").exists())
        self.assertEqual(
            (self.home / ".config/zestify/cava.conf").read_text(),
            (REPO / "config/cava.conf").read_text(),
        )
        self.assertTrue((self.conf / "zestify.lua").exists())

        binds = (self.conf / "binds.lua").read_text()
        self.assertEqual(binds.count(">>> zestify-binds >>>"), 1)
        self.assertIn('dofile(os.getenv("HOME") .. "/.config/hypr/conf/zestify.lua")', binds)

        autostart = (self.conf / "autostart.lua").read_text()
        self.assertEqual(autostart.count(">>> zestify-autostart >>>"), 1)
        self.assertIn('hl.exec_cmd("zesti shell start")', autostart)
        self.assertIn('-- hl.exec_cmd("caelestia shell")', autostart)
        self.assertNotIn('\n    hl.exec_cmd("caelestia shell")\n', autostart)
        self.assertTrue(list(self.conf.glob("*.zestify.bak.*")))

    def test_install_is_idempotent_and_preserves_user_edits(self):
        self.install()
        binds = self.conf / "binds.lua"
        binds.write_text(binds.read_text() + 'hl.bind("SUPER + X", hl.dsp.exec_cmd("true"))\n')
        self.install()
        text = binds.read_text()
        self.assertEqual(text.count(">>> zestify-binds >>>"), 1)
        self.assertIn('hl.bind("SUPER + X"', text)
        self.assertEqual((self.conf / "autostart.lua").read_text().count(">>> zestify-autostart >>>"), 1)

    def test_dry_run_writes_nothing(self):
        result = self.run_script("install.sh", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.home / ".config/quickshell/zestify").exists())
        self.assertFalse((self.home / ".config/zestify/config.json").exists())
        self.assertFalse((self.conf / "zestify.lua").exists())
        self.assertNotIn("zestify-binds", (self.conf / "binds.lua").read_text())

    def test_uninstall_removes_only_managed_state(self):
        self.install()
        write(self.home / ".config/zestify/keep.json", "{}\n")
        result = self.run_script("uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.home / ".config/quickshell/zestify").exists())
        self.assertFalse((self.home / ".local/bin/zesti").is_symlink())
        self.assertFalse((self.home / ".local/bin/zestify").is_symlink())
        self.assertFalse((self.conf / "zestify.lua").exists())
        self.assertNotIn("zestify-binds", (self.conf / "binds.lua").read_text())
        autostart = (self.conf / "autostart.lua").read_text()
        self.assertNotIn("zestify-autostart", autostart)
        self.assertNotIn(AUTOSTART_ORIGINAL, autostart)
        self.assertTrue((self.home / ".config/zestify/keep.json").exists())

    def test_uninstall_purge_removes_config_state_and_cache(self):
        self.install()
        for path in (
            self.home / ".config/zestify/keep.json",
            self.home / ".local/state/zestify/keep.json",
            self.home / ".cache/zestify/keep.json",
        ):
            write(path, "{}\n")
        result = self.run_script("uninstall.sh", "--purge")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.home / ".config/zestify").exists())
        self.assertFalse((self.home / ".local/state/zestify").exists())
        self.assertFalse((self.home / ".cache/zestify").exists())

    def test_migration_copies_state_without_caelestia(self):
        state = self.home / ".local/state/caelestia/wallpaper"
        write(state / "path.txt", "/wallpapers/global.png\n")
        write(state / "monitors/eDP-1.txt", "/wallpapers/primary.png\n")
        write(state / "monitors/HDMI-A-1.txt", "/wallpapers/secondary.png\n")
        write(state / "scheme.json", '{"primary": "112233", "mode": "dark"}\n')
        result = subprocess.run(
            ["python3", str(REPO / "scripts/migrate-state.py"), "--force"],
            cwd=REPO,
            env=self.env,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        invocation = json.loads(result.stdout)
        self.assertTrue(invocation["ok"], invocation.get("errors"))
        self.assertTrue(invocation["copied_global"])
        self.assertTrue(invocation["copied_scheme"])
        self.assertTrue(invocation["marker_written"])
        self.assertEqual(
            set(invocation["copied_monitors"]),
            {"eDP-1", "HDMI-A-1"},
        )
        zest = self.home / ".local/state/zestify"
        self.assertEqual(
            (zest / "wallpaper" / "path.txt").read_text().strip(),
            "/wallpapers/global.png",
        )
        self.assertEqual(
            (zest / "wallpaper" / "monitors" / "edp-1.txt").read_text().strip(),
            "/wallpapers/primary.png",
        )
        self.assertEqual(
            (zest / "wallpaper" / "monitors" / "hdmi-a-1.txt").read_text().strip(),
            "/wallpapers/secondary.png",
        )
        self.assertEqual((state / "path.txt").read_text().strip(), "/wallpapers/global.png")
        self.assertEqual((state / "scheme.json").read_text().strip(), '{"primary": "112233", "mode": "dark"}')


if __name__ == "__main__":
    unittest.main()
