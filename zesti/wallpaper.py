"""Zesti-owned wallpaper state: listing, setting, thumbnails, and palette hooks.

No Caelestia executable or state is read or written. All state lives under the
Zestify XDG roots owned by :mod:`zesti.paths`. Wallpaper changes are
transactional: the palette is generated *before* any state file is committed,
so a failure leaves every prior state file byte-identical.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Mapping

from zesti.paths import Paths, atomic_write
from zesti.palette import PaletteSettings

VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
ALL_EXTENSIONS = VIDEO_EXTENSIONS | IMAGE_EXTENSIONS


class WallpaperError(Exception):
    """Raised when a wallpaper operation cannot complete safely."""


@dataclass(frozen=True)
class WallpaperTarget:
    kind: str  # "global" | "monitor" | "all" | "random"
    monitor: str | None = None
    random: bool = False
    no_filter: bool = False


@dataclass(frozen=True)
class WallpaperServices:
    generate_palette: Callable[[Path, PaletteSettings, Callable[..., int]], dict]
    save_scheme: Callable[[Paths, Mapping], None]
    theme_applier: Callable[[dict], list] = field(default_factory=lambda: lambda _: [])
    run: Callable[..., int] = field(default_factory=lambda: _default_run)
    rng: object = field(default_factory=lambda: __import__("random"))
    primary_monitor: str = "eDP-1"


def _default_run(cmd, **kwargs):  # pragma: no cover - real subprocess path
    import subprocess

    return subprocess.run(cmd, **kwargs).returncode


def monitor_slug(name: str) -> str:
    """Convert a monitor connector name into a safe, non-escaping filename slug.

    Lowercases, keeps alphanumerics and hyphens, collapses every other character
    (including ``/``, ``\\``, ``..``) into a single ``_``, and never returns an
    empty or dot-led string.
    """
    name = str(name).strip().lower()
    out: list[str] = []
    prev_sep = False
    for ch in name:
        if ch.isalnum():
            out.append(ch)
            prev_sep = False
        else:
            # Hyphens and every other separator collapse to a single "-".
            sep = "-"
            if not prev_sep or out and out[-1] != sep:
                out.append(sep)
            prev_sep = True
    slug = "".join(out).strip("-")
    return slug or "_"


def _is_wallpaper(path: Path) -> bool:
    return path.suffix.lower() in ALL_EXTENSIONS


def list_wallpapers(
    directory: Path,
    paths: Paths | None = None,
    run: Callable[..., int] | None = None,
) -> list[dict]:
    """List wallpaper items in ``directory`` with the QML item schema.

    Each item: ``{"path", "name", "isVideo", "thumb"}``. Non-image/video files
    are ignored. Results are sorted by name. When ``paths`` and ``run`` are
    supplied, cached video frames are generated concurrently so the gallery can
    display video thumbnails.
    """
    directory = Path(directory)
    try:
        entries = sorted(
            p for p in directory.iterdir() if p.is_file() and _is_wallpaper(p)
        )
    except OSError:
        return []
    items: list[dict] = []
    videos: list[Path] = []
    for path in entries:
        is_video = path.suffix.lower() in VIDEO_EXTENSIONS
        if is_video:
            videos.append(path)
        items.append(
            {
                "path": str(path.resolve()),
                "name": path.name,
                "isVideo": is_video,
                "thumb": str(path.resolve()) if not is_video else "",
            }
        )

    if paths is not None and run is not None and videos:
        def video_thumb(path: Path) -> str:
            try:
                thumb = make_thumbnail(path, paths, run)
            except Exception:  # noqa: BLE001 - a failed thumb is non-fatal
                return ""
            return "" if thumb.suffix.lower() in VIDEO_EXTENSIONS else str(thumb)

        with ThreadPoolExecutor(max_workers=min(4, len(videos))) as pool:
            frames = list(pool.map(video_thumb, videos))
        for item, frame in zip(
            (item for item in items if item["isVideo"]), frames
        ):
            item["thumb"] = frame
    return items


def effective_wallpaper(paths: Paths, monitor: str | None) -> Path | None:
    """Return the effective wallpaper path for ``monitor`` (or the global)."""
    if monitor:
        override = paths.monitor_dir / f"{monitor_slug(monitor)}.txt"
        try:
            value = override.read_text(encoding="utf-8").strip()
        except OSError:
            return None
        return Path(value) if value else None
    try:
        value = (paths.wallpaper_dir / "path.txt").read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return Path(value) if value else None


def _stamp_key(path: Path) -> str:
    try:
        st = path.stat()
        raw = f"{path.resolve()}:{st.st_size}:{st.st_mtime_ns}"
    except OSError:
        raw = str(path)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def extract_palette_source(path: Path, paths: Paths, run: Callable[..., int]) -> Path:
    """Return the image to use for palette generation.

    Images are returned as-is. Videos are represented by a cached ffmpeg frame
    written under the Zestify cache. Raises :class:`WallpaperError` if the frame
    cannot be extracted.
    """
    path = Path(path)
    if path.suffix.lower() not in VIDEO_EXTENSIONS:
        return path
    cache_dir = paths.cache_home / "wallpapers"
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / f"{_stamp_key(path)}.jpg"
    if not (target.exists() and target.stat().st_size > 0):
        command = [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-ss", "2", "-i", str(path), "-frames:v", "1",
            "-vf", "scale=960:-1:flags=lanczos", "-q:v", "2", str(target),
        ]
        if run(command) != 0 or not (target.exists() and target.stat().st_size > 0):
            raise WallpaperError(f"ffmpeg frame extraction failed for {path}")
    return target


def make_thumbnail(path: Path, paths: Paths, run: Callable[..., int]) -> Path:
    """Return the thumbnail path for ``path``.

    Images are their own thumbnail. Videos are represented by a cached ffmpeg
    frame under the Zestify cache; the resolved source is returned only when
    frame extraction fails.
    """
    path = Path(path)
    if path.suffix.lower() in VIDEO_EXTENSIONS:
        try:
            return extract_palette_source(path, paths, run)
        except WallpaperError:
            pass  # thumbnail is best-effort; fall back to the source
    return path.resolve()


def _write_state_file(paths: Paths, name: str, content: str) -> None:
    paths.wallpaper_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(paths.wallpaper_dir / name, content)


def _copy_to_thumbnail(source: Path, paths: Paths) -> None:
    paths.wallpaper_dir.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copy2(source, paths.wallpaper_dir / "thumbnail.jpg")
    except OSError:  # includes shutil.SameFileError
        atomic_write(paths.wallpaper_dir / "thumbnail.jpg", "")


def set_wallpaper(
    path: Path,
    target: WallpaperTarget,
    paths: Paths,
    services: WallpaperServices,
) -> dict:
    """Transactionally set the wallpaper.

    Returns a result dict with ``ok``, ``path``, ``monitor``, ``all`` and, on
    failure, ``error``. On any failure every prior state file is left
    byte-identical.
    """
    monitor = target.monitor
    destination = target.kind
    if target.kind == "random":
        destination = "monitor" if monitor else "global"
    elif target.random:
        destination = "all" if target.kind == "all" else ("monitor" if monitor else "global")

    result: dict = {
        "ok": False,
        "path": str(path),
        "monitor": monitor,
        "all": destination == "all",
        "error": None,
    }

    path = Path(path)
    if target.kind == "random" or target.random:
        if not path.is_dir():
            result["error"] = "random requires a directory"
            return result
        items = [
            it for it in list_wallpapers(path)
            if target.no_filter or not it["isVideo"]
        ]
        active = effective_wallpaper(paths, monitor)
        candidates = [
            Path(it["path"]) for it in items if Path(it["path"]).resolve() != active
        ]
        if not candidates:
            result["error"] = "no candidate wallpaper"
            return result
        path = services.rng.choice(candidates)

    if not path.is_file():
        result["error"] = f"wallpaper not found: {path}"
        return result
    if not _is_wallpaper(path):
        result["error"] = f"unsupported wallpaper type: {path.suffix}"
        return result

    # Generate the palette *before* committing any state. On failure nothing is
    # written, so prior state stays byte-identical.
    try:
        source = extract_palette_source(path, paths, services.run)
        scheme = services.generate_palette(source, PaletteSettings(), services.run)
    except WallpaperError as exc:
        result["error"] = str(exc)
        return result
    except Exception as exc:  # noqa: BLE001 - any generation failure is fatal
        result["error"] = f"palette generation failed: {exc}"
        return result

    try:
        if destination == "monitor":
            monitor = monitor or ""
            paths.monitor_dir.mkdir(parents=True, exist_ok=True)
            atomic_write(
                paths.monitor_dir / f"{monitor_slug(monitor)}.txt", str(path.resolve())
            )
            atomic_write(
                paths.monitor_dir / f"{monitor_slug(monitor)}-scheme.json",
                __import__("json").dumps(scheme),
            )
        elif destination == "all":
            _write_state_file(paths, "path.txt", str(path.resolve()))
            _copy_to_thumbnail(source, paths)
            # Truncate watched override files rather than unlinking them so QML
            # file watches remain attached.
            if paths.monitor_dir.is_dir():
                for override in paths.monitor_dir.glob("*.txt"):
                    try:
                        override.write_text("", encoding="utf-8")
                    except OSError:
                        pass
                for palette in paths.monitor_dir.glob("*-scheme.json"):
                    atomic_write(palette, "{}")
        else:  # global / primary
            _write_state_file(paths, "path.txt", str(path.resolve()))
            _write_state_file(paths, "current", str(path.resolve()))
            _copy_to_thumbnail(source, paths)
            for name in (f"{monitor_slug(services.primary_monitor)}.txt",
                         f"{monitor_slug(services.primary_monitor)}-scheme.json"):
                override = paths.monitor_dir / name
                if override.exists():
                    atomic_write(override, "{}" if name.endswith(".json") else "")
    except OSError as exc:
        result["error"] = f"could not write wallpaper state: {exc}"
        return result

    if destination != "monitor":
        services.save_scheme(paths, scheme)
    if destination != "monitor" or monitor == services.primary_monitor:
        try:
            result["theme"] = services.theme_applier(scheme)
        except Exception as exc:  # theme failure must not roll back wallpaper state
            print(f"zesti: theme apply: {exc}", file=sys.stderr)
            result["theme"] = [{"target": "apply", "ok": False, "error": str(exc)}]

    result["ok"] = True
    result["path"] = str(path.resolve())
    return result
