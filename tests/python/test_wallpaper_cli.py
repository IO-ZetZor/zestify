"""CLI-level tests for zesti wallpaper commands.

Drives the canonical ``zesti`` executable through a temporary XDG home so no
real desktop or legacy shell is involved.
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
ZESTI = REPO / "bin" / "zesti"


class WallpaperCliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.wall = self.home / "Pictures" / "Wallpapers"
        self.wall.mkdir(parents=True)
        Image.new("RGB", (2, 2), (23, 41, 54)).save(self.wall / "still.png", "PNG")
        (self.wall / "clip.mp4").write_bytes(b"fake-mp4")
        config = self.home / ".config" / "zestify"
        config.mkdir(parents=True)
        config.joinpath("config.json").write_text(
            json.dumps({"monitor": {"primary": "eDP-1"}, "wallpaper": {"dir": str(self.wall)}})
        )
        self.env = dict(os.environ)
        self.env.update({
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
        })

    def tearDown(self):
        self.temp.cleanup()

    def run_zesti(self, *args):
        return subprocess.run(
            [str(ZESTI), *args], env=self.env, text=True, capture_output=True
        )

    def test_list_json_retains_item_schema(self):
        result = self.run_zesti("wallpaper", "list", "--json")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        items = json.loads(result.stdout)
        by_name = {it["name"]: it for it in items}
        self.assertEqual(set(by_name), {"still.png", "clip.mp4"})
        self.assertFalse(by_name["still.png"]["isVideo"])
        self.assertTrue(by_name["clip.mp4"]["isVideo"])
        for it in items:
            self.assertIn("path", it)
            self.assertIn("thumb", it)

    def test_set_global_writes_state_and_get_returns_it(self):
        image = self.wall / "still.png"
        result = self.run_zesti(
            "wallpaper", "set", str(image), "--monitor", "eDP-1", "--no-smart"
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"], payload)
        state = self.home / ".local/state" / "zestify" / "wallpaper" / "monitors" / "edp-1.txt"
        self.assertEqual(state.read_text().strip(), str(image))
        result = self.run_zesti("wallpaper", "get", "--monitor", "eDP-1")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(result.stdout.strip(), str(image))

    def test_random_monitor_writes_override(self):
        result = self.run_zesti(
            "wallpaper", "random", "--monitor", "eDP-1",
            "--threshold", "0.5", "--no-smart",
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"], payload)
        state = self.home / ".local/state" / "zestify" / "wallpaper" / "monitors" / "edp-1.txt"
        self.assertEqual(state.read_text().strip(), str(self.wall / "still.png"))
        self.assertFalse(
            (self.home / ".local/state" / "zestify" / "wallpaper" / "path.txt").exists()
        )

    def test_random_all_writes_global_state(self):
        result = self.run_zesti("wallpaper", "random", "--all")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"], payload)
        self.assertEqual(payload["all"], True)
        state = self.home / ".local/state" / "zestify" / "wallpaper" / "path.txt"
        self.assertEqual(state.read_text().strip(), str(self.wall / "still.png"))

    def test_invalid_file_returns_json_error(self):
        result = self.run_zesti("wallpaper", "set", str(self.home / "missing.png"))
        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        self.assertIn("error", payload)

    def set_theme_config(self, smart_scheme):
        config = self.home / ".config/zestify/config.json"
        settings = json.loads(config.read_text())
        settings["theme"] = {"mode": "dark", "apply": False, "smartScheme": smart_scheme}
        config.write_text(json.dumps(settings))

    def test_smart_config_and_no_smart_override_reach_set_and_random(self):
        gray = self.wall / "still.png"
        Image.new("RGB", (16, 16), (128, 128, 128)).save(gray)
        self.set_theme_config(True)
        scheme_file = self.home / ".local/state/zestify/scheme.json"
        for command, smart, flags in [("set", True, []), ("set", True, ["--no-smart"]), ("random", True, []), ("random", True, ["--no-smart"]), ("set", False, [])]:
            with self.subTest(command=command, smart=smart, flags=flags):
                self.set_theme_config(smart)
                # Clear the active path so random can choose the only image.
                active = self.home / ".local/state/zestify/wallpaper/path.txt"
                if active.exists():
                    active.write_text("")
                args = ["wallpaper", command]
                if command == "set":
                    args.append(str(gray))
                result = self.run_zesti(*args, "--all", *flags)
                self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
                scheme = json.loads(scheme_file.read_text())
                self.assertEqual(scheme["variant"], "neutral" if smart and not flags else "tonalspot")
                self.assertEqual(scheme["flavour"], "hard")
                self.assertEqual(scheme["mode"], "dark")

    def test_refresh_updates_global_and_monitor_palettes_without_changing_paths(self):
        self.set_theme_config(True)
        gray = self.wall / "still.png"
        Image.new("RGB", (16, 16), (128, 128, 128)).save(gray)
        for flags in [("--all",), ("--monitor", "HDMI-A-1")]:
            result = self.run_zesti("wallpaper", "set", str(gray), *flags)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        state = self.home / ".local/state/zestify"
        global_scheme = state / "scheme.json"
        monitor_scheme = state / "wallpaper/monitors/hdmi-a-1-scheme.json"
        self.assertEqual(json.loads(global_scheme.read_text())["variant"], "neutral")
        self.set_theme_config(False)
        before_paths = {path: path.read_bytes() for path in (state / "wallpaper").rglob("*.txt")}
        result = self.run_zesti("wallpaper", "refresh")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(json.loads(result.stdout)["updated"], 2)
        for scheme in (global_scheme, monitor_scheme):
            self.assertEqual(json.loads(scheme.read_text())["variant"], "tonalspot")
        self.assertEqual(before_paths, {path: path.read_bytes() for path in before_paths})
        old_schemes = {path: path.read_bytes() for path in (global_scheme, monitor_scheme)}
        (state / "wallpaper/monitors/hdmi-a-1.txt").write_text(str(self.home / "missing.png"))
        result = self.run_zesti("wallpaper", "refresh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not refresh", result.stderr)
        self.assertEqual(old_schemes, {path: path.read_bytes() for path in old_schemes})

    def test_print_smart_config_and_explicit_variant(self):
        self.set_theme_config(True)
        gray = self.wall / "still.png"
        Image.new("RGB", (16, 16), (128, 128, 128)).save(gray)
        for flags, variant in [((), "neutral"), (("--variant", "monochrome"), "monochrome")]:
            result = self.run_zesti("wallpaper", "print", str(gray), "--mode", "dark", *flags)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(json.loads(result.stdout)["metadata"]["variant"], variant)

    def test_saved_palette_has_shell_colours_and_both_modes(self):
        config = self.home / ".config/zestify/config.json"
        settings = json.loads(config.read_text())
        settings["theme"] = {"mode": "light", "apply": False}
        config.write_text(json.dumps(settings))
        result = self.run_zesti("wallpaper", "set", str(self.wall / "still.png"), "--all")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        scheme = json.loads((self.home / ".local/state/zestify/scheme.json").read_text())
        self.assertEqual(scheme["mode"], "light")
        self.assertEqual(scheme["colours"], scheme["palettes"]["light"])
        self.assertNotEqual(scheme["palettes"]["dark"]["surface"], scheme["colours"]["surface"])
        self.assertIn("primary", scheme["colours"])
        self.assertIn("onSurface", scheme["colours"])
        self.assertFalse((self.home / ".local/state/zestify/hyprland.rendered").exists())


if __name__ == "__main__":
    unittest.main()
