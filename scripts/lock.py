#!/usr/bin/env python3
"""Request Zestify's native Wayland lock and wait for compositor confirmation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pwd
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov", ".m4v"}


def cache_dir() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "zestify"


def lock_frame(source: str) -> str:
    path = Path(source).expanduser()
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTENSIONS and path.is_file():
        return str(path.resolve())
    if suffix not in VIDEO_EXTENSIONS or not path.is_file() or not shutil.which("ffmpeg"):
        return ""
    try:
        stamp = "%s:%s:%s" % (path.resolve(), path.stat().st_size, path.stat().st_mtime_ns)
    except OSError:
        return ""
    key = hashlib.sha256(stamp.encode("utf-8")).hexdigest()[:24]
    target = cache_dir() / "lock" / (key + ".jpg")
    if target.exists() and target.stat().st_size > 0:
        return str(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Curtain and lock surface can request the same video concurrently. Publish
    # only a complete image so neither reads ffmpeg's partially written output.
    with tempfile.NamedTemporaryFile(suffix=".jpg", dir=target.parent, delete=False) as temporary:
        pending = Path(temporary.name)
    try:
        for seek in ("1", "0"):
            pending.write_bytes(b"")
            result = subprocess.run(
                ["ffmpeg", "-y", "-v", "error", "-ss", seek, "-i", str(path), "-frames:v", "1",
                 "-vf", "scale=1920:-2", str(pending)],
                capture_output=True,
                timeout=30,
            )
            if result.returncode == 0 and pending.stat().st_size > 0:
                pending.replace(target)
                return str(target)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    finally:
        pending.unlink(missing_ok=True)
    return ""


def user_name() -> str:
    try:
        account = pwd.getpwuid(os.getuid())
        return account.pw_gecos.split(",")[0] or account.pw_name
    except KeyError:
        return os.environ.get("USER", "Welcome back")


def battery_status() -> str:
    for device in sorted(Path("/sys/class/power_supply").glob("*")):
        try:
            if (device / "type").read_text().strip() != "Battery":
                continue
            percent = int((device / "capacity").read_text().strip())
            status = (device / "status").read_text().strip()
            return "%d%% · %s" % (percent, status)
        except (OSError, ValueError):
            continue
    return ""



def ipc_call(method: str) -> str:
    result = subprocess.run(
        [os.environ.get("QS_BIN", "qs"), "ipc", "-c", "zestify", "call", "zestify", method],
        capture_output=True, text=True, timeout=3,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Zestify shell is unavailable; run zesti shell start")
    return result.stdout.strip()


def lock_status() -> dict:
    state = json.loads(ipc_call("lockStatus"))
    if not isinstance(state, dict) or not all(key in state for key in ("generation", "active", "secure", "error")):
        raise RuntimeError("Invalid lock status from Zestify")
    return state


def request_lock(wait: bool = False, timeout: float = 10) -> int:
    generation = int(ipc_call("lock"))
    deadline = time.monotonic() + timeout
    while True:
        state = lock_status()
        if state["generation"] != generation:
            raise RuntimeError("Lock session changed before confirmation")
        if state["secure"] and state["active"]:
            break
        if state["error"] or not state["active"]:
            raise RuntimeError(state["error"] or "Locker stopped before the session was secured")
        if time.monotonic() >= deadline:
            raise RuntimeError("Timed out waiting for compositor lock confirmation")
        time.sleep(0.05)
    if wait:
        while True:
            state = lock_status()
            if state["generation"] != generation or not state["active"]:
                break
            time.sleep(0.1)
    print(json.dumps({"ok": True, "locked": not wait}))
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="zesti lock")
    parser.add_argument("--wait", action="store_true", help="wait until the session is unlocked")
    parser.add_argument("--frame", help=argparse.SUPPRESS)
    parser.add_argument("--status", choices=["battery", "user"], help=argparse.SUPPRESS)
    parser.add_argument("--suspend", nargs=argparse.REMAINDER, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.frame is not None:
        frame = lock_frame(args.frame)
        print(json.dumps({"url": Path(frame).as_uri() if frame else ""}))
        return 0
    if args.status:
        print(user_name() if args.status == "user" else battery_status())
        return 0
    try:
        if args.suspend is not None:
            if not args.suspend:
                raise RuntimeError("Missing suspend command")
            request_lock()
            return subprocess.run(args.suspend).returncode
        return request_lock(args.wait)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"ok": False, "error": str(error)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
