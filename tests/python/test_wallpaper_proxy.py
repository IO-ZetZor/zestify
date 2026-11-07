import json
import os
import shutil
import subprocess
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CLI = REPO / "bin/zestify"


def ffprobe_size(path):
    out = subprocess.run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "json", str(path),
    ], text=True, capture_output=True, check=True)
    stream = json.loads(out.stdout)["streams"][0]
    return stream["width"], stream["height"]


def ffprobe_fps(path):
    out = subprocess.run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=avg_frame_rate", "-of", "json", str(path),
    ], text=True, capture_output=True, check=True)
    stream = json.loads(out.stdout)["streams"][0]
    return Fraction(stream["avg_frame_rate"])


class WallpaperProxyTest(unittest.TestCase):
    def setUp(self):
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            self.skipTest("ffmpeg/ffprobe unavailable")
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.cache = self.home / ".cache"
        self.source = self.root / "source.mp4"
        subprocess.run([
            "ffmpeg", "-y", "-v", "error", "-f", "lavfi",
            "-i", "testsrc=size=64x64:rate=10", "-t", "1",
            "-pix_fmt", "yuv420p", str(self.source),
        ], check=True)
        self.fast_source = self.root / "fast.mp4"
        subprocess.run([
            "ffmpeg", "-y", "-v", "error", "-f", "lavfi",
            "-i", "testsrc=size=64x64:rate=60", "-t", "1",
            "-pix_fmt", "yuv420p", str(self.fast_source),
        ], check=True)
        self.env = dict(os.environ)
        self.env.update({
            "HOME": str(self.home),
            "XDG_CACHE_HOME": str(self.cache),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
        })

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        return subprocess.run([str(CLI), *args], env=self.env, text=True, capture_output=True)

    def ensure(self, width, height, source=None):
        result = self.run_cli("proxy", "ensure", "--source", str(source or self.source), "--width", str(width), "--height", str(height))
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        return json.loads(result.stdout)

    def test_ensure_creates_monitor_sized_h264(self):
        payload = self.ensure(320, 180)
        path = Path(payload["path"])
        self.assertTrue(path.exists())
        self.assertEqual(ffprobe_size(path), (320, 180))
        self.assertFalse(payload["cached"])

    def test_second_ensure_uses_cache(self):
        first = self.ensure(320, 180)
        second = self.ensure(320, 180)
        self.assertTrue(second["cached"])
        self.assertEqual(first["path"], second["path"])

    def test_key_changes_with_target_size(self):
        first = self.ensure(320, 180)
        second = self.ensure(160, 90)
        self.assertNotEqual(first["path"], second["path"])

    def test_proxy_fps_capped_at_30(self):
        payload = self.ensure(320, 180, source=self.fast_source)
        self.assertLessEqual(ffprobe_fps(Path(payload["path"])), 30)

    def test_proxy_preserves_lower_fps(self):
        payload = self.ensure(320, 180)
        self.assertEqual(ffprobe_fps(Path(payload["path"])), 10)

    def test_missing_source_fails_without_temp(self):
        result = self.run_cli("proxy", "ensure", "--source", str(self.root / "missing.mp4"), "--width", "320", "--height", "180")
        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        self.assertFalse(list((self.cache / "zestify/wallpapers").rglob(".tmp-*")) if (self.cache / "zestify/wallpapers").exists() else [])

    def test_prune_removes_unlisted_keys(self):
        first = self.ensure(320, 180)
        second = self.ensure(160, 90)
        keep = Path(first["path"]).parent.name
        result = self.run_cli("cache", "prune", "--keep", keep)
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertTrue(Path(first["path"]).exists())
        self.assertFalse(Path(second["path"]).exists())


if __name__ == "__main__":
    unittest.main()
