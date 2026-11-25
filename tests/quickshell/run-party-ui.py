#!/usr/bin/env python3
"""Render party-mode previews and exercise the overlay on an isolated bus."""
import argparse
import os
from pathlib import Path
import resource
import shutil
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/zestify-party-previews"))
    parser.add_argument("--audio-trace", type=Path, help="spectrum.json from run-party-audio.py")
    parser.add_argument("--profile-formation", action="store_true", help="measure entry frames without screenshot overhead")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="zestify-party-ui-") as scratch:
        stage = Path(scratch)
        shutil.copytree(repo / "shell", stage / "shell")
        source = (repo / "tests/quickshell/party-ui.qml").read_text()
        (stage / "shell/shell.qml").write_text(source.replace("../../shell/", ""))
        config = stage / "config/zestify"
        config.mkdir(parents=True)
        shutil.copyfile(repo / "config/default.json", config / "config.json")
        cover = stage / "cover.svg"
        cover.write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">
          <defs>
            <linearGradient id="sky" x2="0" y2="1">
              <stop stop-color="#f0b56e"/><stop offset="1" stop-color="#915563"/>
            </linearGradient>
          </defs>
          <rect width="1024" height="1024" fill="url(#sky)"/>
          <circle cx="670" cy="320" r="148" fill="#ffe1a1"/>
          <path d="M0 720Q260 440 530 730T1024 660V1024H0Z" fill="#393d58"/>
          <path d="M0 840Q300 630 650 870T1024 790V1024H0Z" fill="#202735"/>
          <text x="72" y="180" fill="#fff" font-family="sans-serif" font-size="44">AFTER HOURS</text>
        </svg>''')
        env = dict(os.environ,
                   XDG_CONFIG_HOME=str(stage / "config"),
                   PARTY_UI_OUTPUT=str(args.output.resolve()),
                   PARTY_UI_COVER=cover.as_uri(),
                   PARTY_UI_AUDIO=str(args.audio_trace.resolve()) if args.audio_trace else "",
                   PARTY_UI_PROFILE="1" if args.profile_formation else "",
                   QT_QPA_PLATFORM="offscreen",
                   QT_QUICK_BACKEND="rhi",
                   QSG_RHI_BACKEND="opengl")
        env.pop("WAYLAND_DISPLAY", None)
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        result = subprocess.run(
            ["dbus-run-session", "qs", "-p", str(stage / "shell/shell.qml"), "--no-color"],
            env=env, capture_output=True, text=True, timeout=60 if args.audio_trace else 35)
        log = result.stdout + result.stderr
        print(log, end="")
        if args.profile_formation:
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            print("PARTY PROFILE CPU seconds:", round(after.ru_utime + after.ru_stime
                - before.ru_utime - before.ru_stime, 3))
        passed = "PARTY UI PASS:" in log and all(error not in log for error in
            ["PARTY UI FAIL:", "TypeError", "ReferenceError", "Binding loop"])
        return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
