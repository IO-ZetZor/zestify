"""Unit tests for zesti.wallpaper — Zesti-owned wallpaper state (no Caelestia).

Tests inject a fake palette generator, scheme saver, theme applier, and process
runner so no real desktop tool or the live desktop is touched.
"""

import json
import os
import random
import tempfile
import unittest
from pathlib import Path

from zesti.paths import Paths
from zesti.wallpaper import (
    WallpaperError,
    WallpaperServices,
    WallpaperTarget,
    effective_wallpaper,
    extract_palette_source,
    list_wallpapers,
    make_thumbnail,
    monitor_slug,
    set_wallpaper,
)


def fake_paths(env_overrides=None):
    env = {
        "XDG_STATE_HOME": "/tmp/zt/state",
        "XDG_CACHE_HOME": "/tmp/zt/cache",
        "XDG_CONFIG_HOME": "/tmp/zt/config",
    }
    if env_overrides:
        env.update(env_overrides)
    return Paths.from_env(env)


class MonitorSlugTest(unittest.TestCase):
    def test_slug_is_safe_filename(self):
        self.assertEqual(monitor_slug("eDP-1"), "edp-1")
        self.assertEqual(monitor_slug("HDMI-A-1"), "hdmi-a-1")

    def test_slug_blocks_path_escape(self):
        slug = monitor_slug("../../../etc/passwd")
        self.assertNotIn("/", slug)
        self.assertNotIn("\\", slug)
        self.assertFalse(slug.startswith("."))
        self.assertNotEqual(slug, "")

    def test_slug_dotdot_is_not_empty(self):
        self.assertEqual(monitor_slug(".."), "_")

    def test_slug_collapses_repeated_hyphens(self):
        self.assertEqual(monitor_slug("DP--1"), "dp-1")
        self.assertEqual(monitor_slug("eDP-1"), "edp-1")


class ListWallpapersTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_list_marks_videos_and_images(self):
        (self.dir / "still.png").write_bytes(b"x")
        (self.dir / "clip.mp4").write_bytes(b"x")
        (self.dir / "notes.txt").write_bytes(b"x")  # ignored
        items = list_wallpapers(self.dir)
        by_name = {it["name"]: it for it in items}
        self.assertEqual(set(by_name), {"still.png", "clip.mp4"})
        self.assertFalse(by_name["still.png"]["isVideo"])
        self.assertTrue(by_name["clip.mp4"]["isVideo"])
        self.assertIn("path", by_name["still.png"])
        self.assertIn("thumb", by_name["still.png"])

    def test_list_empty_dir(self):
        self.assertEqual(list_wallpapers(self.dir), [])


class EffectiveWallpaperTest(unittest.TestCase):
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

    def test_effective_wallpaper_global(self):
        paths = self.paths
        paths.wallpaper_dir.mkdir(parents=True)
        (paths.wallpaper_dir / "path.txt").write_text("/global/wall.png")
        self.assertEqual(effective_wallpaper(paths, None), Path("/global/wall.png"))

    def test_effective_wallpaper_monitor_override(self):
        paths = self.paths
        paths.monitor_dir.mkdir(parents=True)
        (paths.monitor_dir / "hdmi-a-1.txt").write_text("/mon/wall.png")
        (paths.wallpaper_dir / "path.txt").write_text("/global/wall.png")
        self.assertEqual(effective_wallpaper(paths, "HDMI-A-1"), Path("/mon/wall.png"))

    def test_effective_wallpaper_missing_returns_none(self):
        paths = self.paths
        self.assertIsNone(effective_wallpaper(paths, None))


