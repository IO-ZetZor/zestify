"""Copy-only migration tests for zesti.

No legacy shell executable is invoked; the palette generator is injected so the
live desktop is never touched and source files are never modified.
"""

import json
import os
import tempfile
import unittest
from pathlib import Path

from zesti.migrate import migrate, MigrationResult
from zesti.paths import Paths


def make_env(temp):
    home = temp / "home"
    home.mkdir()
    return {
        "HOME": str(home),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_CONFIG_HOME": str(home / ".config"),
    }


def make_source(root):
    state = root / "caelestia" / "wallpaper"
    state.mkdir(parents=True)
    imgs = root / "wallpapers"
    imgs.mkdir()
    global_img = imgs / "global.png"
    global_img.write_bytes(b"png")
    primary_img = imgs / "primary.png"
    primary_img.write_bytes(b"png")
    secondary_img = imgs / "secondary.png"
    secondary_img.write_bytes(b"png")
    (state / "path.txt").write_text(str(global_img) + "\n")
    (state / "monitors").mkdir()
    (state / "monitors" / "eDP-1.txt").write_text(str(primary_img) + "\n")
    (state / "monitors" / "HDMI-A-1.txt").write_text(str(secondary_img) + "\n")
    (state / "scheme.json").write_text('{"primary": "112233", "mode": "dark"}\n')
    return state


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = make_env(self.root)
        self.paths = Paths.from_env(self.env)
        self.source = make_source(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def generator(self, calls, scheme=None, fail=False):
        def generate(source_path, paths):
            calls.append(str(source_path))
            if fail:
                raise RuntimeError("palette failed")
            return scheme or {"primary": "generated", "mode": "dark", "metadata": {"mode": "dark"}}
        return generate

    def test_first_run_copies_global_and_monitors(self):
        calls = []
        result = migrate(self.source, None, self.paths, force=True, generate=self.generator(calls))
        self.assertTrue(result.ok, result.errors)
        self.assertTrue(result.copied_global)
        self.assertEqual(result.copied_monitors, {"eDP-1": str(self.paths.monitor_dir / "edp-1.txt"), "HDMI-A-1": str(self.paths.monitor_dir / "hdmi-a-1.txt")})
        self.assertTrue(result.copied_scheme)
        self.assertTrue(result.marker_written)
        self.assertEqual((self.paths.wallpaper_dir / "path.txt").read_text().strip(), str(self.root / "wallpapers" / "global.png"))
        self.assertEqual((self.paths.monitor_dir / "edp-1.txt").read_text().strip(), str(self.root / "wallpapers" / "primary.png"))
        # generation ran and overwrote the copied fallback
        self.assertEqual(json.loads(self.paths.scheme_file.read_text())["primary"], "generated")

    def test_never_changes_source_files(self):
        before = {
            "path": (self.source / "path.txt").read_text(),
            "eDP-1": (self.source / "monitors" / "eDP-1.txt").read_text(),
            "scheme": (self.source / "scheme.json").read_text(),
        }
        migrate(self.source, None, self.paths, force=True, generate=self.generator([]))
        self.assertEqual((self.source / "path.txt").read_text(), before["path"])
        self.assertEqual((self.source / "monitors" / "eDP-1.txt").read_text(), before["eDP-1"])
        self.assertEqual((self.source / "scheme.json").read_text(), before["scheme"])

    def test_regenerates_palette_when_source_wallpaper_exists(self):
        calls = []
        scheme = {"primary": "abcdef", "mode": "dark", "metadata": {"mode": "dark"}}
        result = migrate(self.source, None, self.paths, force=True, generate=self.generator(calls, scheme=scheme))
        self.assertTrue(result.ok, result.errors)
        self.assertTrue(result.regenerated)
        self.assertEqual(calls, [str(self.root / "wallpapers" / "global.png")])
        self.assertEqual(json.loads(self.paths.scheme_file.read_text())["primary"], "abcdef")

    def test_generation_failure_keeps_copied_fallback_and_marks(self):
        calls = []
        result = migrate(self.source, None, self.paths, force=True, generate=self.generator(calls, fail=True))
        self.assertFalse(result.regenerated)
        self.assertTrue(result.marker_written)  # marker written even with errors
        self.assertIn("palette", " ".join(result.errors))
        # copied fallback scheme is still present
        self.assertEqual(json.loads(self.paths.scheme_file.read_text())["primary"], "112233")

    def test_marker_written_last(self):
        migrate(self.source, None, self.paths, force=True, generate=self.generator([]))
        marker = self.paths.state_home / "zestify" / "migration.json"
        self.assertTrue(marker.exists())
        data = json.loads(marker.read_text())
        self.assertEqual(data["schema"], 1)

    def test_failed_migration_can_be_retried_without_force(self):
        failed = migrate(self.source, None, self.paths, generate=self.generator([], fail=True))
        self.assertFalse(failed.ok)
        calls = []
        retried = migrate(self.source, None, self.paths, generate=self.generator(calls))
        self.assertFalse(retried.skipped)
        self.assertTrue(retried.ok, retried.errors)
        self.assertTrue(retried.regenerated)
        self.assertEqual(len(calls), 1)

    def test_rerun_without_force_is_noop(self):
        migrate(self.source, None, self.paths, force=True, generate=self.generator([]))
        calls = []
        result = migrate(self.source, None, self.paths, force=False, generate=self.generator(calls))
        self.assertTrue(result.skipped)
        self.assertEqual(calls, [])

    def test_force_recopies_without_deleting_destination_data(self):
        # add destination-only user data
        self.paths.wallpaper_dir.mkdir(parents=True, exist_ok=True)
        (self.paths.wallpaper_dir / "path.txt").write_text("/user/custom.png\n")
        migrate(self.source, None, self.paths, force=True, generate=self.generator([]))
        # force recopies over the custom global path (source wins)
        self.assertEqual((self.paths.wallpaper_dir / "path.txt").read_text().strip(), str(self.root / "wallpapers" / "global.png"))
        result = migrate(self.source, None, self.paths, force=True, generate=self.generator([]))
        self.assertFalse(result.skipped)


if __name__ == "__main__":
    unittest.main()
