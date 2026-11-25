"""Native client regressions and an offscreen preview; never authenticates."""

from pathlib import Path
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest


class GreeterTest(unittest.TestCase):
    @staticmethod
    def preview_environment(directory):
        temporary = Path(directory)
        runtime = temporary / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        env = dict(os.environ)
        env.pop("WAYLAND_DISPLAY", None)
        env.update({
            "HOME": directory,
            "XDG_CONFIG_HOME": str(temporary / "config"),
            "XDG_CACHE_HOME": str(temporary / "cache"),
            "XDG_RUNTIME_DIR": str(runtime),
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QUICK_BACKEND": "software",
            "QT_QUICK_CONTROLS_STYLE": "Basic",
        })
        return env

    def run_theme_test(self, directory, *media):
        env = self.preview_environment(directory)
        if shutil.which("fc-match"):
            font = subprocess.run(["fc-match", "-f", "%{file}", "monospace"], capture_output=True, text=True, timeout=5)
            if font.returncode == 0 and Path(font.stdout).is_file():
                env["ZESTIFY_TEST_FONT_FILE"] = font.stdout
        result = subprocess.run(
            [str(Path(GREETER).with_name("test-greeter-theme")), *map(str, media)],
            env=env, capture_output=True, text=True, timeout=45,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("GREETER THEME PASS:", output)
        for error in ("TypeError", "ReferenceError", "Binding loop", "Cannot assign", "failed to load component"):
            self.assertNotIn(error, output)

    def test_theme_editor_reload_layout_and_authentication_ui(self):
        with tempfile.TemporaryDirectory(prefix="zestify-theme-") as directory:
            self.run_theme_test(directory)

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg required for live wallpaper fixtures")
    def test_live_wallpaper_decoding_loop_pause_and_fallback(self):
        with tempfile.TemporaryDirectory(prefix="zestify-theme-media-") as directory:
            video = Path(directory) / "video #1.mp4"
            animation = Path(directory) / "animation.gif"
            for path, codec in ((video, ["-c:v", "mpeg4", "-q:v", "3"]), (animation, [])):
                result = subprocess.run([
                    "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=10",
                    "-t", "0.6", *codec, str(path),
                ], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.run_theme_test(directory, video, animation)

    def test_check_theme_is_headless_and_rejects_invalid_fields(self):
        with tempfile.TemporaryDirectory(prefix="zestify-theme-check-") as directory:
            path = Path(directory) / "theme.json"
            env = dict(os.environ)
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            for content, code in (({"background": {"type": "video", "source": "movie.mp4"}}, 0),
                                  ({"layout": {"scale": -1}}, 1), ({"icons": {"user": {"source": "https://example.org/icon"}}}, 1)):
                path.write_text(json.dumps(content))
                result = subprocess.run([GREETER, "--check-theme", str(path)], env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)

    def test_client_protocol_and_response_bounds(self):
        result = subprocess.run([CLIENT], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GREETER CLIENT PASS:", result.stdout)

    def test_offscreen_preview_renders(self):
        with tempfile.TemporaryDirectory(prefix="zestify-greeter-preview-") as directory:
            temporary = Path(directory)
            image = temporary / "preview.png"
            env = self.preview_environment(directory)
            result = subprocess.run(
                [GREETER, "--preview", "--screenshot", str(image)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            contents = image.read_bytes()
            self.assertEqual(contents[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack(">II", contents[16:24]), (1280, 800))
            self.assertGreater(len(contents), 10000)
            for error in ("TypeError", "ReferenceError", "Binding loop", "failed to load component"):
                self.assertNotIn(error, output)

    def test_screenshot_requires_preview(self):
        result = subprocess.run(
            [GREETER, "--screenshot", "/tmp/zestify-should-not-be-created.png"],
            env=dict(os.environ, QT_QPA_PLATFORM="offscreen"),
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: test_greeter.py GREETER [CLIENT_TEST]")
    GREETER = str(Path(sys.argv[1]).resolve())
    CLIENT = str(Path(sys.argv[2]).resolve()) if len(sys.argv) == 3 else str(Path(GREETER).with_name("test-greeter-client"))
    unittest.main(argv=[sys.argv[0]], verbosity=2)