class SetWallpaperTest(unittest.TestCase):
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
        self.paths.scheme_file.parent.mkdir(parents=True, exist_ok=True)
        self.image = self.home / "wall.png"
        self.image.write_bytes(b"png")
        self.video = self.home / "clip.mp4"
        self.video.write_bytes(b"mp4")

    def tearDown(self):
        self.temp.cleanup()

    def services(self, palette=None, run=None, rng=None):
        calls = {"palette": [], "scheme": [], "theme": []}

        def gen(source, p, r):
            calls["palette"].append(str(source))
            return palette or {"mode": "dark", "colours": {"primary": "112233"}}

        def save(p, s):
            calls["scheme"].append(s)

        def theme(scheme):
            calls["theme"].append(scheme)
            return []

        return WallpaperServices(
            generate_palette=gen,
            save_scheme=save,
            theme_applier=theme,
            run=run or (lambda *a, **k: 0),
            rng=rng or random,
        ), calls

    def test_global_set_writes_zestify_state(self):
        services, calls = self.services()
        result = set_wallpaper(self.image, WallpaperTarget("global"), self.paths, services)
        self.assertTrue(result["ok"], result)
        self.assertEqual(
            (self.paths.wallpaper_dir / "path.txt").read_text().strip(), str(self.image)
        )
        self.assertTrue((self.paths.wallpaper_dir / "current").exists())
        self.assertTrue((self.paths.wallpaper_dir / "thumbnail.jpg").exists())
        self.assertEqual(len(calls["scheme"]), 1)

    def test_secondary_set_writes_only_monitor(self):
        services, _ = self.services()
        result = set_wallpaper(
            self.image, WallpaperTarget("monitor", "HDMI-A-1"), self.paths, services
        )
        self.assertTrue(result["ok"], result)
        self.assertEqual(
            (self.paths.monitor_dir / "hdmi-a-1.txt").read_text().strip(), str(self.image)
        )
        # global path must not be created/changed
        self.assertFalse((self.paths.wallpaper_dir / "path.txt").exists())

    def test_all_truncates_overrides_without_unlink(self):
        paths = self.paths
        paths.monitor_dir.mkdir(parents=True)
        (paths.monitor_dir / "hdmi-a-1.txt").write_text("/old/video.mp4")
        services, _ = self.services()
        result = set_wallpaper(self.image, WallpaperTarget("all"), paths, services)
        self.assertTrue(result["ok"], result)
        self.assertTrue((paths.monitor_dir / "hdmi-a-1.txt").exists())
        self.assertEqual((paths.monitor_dir / "hdmi-a-1.txt").read_text().strip(), "")

    def test_random_avoids_active_wallpaper(self):
        paths = self.paths
        paths.wallpaper_dir.mkdir(parents=True)
        (paths.wallpaper_dir / "path.txt").write_text(str(self.image))
        wall_dir = self.home / "pics"
        wall_dir.mkdir()
        (wall_dir / "still.png").write_bytes(b"png")
        (wall_dir / "other.png").write_bytes(b"png")
        services, _ = self.services(rng=random.Random(1))
        result = set_wallpaper(wall_dir, WallpaperTarget("random"), paths, services)
        self.assertTrue(result["ok"], result)
        chosen = Path(result["path"])
        self.assertNotEqual(chosen, self.image)
        self.assertIn(chosen, [wall_dir / "still.png", wall_dir / "other.png"])

    def test_missing_file_returns_error_and_leaves_state_untouched(self):
        services, calls = self.services()
        missing = self.home / "missing.png"
        before_scheme = self.paths.scheme_file
        before_scheme.write_text('{"primary": "112233"}')
        result = set_wallpaper(missing, WallpaperTarget("global"), self.paths, services)
        self.assertFalse(result["ok"])
        self.assertIn("error", result)
        self.assertEqual(before_scheme.read_text(), '{"primary": "112233"}')
        self.assertEqual(calls["scheme"], [])

    def test_palette_failure_leaves_state_untouched(self):
        calls = {"scheme": []}

        def failing_palette(source, p, r):
            raise WallpaperError("palette failed")

        def save(p, s):
            calls["scheme"].append(s)

        services = WallpaperServices(
            generate_palette=failing_palette,
            save_scheme=save,
            theme_applier=lambda scheme: [],
            run=lambda *a, **k: 0,
            rng=random,
        )
        before_scheme = self.paths.scheme_file
        before_scheme.write_text('{"primary": "112233"}')
        result = set_wallpaper(self.image, WallpaperTarget("global"), self.paths, services)
        self.assertFalse(result["ok"])
        self.assertEqual(before_scheme.read_text(), '{"primary": "112233"}')
        self.assertEqual(calls["scheme"], [])


class ExtractPaletteSourceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.paths = fake_paths()
        self.image = self.root / "wall.png"
        self.image.write_bytes(b"png")
        self.video = self.root / "clip.mp4"
        self.video.write_bytes(b"mp4")

    def tearDown(self):
        self.temp.cleanup()

    def test_image_returns_path_unchanged(self):
        self.assertEqual(
            extract_palette_source(self.image, self.paths, lambda *a: 0), self.image
        )

    def test_video_extracts_frame_via_run(self):
        calls = []

        def run(cmd, **kwargs):
            calls.append(cmd)
            out = Path(cmd[-1])
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(b"jpg")
            return 0

        result = extract_palette_source(self.video, self.paths, run)
        self.assertTrue(result.exists() and result.stat().st_size > 0)
        self.assertTrue(any("ffmpeg" in str(c[0]) for c in calls))

    def test_video_frame_failure_raises(self):
        def run(cmd, **kwargs):
            return 1  # ffmpeg failed, no frame

        with self.assertRaises(WallpaperError):
            extract_palette_source(self.video, self.paths, run)


class MakeThumbnailTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.paths = fake_paths()
        self.image = self.root / "wall.png"
        self.image.write_bytes(b"png")
        self.video = self.root / "clip.mp4"
        self.video.write_bytes(b"mp4")

    def tearDown(self):
        self.temp.cleanup()

    def test_image_returns_resolved_path(self):
        self.assertEqual(
            make_thumbnail(self.image, self.paths, lambda *a: 0), self.image.resolve()
        )

    def test_video_ensures_cached_frame_and_returns_source(self):
        calls = []

        def run(cmd, **kwargs):
            calls.append(cmd)
            out = Path(cmd[-1])
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(b"jpg")
            return 0

        result = make_thumbnail(self.video, self.paths, run)
        self.assertTrue(any("ffmpeg" in str(c[0]) for c in calls))
        self.assertEqual(result, self.video.resolve())


if __name__ == "__main__":
    unittest.main()
