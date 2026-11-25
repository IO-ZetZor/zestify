"""Map precision, subject/cache decisions and isolated inference setup."""
from __future__ import annotations

import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

from zesti import wallfx
from zesti.paths import Paths


class MapMathTest(unittest.TestCase):
    def test_arrival_prefers_cheaper_path_and_earliest_duplicate_seed(self):
        # The center cell has a high cost; arrival along the outer row must
        # outrun the direct route through it. Duplicate seeds cannot delay it.
        cost = [1.0] * 9
        cost[4] = 100.0
        arrival = wallfx._arrival(cost, [(0, 0.0), (0, 20.0)], 3, 3)
        self.assertEqual(arrival[0], 0.0)
        self.assertEqual(arrival[2], 2.0)
        self.assertLess(arrival[8], arrival[4])

    def test_colony_map_rank_reveals_uniform_area_and_preserves_16bits(self):
        arrival = wallfx.contagion_map(42, 48, 27)
        repeated = wallfx.contagion_map(42, 48, 27)
        self.assertTrue(np.array_equal(arrival, repeated))
        self.assertEqual(arrival.dtype, np.uint16)
        self.assertEqual((int(arrival.min()), int(arrival.max())), (0, 65535))
        for fraction in (0.1, 0.3, 0.7, 0.9):
            self.assertAlmostEqual(float((arrival <= fraction * 65535).mean()), fraction, delta=0.002)
        encoded = wallfx._rgb16(arrival.astype(np.float64) / 65535.0)
        decoded = encoded[..., 1].astype(np.uint16) * 256 + encoded[..., 2]
        self.assertTrue(np.array_equal(decoded, arrival))
        self.assertFalse(encoded[..., 0].any())

    def test_smooth_map_stays_bounded_and_retains_shape(self):
        values = np.zeros((20, 30))
        values[10:, 15:] = 1
        smooth = wallfx._blur(values, 2.5)
        self.assertEqual(smooth.shape, values.shape)
        self.assertGreater(smooth[10, 15], 0)
        self.assertLess(smooth[10, 15], 1)
        self.assertGreaterEqual(smooth.min(), 0)
        self.assertLessEqual(smooth.max(), 1)


class CacheTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="zestify-wallfx-tests-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.paths = Paths.from_env({"HOME": str(self.root),
            "XDG_DATA_HOME": str(self.root / "data"), "XDG_CACHE_HOME": str(self.root / "cache")})
        self.source = self.root / "source.png"
        Image.new("RGB", (160, 90), "navy").save(self.source)
        # Map generation tests use real Dijkstra mathematics on a smaller grid,
        # keeping cache/concurrency coverage fast without model downloads.
        original = wallfx.contagion_map
        self.generator = patch("zesti.wallfx.contagion_map", side_effect=lambda seed: original(seed, 48, 27))
        self.generator.start()
        self.addCleanup(self.generator.stop)

    def test_missing_runtime_falls_back_without_poisoning_profile_cache(self):
        with patch("zesti.wallfx._cutout", side_effect=ImportError("model missing")):
            result = wallfx.prepare_effect(self.source, self.paths)
        self.assertEqual(result["kind"], "contagio")
        self.assertIn("model missing", result["reason"])
        self.assertIn("model missing", result["error"])
        self.assertFalse((wallfx.cache_dir(self.paths) / "perfil" / (result["key"] + ".json")).exists())
        self.assertTrue(Path(result["field"]).is_file())
        self.assertTrue(wallfx._complete_pair(Path(result["field"]), Path(result["line"])))

    def test_cache_probe_does_not_wait_for_inference_lock(self):
        key = wallfx.source_key(self.source)
        lock_path = wallfx.cache_dir(self.paths) / "perfil" / (key + ".lock")
        lock_path.parent.mkdir(parents=True)
        with lock_path.open("a") as lock, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            wallfx.fcntl.flock(lock, wallfx.fcntl.LOCK_EX)
            future = pool.submit(wallfx.prepare_effect, self.source, self.paths, allow_inference=False)
            try:
                result = future.result(timeout=1)
            finally:
                wallfx.fcntl.flock(lock, wallfx.fcntl.LOCK_UN)
        self.assertEqual(result["kind"], "contagio")
        self.assertTrue(result["pending"])
        self.assertFalse(result["cached"])

    def test_source_timestamp_changes_even_when_size_and_second_are_same(self):
        first = wallfx.source_key(self.source)
        stamp = self.source.stat()
        os.utime(self.source, ns=(stamp.st_atime_ns, stamp.st_mtime_ns + 1))
        second = wallfx.source_key(self.source)
        self.assertNotEqual(first, second)

    def test_cached_negative_is_used_without_inference(self):
        key = wallfx.source_key(self.source)
        metadata = wallfx.cache_dir(self.paths) / "perfil" / (key + ".json")
        metadata.parent.mkdir(parents=True)
        metadata.write_text(json.dumps({"key": key, "ok": False}))
        with patch("zesti.wallfx._cutout") as cutout:
            result = wallfx.prepare_effect(self.source, self.paths)
        cutout.assert_not_called()
        self.assertEqual(result["kind"], "contagio")
        self.assertEqual(result["reason"], "No clear subject")
        self.assertNotIn("error", result)
        self.assertTrue(result["cached"])

    def test_concurrent_pool_publication_produces_matching_immutable_pair(self):
        with patch("zesti.wallfx.secrets.randbelow", return_value=2), \
             concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: wallfx.prepare_effect(
                self.source, self.paths, allow_inference=False), range(4)))
        self.assertEqual(len({item["field"] for item in results}), 1)
        field = Path(results[0]["field"])
        before = field.read_bytes()
        with patch("zesti.wallfx.secrets.randbelow", return_value=2):
            result = wallfx.prepare_effect(self.source, self.paths, allow_inference=False)
        self.assertEqual(field.read_bytes(), before)
        self.assertTrue(wallfx._complete_pair(field, Path(result["line"])))

    def test_corrupt_pool_image_is_repaired_before_reuse(self):
        with patch("zesti.wallfx.secrets.randbelow", return_value=3):
            result = wallfx.prepare_effect(self.source, self.paths, allow_inference=False)
            Path(result["line"]).write_bytes(b"not a PNG")
            repaired = wallfx.prepare_effect(self.source, self.paths, allow_inference=False)
        self.assertTrue(wallfx._complete_pair(Path(repaired["field"]), Path(repaired["line"])))

    def test_map_pair_rejects_wrong_cached_geometry_and_alpha(self):
        first, second = self.root / "field.png", self.root / "line.png"
        Image.new("RGB", (40, 20)).save(first)
        Image.new("RGB", (40, 20)).save(second)
        self.assertTrue(wallfx._complete_pair(first, second, width=40, height=20))
        self.assertFalse(wallfx._complete_pair(first, second, width=80, height=40))
        Image.new("RGBA", (40, 20)).save(second)
        self.assertFalse(wallfx._complete_pair(first, second))

    def test_profile_maps_commit_only_after_both_images_exist(self):
        field = np.zeros((90, 160, 3), np.uint8)
        line = np.zeros_like(field)
        mask = Image.new("L", (160, 90), 0)
        with patch("zesti.wallfx._cutout", return_value=mask), \
             patch("zesti.wallfx.contour_maps", return_value=(field, line, {"ok": True})):
            result = wallfx.prepare_effect(self.source, self.paths)
        self.assertEqual(result["kind"], "perfil")
        self.assertTrue(wallfx._complete_pair(Path(result["field"]), Path(result["line"])))
        with patch("zesti.wallfx._cutout") as cutout:
            cached = wallfx.prepare_effect(self.source, self.paths, allow_inference=False)
        cutout.assert_not_called()
        self.assertEqual(cached["kind"], "perfil")
        self.assertTrue(cached["cached"])

    def test_concurrent_profile_requests_only_infer_once(self):
        field = np.zeros((90, 160, 3), np.uint8)
        mask = Image.new("L", (160, 90), 0)
        with patch("zesti.wallfx._cutout", return_value=mask) as cutout, \
             patch("zesti.wallfx.contour_maps", return_value=(field, field, {"ok": True})), \
             concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: wallfx.prepare_effect(self.source, self.paths), range(4)))
        self.assertEqual(cutout.call_count, 1)
        self.assertEqual(len({item["field"] for item in results}), 1)
        self.assertEqual(sum(not item["cached"] for item in results), 1)

    def test_interrupted_map_publication_does_not_commit_negative(self):
        field = np.zeros((90, 160, 3), np.uint8)
        real_writer = wallfx._write_image
        def fail_line(path, values):
            if str(path).endswith(".line.png") and "perfil" in str(path):
                raise OSError("disk full")
            real_writer(path, values)
        with patch("zesti.wallfx._cutout", return_value=Image.new("L", (160, 90), 0)), \
             patch("zesti.wallfx.contour_maps", return_value=(field, field, {"ok": True})), \
             patch("zesti.wallfx._write_image", side_effect=fail_line):
            result = wallfx.prepare_effect(self.source, self.paths)
        self.assertEqual(result["kind"], "contagio")
        self.assertIn("disk full", result["reason"])
        metadata = wallfx.cache_dir(self.paths) / "perfil" / (result["key"] + ".json")
        self.assertFalse(metadata.exists())


