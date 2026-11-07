"""CLI-level tests for zesti wallpaper commands.

Drives the canonical ``zesti`` executable through a temporary XDG home so no
real desktop or Caelestia is involved.
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
        result = self.run_zesti("wallpaper", "set", str(image), "--monitor", "eDP-1")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"], payload)
        state = self.home / ".local/state" / "zestify" / "wallpaper" / "monitors" / "edp-1.txt"
        self.assertEqual(state.read_text().strip(), str(image))
        result = self.run_zesti("wallpaper", "get", "--monitor", "eDP-1")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(result.stdout.strip(), str(image))

    def test_invalid_file_returns_json_error(self):
        result = self.run_zesti("wallpaper", "set", str(self.home / "missing.png"))
        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        self.assertIn("error", payload)


if __name__ == "__main__":
    unittest.main()
