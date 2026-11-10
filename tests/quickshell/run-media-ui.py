#!/usr/bin/env python3
"""Exercise native UI on an isolated bus with a local lyrics API and previews."""
import argparse
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse


class LyricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        title = query.get("track_name", [""])[0]
        if title == "Slow old":
            time.sleep(1)
        self.send_response(404 if title == "Missing" else 200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if title == "Bad JSON":
            body = b"not json"
        else:
            text = "New lyric" if title == "New song" else "Network lyric"
            body = json.dumps({"syncedLyrics": "[00:10.00]" + text, "plainLyrics": text}).encode()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Cancellation deliberately closes the old request.

    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/zestify-media-previews"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="zestify-media-ui-") as scratch:
        stage = Path(scratch)
        shutil.copytree(repo / "shell", stage / "shell")
        source = (repo / "tests/quickshell/media-ui.qml").read_text()
        (stage / "shell/shell.qml").write_text(source.replace("../../shell/", ""))
        config = stage / "config/zestify"
        config.mkdir(parents=True)
        shutil.copyfile(repo / "config/default.json", config / "config.json")
        cover = stage / "cover.svg"
        cover.write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">
          <defs><linearGradient id="sky" x2="0" y2="1"><stop stop-color="#f0b56e"/><stop offset="1" stop-color="#915563"/></linearGradient></defs>
          <rect width="512" height="512" fill="url(#sky)"/>
          <circle cx="335" cy="160" r="74" fill="#ffe1a1"/>
          <path d="M0 360Q130 220 265 365T512 330V512H0Z" fill="#393d58"/>
          <path d="M0 420Q150 315 325 435T512 395V512H0Z" fill="#202735"/>
        </svg>''')
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), LyricsHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = dict(os.environ, XDG_CONFIG_HOME=str(stage / "config"),
                   MEDIA_UI_OUTPUT=str(args.output.resolve()), MEDIA_UI_COVER=cover.as_uri(),
                   MEDIA_UI_ENDPOINT=f"http://127.0.0.1:{server.server_port}/api/get",
                   QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl")
        env.pop("WAYLAND_DISPLAY", None)
        try:
            result = subprocess.run(["dbus-run-session", "qs", "-p", str(stage / "shell"), "--no-color"],
                                    env=env, capture_output=True, text=True, timeout=25)
        finally:
            server.shutdown()
            server.server_close()
        log = result.stdout + result.stderr
        print(log, end="")
        return 0 if result.returncode == 0 and "MEDIA UI PASS:" in log and "MEDIA UI FAIL:" not in log else 1


if __name__ == "__main__":
    raise SystemExit(main())