class RuntimeTest(unittest.TestCase):
    def test_setup_explicitly_installs_and_downloads_model_without_stdout(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = Paths.from_env({"HOME": directory, "XDG_DATA_HOME": directory})
            model = wallfx.runtime_dir(paths) / "models/models" / wallfx.MODEL / (wallfx.MODEL + ".onnx")
            model.parent.mkdir(parents=True)
            model.write_bytes(b"downloaded model fixture")
            with patch("zesti.wallfx.shutil.which", return_value="/bin/uv"), \
                 patch("zesti.wallfx.subprocess.run", return_value=subprocess.CompletedProcess(
                     [], 0, json.dumps({"model_file": str(model)}))) as run:
                result = wallfx.setup_runtime(paths)
            self.assertTrue(result["ok"])
            commands = [call.args[0] for call in run.call_args_list]
            self.assertIn("3.12", commands[0])
            self.assertIn("rembg[cpu]>=2.0.60,<3", commands[1])
            self.assertIn("birefnet-general-lite", commands[2][-1])
            for call in run.call_args_list[:2]:
                self.assertIs(call.kwargs["stdout"], __import__("sys").stderr)
            self.assertEqual(run.call_args_list[2].kwargs["stdout"], subprocess.PIPE)
            self.assertEqual(result["model_file"], str(model))
            self.assertTrue((wallfx.runtime_dir(paths) / "ready.json").is_file())

    def test_preparation_never_downloads_missing_or_changed_model(self):
        import types
        with tempfile.TemporaryDirectory() as directory:
            paths = Paths.from_env({"HOME": directory, "XDG_DATA_HOME": directory})
            module = types.SimpleNamespace(new_session=__import__("unittest.mock", fromlist=["Mock"]).Mock(), remove=None)
            with patch.dict(__import__("sys").modules, {"rembg": module}):
                with self.assertRaisesRegex(RuntimeError, "setup"):
                    wallfx._cutout(Image.new("RGB", (10, 10)), paths)
                model = wallfx.runtime_dir(paths) / "models" / (wallfx.MODEL + ".onnx")
                model.parent.mkdir(parents=True)
                model.write_bytes(b"model")
                (wallfx.runtime_dir(paths) / "ready.json").write_text(json.dumps({
                    "ok": True, "model": wallfx.MODEL, "model_size": 123, "model_mtime_ns": 0}))
                with self.assertRaisesRegex(RuntimeError, "changed"):
                    wallfx._cutout(Image.new("RGB", (10, 10)), paths)
                module.new_session.assert_not_called()

    def test_setup_failure_has_no_ready_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = Paths.from_env({"HOME": directory, "XDG_DATA_HOME": directory})
            with patch("zesti.wallfx.shutil.which", return_value="/bin/uv"), \
                 patch("zesti.wallfx.subprocess.run", side_effect=subprocess.CalledProcessError(2, ["uv"])):
                result = wallfx.setup_runtime(paths)
            self.assertFalse(result["ok"])
            self.assertFalse((wallfx.runtime_dir(paths) / "ready.json").exists())


class SubjectMapTest(unittest.TestCase):
    def test_real_opencv_contour_fields_and_mask_decisions(self):
        """Run OpenCV through the isolated runtime; host Python stays clean."""
        paths = Paths.from_env(os.environ)
        python = wallfx.runtime_python(paths)
        if python is None:
            try:
                __import__("cv2")
                python = Path(__import__("sys").executable)
            except ImportError:
                self.skipTest("Install wallpaper-effects runtime to exercise OpenCV subject maps")
        script = '''
import json
import numpy as np
from PIL import Image, ImageDraw
from zesti.wallfx import contour_maps
mask=Image.new("L", (320,180), 0)
ImageDraw.Draw(mask).ellipse((110,40,210,140),fill=255)
field,line,metadata=contour_maps(mask,"0123456789abcdef")
assert metadata["ok"]
assert field.shape==(180,320,3) and line.shape==field.shape
assert field[90,160,2]<128 and field[0,0,2]>128
assert field[90,160,1]>200 and field[0,0,1]==0
assert np.count_nonzero(line[...,0])>100
assert line[0,0,0]==0
assert line.dtype==np.uint8
for value in (0,255,128):
    field,line,metadata=contour_maps(Image.new("L",(320,180),value),"0123456789abcdef")
    assert not metadata["ok"] and field is None and line is None
print("SUBJECT MAP PASS")
'''
        result = subprocess.run([str(python), "-c", script], cwd=Path(__file__).resolve().parents[2],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SUBJECT MAP PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
