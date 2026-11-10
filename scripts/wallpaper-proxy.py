#!/usr/bin/env python3
"""Monitor-sized H.264 proxy cache for Zestify video wallpapers."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def home() -> Path:
    return Path(os.environ.get("HOME", str(Path.home())))


def cache_root() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    return (Path(base) if base else home() / ".cache") / "zestify/wallpapers"


def fail(message: str) -> int:
    print(json.dumps({"ok": False, "error": message}))
    return 1


def key_for(source: Path, width: int, height: int, codec: str, crf: int, fps: float) -> str:
    stamp = "|".join([
        str(source.resolve()),
        str(source.stat().st_size),
        str(source.stat().st_mtime_ns),
        str(width),
        str(height),
        codec,
        str(crf),
        "%.6g" % fps,
    ])
    return hashlib.sha256(stamp.encode("utf-8")).hexdigest()


def probe_size(path: Path) -> tuple[int, int] | None:
    try:
        result = subprocess.run([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json", str(path),
        ], text=True, capture_output=True, timeout=30)
        stream = json.loads(result.stdout)["streams"][0]
        return int(stream["width"]), int(stream["height"])
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, IndexError):
        return None


def probe_fps(path: Path) -> float | None:
    try:
        result = subprocess.run([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=avg_frame_rate,r_frame_rate", "-of", "json", str(path),
        ], text=True, capture_output=True, timeout=30)
        stream = json.loads(result.stdout)["streams"][0]
        for entry in (stream.get("avg_frame_rate"), stream.get("r_frame_rate")):
            numerator, _, denominator = str(entry or "").partition("/")
            fps = float(numerator) / float(denominator or 1)
            if fps > 0:
                return fps
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, IndexError, ZeroDivisionError):
        pass
    return None


def ensure(source: Path, width: int, height: int, codec: str = "h264", crf: int = 20) -> int:
    if not source.is_file():
        return fail("source not found: %s" % source)
    if width <= 0 or height <= 0:
        return fail("invalid target size: %sx%s" % (width, height))
    encoders = {"h264": "libx264", "h265": "libx265", "hevc": "libx265"}
    encoder = encoders.get(codec)
    if encoder is None:
        return fail("unsupported codec: %s" % codec)
    if crf < 0 or crf > 51:
        return fail("invalid CRF: %s" % crf)
    out_fps = min(probe_fps(source) or 30.0, 30.0)
    key = key_for(source, width, height, codec, crf, out_fps)
    target = cache_root() / key / ("%sx%s.mp4" % (width, height))
    if target.exists() and target.stat().st_size > 0:
        print(json.dumps({"ok": True, "path": str(target), "cached": True, "width": width, "height": height}))
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.parent / (".tmp-%s-%s" % (os.getpid(), target.name))
    filter_graph = "scale=%s:%s:force_original_aspect_ratio=increase,crop=%s:%s" % (width, height, width, height)
    command = [
        "ffmpeg", "-y", "-v", "error", "-i", str(source),
        "-vf", filter_graph, "-r", "%.6g" % out_fps, "-c:v", encoder, "-preset", "veryfast",
        "-crf", str(crf), "-an", "-movflags", "+faststart",
    ]
    if codec in ("h265", "hevc"):
        command += ["-tag:v", "hvc1"]
    command.append(str(temp))
    try:
        result = subprocess.run(command, capture_output=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as error:
        temp.unlink(missing_ok=True)
        return fail("ffmpeg failed: %s" % error)
    if result.returncode != 0:
        temp.unlink(missing_ok=True)
        return fail(result.stderr.decode("utf-8", "replace").strip() or "ffmpeg failed")
    size = probe_size(temp)
    if size != (width, height):
        temp.unlink(missing_ok=True)
        return fail("proxy size mismatch: expected %sx%s, got %s" % (width, height, size))
    temp.replace(target)
    print(json.dumps({"ok": True, "path": str(target), "cached": False, "width": width, "height": height}))
    return 0


def command_proxy(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="zestify proxy")
    sub = parser.add_subparsers(dest="command", required=True)
    ensure_parser = sub.add_parser("ensure")
    ensure_parser.add_argument("--source", required=True)
    ensure_parser.add_argument("--width", required=True, type=int)
    ensure_parser.add_argument("--height", required=True, type=int)
    ensure_parser.add_argument("--codec", default="h264", choices=["h264", "h265", "hevc"])
    ensure_parser.add_argument("--crf", default=20, type=int)
    args = parser.parse_args(argv)
    if args.command == "ensure":
        return ensure(Path(args.source).expanduser(), args.width, args.height, args.codec, args.crf)
    return fail("unknown proxy command")


def command_cache(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="zestify cache")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    prune = sub.add_parser("prune")
    prune.add_argument("--keep", action="append", default=[])
    args = parser.parse_args(argv)
    root = cache_root()
    if args.command == "status":
        files = list(root.rglob("*.mp4")) if root.exists() else []
        print(json.dumps({"ok": True, "path": str(root), "count": len(files), "bytes": sum(p.stat().st_size for p in files)}))
        return 0
    if args.command == "prune":
        removed = []
        if root.exists():
            for child in list(root.iterdir()):
                if child.is_dir() and child.name not in set(args.keep):
                    shutil.rmtree(child, ignore_errors=True)
                    removed.append(child.name)
        print(json.dumps({"ok": True, "removed": removed}))
        return 0
    return fail("unknown cache command")


def main(argv: list[str]) -> int:
    if not argv:
        return fail("missing command")
    if argv[0] == "proxy":
        return command_proxy(argv[1:])
    if argv[0] == "cache":
        return command_cache(argv[1:])
    return fail("unknown proxy command: %s" % argv[0])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
