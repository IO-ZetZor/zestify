"""Exercise the real multimedia player without a live desktop or audio stream."""

import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest


REPO = Path(__file__).resolve().parents[2]


class VideoWallpaperTest(unittest.TestCase):
    def test_decoder_pauses_after_first_frame_and_resumes_on_request(self):
        self.check_playback(delayed=False)

    def test_slow_loading_does_not_pause_before_the_first_frame(self):
        self.check_playback(delayed=True)

    def check_playback(self, delayed):
        with tempfile.TemporaryDirectory(prefix="zestify-video-wallpaper-") as directory:
            root = Path(directory)
            source = root / "video sample.mp4"
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                "testsrc=size=160x90:rate=30", "-t", "3", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", str(source)],
                check=True, capture_output=True, timeout=10)
            server = None
            thread = None
            url = source.as_uri()
            if delayed:
                contents = source.read_bytes()
                class SlowVideo(BaseHTTPRequestHandler):
                    def do_GET(self):
                        time.sleep(2)
                        self.send_response(200)
                        self.send_header("Content-Type", "video/mp4")
                        self.send_header("Content-Length", str(len(contents)))
                        self.end_headers()
                        self.wfile.write(contents)

                    def log_message(self, *args):
                        pass

                server = ThreadingHTTPServer(("127.0.0.1", 0), SlowVideo)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                url = "http://127.0.0.1:" + str(server.server_port) + "/video.mp4"
            (root / "shell").symlink_to(REPO / "shell", target_is_directory=True)
            harness = root / "video.qml"
            harness.write_text((REPO / "tests/quickshell/video-wallpaper.qml").read_text()
                .replace("../../shell/", "shell/").replace("__VIDEO_URL__", url))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
            env.pop("WAYLAND_DISPLAY", None)
            try:
                result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(harness)],
                    env=env, capture_output=True, text=True, timeout=15)
            finally:
                if server is not None:
                    server.shutdown()
                    server.server_close()
                    thread.join(timeout=2)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("Totals: 3 passed, 0 failed", output)
            for error in ("TypeError", "ReferenceError", "Binding loop"):
                self.assertNotIn(error, output)


if __name__ == "__main__":
    unittest.main()
