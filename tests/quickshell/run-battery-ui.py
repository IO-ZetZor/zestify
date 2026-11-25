#!/usr/bin/env python3
"""Run battery UI tests with Quickshell's embedded UPower plugin."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, default=Path("/tmp/zestify-battery-preview.png"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="zestify-battery-ui-") as scratch:
        stage = Path(scratch)
        shutil.copytree(repo / "shell", stage / "shell")
        source = (repo / "tests/quickshell/battery-ui.qml").read_text()
        (stage / "shell/shell.qml").write_text(source.replace("../../shell/", ""))
        runtime = stage / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
                   BATTERY_UI_PREVIEW=str(args.preview.resolve()),
                   QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl")
        env.pop("WAYLAND_DISPLAY", None)
        result = subprocess.run(["dbus-run-session", "qs", "-p", str(stage / "shell"), "--no-color"],
                                env=env, capture_output=True, text=True, timeout=20)
        log = result.stdout + result.stderr
        print(log, end="")
        return 0 if result.returncode == 0 and "BATTERY UI PASS:" in log and "BATTERY UI FAIL:" not in log else 1


if __name__ == "__main__":
    raise SystemExit(main())
