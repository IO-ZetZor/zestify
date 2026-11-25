"""Render wallpaper contours/reveals and exercise static/live media lifetimes."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[2]


class WallpaperTransitionTest(unittest.TestCase):
    def test_native_contours_and_media_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="zestify-wallpaper-transition-") as directory:
            root = Path(directory)
            assets = {}
            for name, color in (("RED", "red"), ("BLUE", "blue")):
                path = root / f"{name.lower()}.png"
                Image.new("RGB", (320, 180), color).save(path)
                assets[name] = str(path)
            subject = Image.new("RGB", (320, 180), "#17452d")
            ImageDraw.Draw(subject).ellipse((110, 50, 210, 140), fill="white")
            subject.save(root / "subject.png")
            assets["SUBJECT"] = str(root / "subject.png")
            # These fixtures are generated from the upstream map mathematics:
            # a known foreground circle and seed12 colonies. Map-generation
            # correctness is tested separately without requiring a model download.
            for name in ("SUBJECT_FIELD", "SUBJECT_LINE", "COLONY_FIELD", "COLONY_LINE"):
                assets[name] = str(REPO / "tests/fixtures/wallfx" / (name.lower().replace("_", "-") + ".png"))
            for name, color in (("GREEN_VIDEO", "lime"), ("BLUE_VIDEO", "blue")):
                path = root / f"{name.lower()}.mp4"
                subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                    f"color=c={color}:s=320x180:r=30", "-t", "3", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", str(path)], check=True, capture_output=True, timeout=10)
                assets[name] = str(path)
            assets["MISSING_VIDEO"] = str(root / "missing.mp4")
            contents = Path(assets["GREEN_VIDEO"]).read_bytes()

            class SlowVideo(BaseHTTPRequestHandler):
                def do_GET(self):
                    time.sleep(1)
                    self.send_response(200)
                    self.send_header("Content-Type", "video/mp4")
                    self.send_header("Content-Length", str(len(contents)))
                    self.end_headers()
                    try:
                        self.wfile.write(contents)
                    except (BrokenPipeError, ConnectionResetError):
                        pass

                def log_message(self, *args):
                    pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), SlowVideo)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            assets["SLOW_VIDEO"] = f"http://127.0.0.1:{server.server_port}/slow.mp4"
            previews = Path(os.environ.get("WALLPAPER_EFFECT_PREVIEW", str(root / "previews")))
            previews.mkdir(exist_ok=True)
            assets["OUTPUT_DIR"] = str(previews)
            (root / "shell").symlink_to(REPO / "shell", target_is_directory=True)
            source = (REPO / "tests/quickshell/wallpaper-transition.qml").read_text().replace("../../shell/", "shell/")
            for name, value in assets.items():
                source = source.replace(f"__{name}__", value)
            harness = root / "wallpaper-transition.qml"
            harness.write_text(source)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl")
            env.pop("WAYLAND_DISPLAY", None)
            try:
                result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(harness)],
                    env=env, capture_output=True, text=True, timeout=40)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("0 failed", output)
            for error in ("TypeError", "ReferenceError", "Binding loop", "Cannot assign", "Unable to assign", "Failed to deserialize"):
                self.assertNotIn(error, output)
            for scenario in ("static-static", "static-live", "live-static", "live-live", "contour"):
                self.assertTrue((previews / f"{scenario}.png").is_file(), output)


if __name__ == "__main__":
    unittest.main()
