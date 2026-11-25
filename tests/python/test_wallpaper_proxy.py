import json
import hashlib
import importlib.util
import io
import os
import shutil
import subprocess
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path
from contextlib import redirect_stdout
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
CLI = REPO / "bin/zestify"
spec = importlib.util.spec_from_file_location("wallpaper_proxy", REPO / "scripts/wallpaper-proxy.py")
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


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


class ProxyMetadataTest(unittest.TestCase):
    def test_invalid_average_rate_falls_back_to_valid_reported_rate(self):
        for average in ["0/0", "invalid", "NaN", "Infinity"]:
            result = subprocess.CompletedProcess([], 0, json.dumps({"streams": [{
                "avg_frame_rate": average, "r_frame_rate": "24000/1001"}]}))
            with self.subTest(average=average), patch.object(proxy.subprocess, "run", return_value=result):
                self.assertAlmostEqual(proxy.probe_fps(Path("video.mp4")), 24000 / 1001)

    def test_cached_proxy_avoids_subprocess_and_source_changes_invalidate_probe(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.mp4"
            source.write_bytes(b"source")
            with patch.object(proxy, "cache_root", return_value=root / "cache"):
                with patch.object(proxy, "probe_fps", return_value=24) as probe:
                    self.assertEqual(proxy.cached_fps(source), 24)
                    self.assertEqual(proxy.cached_fps(source), 24)
                    probe.assert_called_once()
                key = proxy.key_for(source, 320, 180, "h264", 20, 24)
                target = root / "cache" / key / "320x180.mp4"
                target.parent.mkdir(parents=True)
                target.write_bytes(b"complete cached proxy")
                with patch.object(proxy.subprocess, "run", side_effect=AssertionError("cache hit launched a process")), redirect_stdout(io.StringIO()) as out:
                    self.assertEqual(proxy.ensure(source, 320, 180), 0)
                    self.assertTrue(json.loads(out.getvalue())["cached"])
                source.write_bytes(b"changed source contents")
                with patch.object(proxy, "probe_fps", return_value=12) as probe:
                    self.assertEqual(proxy.cached_fps(source), 12)
                    probe.assert_called_once()


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

    def test_ensure_honours_codec_and_crf(self):
        result = self.run_cli(
            "proxy", "ensure", "--source", str(self.source),
            "--width", "320", "--height", "180",
            "--codec", "h265", "--crf", "28",
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        codec = subprocess.run([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=codec_name", "-of", "json", payload["path"],
        ], text=True, capture_output=True, check=True)
        self.assertEqual(json.loads(codec.stdout)["streams"][0]["codec_name"], "hevc")

    def test_proxy_fps_defaults_to_24(self):
        payload = self.ensure(320, 180, source=self.fast_source)
        self.assertEqual(ffprobe_fps(Path(payload["path"])), 24)

    def test_maximum_fps_changes_the_proxy_and_is_cached(self):
        paths = []
        for fps in (15, 30, 15):
            result = self.run_cli("proxy", "ensure", "--source", str(self.fast_source),
                "--width", "320", "--height", "180", "--max-fps", str(fps))
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            payload = json.loads(result.stdout)
            paths.append(payload["path"])
            self.assertEqual(ffprobe_fps(Path(payload["path"])), fps)
            self.assertEqual(payload["cached"], len(paths) == 3)
        self.assertNotEqual(paths[0], paths[1])
        self.assertEqual(paths[0], paths[2])

    def test_invalid_maximum_fps_creates_no_proxy(self):
        for fps in (0, -1, 61):
            result = self.run_cli("proxy", "ensure", "--source", str(self.fast_source),
                "--width", "320", "--height", "180", "--max-fps", str(fps))
            self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
            self.assertIn("maximum FPS", json.loads(result.stdout)["error"])
        self.assertFalse(list(self.cache.rglob("*.mp4")))

    def test_proxy_preserves_lower_fps(self):
        payload = self.ensure(320, 180)
        self.assertEqual(ffprobe_fps(Path(payload["path"])), 10)

    def test_h264_proxy_converts_10_bit_and_avoids_the_old_format_cache(self):
        source = self.root / "high-10.mp4"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
            "testsrc=size=64x64:rate=10", "-t", "0.5", "-c:v", "libx264",
            "-pix_fmt", "yuv420p10le", str(source)], check=True, capture_output=True)
        # Populate the legacy cache with valid High 10 video. The new format
        # contract must select a new key instead of accepting that old proxy.
        stamp = "|".join([str(source.resolve()), str(source.stat().st_size),
            str(source.stat().st_mtime_ns), "320", "180", "h264", "20", "10"])
        key = hashlib.sha256(stamp.encode("utf-8")).hexdigest()
        old = self.cache / "zestify/wallpapers" / key / "320x180.mp4"
        old.parent.mkdir(parents=True)
        shutil.copy2(source, old)
        payload = self.ensure(320, 180, source=source)
        self.assertFalse(payload["cached"])
        self.assertNotEqual(Path(payload["path"]), old)
        result = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=pix_fmt,profile", "-of", "json", payload["path"]],
            text=True, capture_output=True, check=True)
        stream = json.loads(result.stdout)["streams"][0]
        self.assertEqual(stream["pix_fmt"], "yuv420p")
        self.assertNotIn("10", stream["profile"])

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
