"""Check rendered static/live crossfades, fast selection, and decoder cleanup."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

from PIL import Image

REPO = Path(__file__).resolve().parents[2]


class WallpaperPreviewTest(unittest.TestCase):
    def test_native_crossfades_and_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="zestify-wallpaper-preview-") as directory:
            root = Path(directory)
            assets = {}
            for name, color in (("RED", "red"), ("BLUE", "blue")):
                path = root / f"{name.lower()}.png"
                Image.new("RGB", (160, 90), color).save(path)
                assets[name] = str(path)
            for name, color in (("GREEN_VIDEO", "lime"), ("BLUE_VIDEO", "blue")):
                path = root / f"{name.lower()}.mp4"
                subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                    f"color=c={color}:s=160x90:r=30", "-t", "3", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", str(path)], check=True, capture_output=True, timeout=10)
                assets[name] = str(path)
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
                        pass  # Cancellation deliberately closes an in-flight request.

                def log_message(self, *args):
                    pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), SlowVideo)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            assets["SLOW_VIDEO"] = f"http://127.0.0.1:{server.server_port}/slow.mp4"
            assets["MISSING_VIDEO"] = str(root / "missing.mp4")
            previews = Path(os.environ.get("WALLPAPER_TRANSITION_PREVIEW", str(root / "previews")))
            previews.mkdir(exist_ok=True)
            assets["OUTPUT_DIR"] = str(previews)
            (root / "shell").symlink_to(REPO / "shell", target_is_directory=True)
            source = (REPO / "tests/quickshell/wallpaper-preview.qml").read_text().replace("../../shell/", "shell/")
            for name, value in assets.items():
                source = source.replace(f"__{name}__", value)
            harness = root / "wallpaper-preview.qml"
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
            self.assertIn("Totals: 13 passed, 0 failed", output)
            for error in ("TypeError", "ReferenceError", "Binding loop", "Cannot assign", "Unable to assign"):
                self.assertNotIn(error, output)
            for scenario in ("static-static", "static-live", "live-static", "live-live"):
                self.assertTrue((previews / f"{scenario}.png").is_file(), output)


if __name__ == "__main__":
    unittest.main()
