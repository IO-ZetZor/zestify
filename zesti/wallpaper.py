"""Zesti-owned wallpaper state: listing, setting, thumbnails, and palette hooks.

No external shell executable or state is read or written. All state lives under the
Zestify XDG roots owned by :mod:`zesti.paths`. Wallpaper changes are
transactional: the palette is generated *before* any state file is committed,
so a failure leaves every prior state file byte-identical.
"""

from __future__ import annotations

import hashlib
import fcntl
import os
import shutil
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
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
    palette_settings: PaletteSettings = field(default_factory=PaletteSettings)


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
        fd, name = tempfile.mkstemp(dir=cache_dir, prefix=".frame-", suffix=".jpg")
        os.close(fd)
        temporary = Path(name)
        try:
            for seek in ("2", "0"):
                temporary.write_bytes(b"")
                command = [
                    "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-ss", seek, "-i", str(path), "-frames:v", "1",
                    "-vf", "scale=960:-1:flags=lanczos", "-q:v", "2", str(temporary),
                ]
                if run(command, timeout=30) == 0 and temporary.stat().st_size > 0:
                    break
            else:
                raise WallpaperError(f"ffmpeg frame extraction failed for {path}")
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    return target


def cached_palette_source(path: Path, paths: Paths) -> Path | None:
    """Return an existing video frame without launching FFmpeg."""
    path = Path(path)
    if path.suffix.lower() not in VIDEO_EXTENSIONS:
        return path
    frame = paths.cache_home / "wallpapers" / f"{_stamp_key(path)}.jpg"
    return frame if frame.is_file() and frame.stat().st_size > 0 else None


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
    target = paths.wallpaper_dir / "thumbnail.jpg"
    temporary = None
    try:
        if target.exists() and source.samefile(target):
            return
        fd, name = tempfile.mkstemp(dir=target.parent, prefix=".thumbnail-")
        os.close(fd)
        temporary = Path(name)
        shutil.copy2(source, temporary)
        temporary.replace(target)
    except OSError:
        pass  # Keep a valid previous thumbnail when the optional copy fails.
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


@contextmanager
def _wallpaper_lock(paths: Paths):
    paths.wallpaper_dir.mkdir(parents=True, exist_ok=True)
    with (paths.wallpaper_dir / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


@contextmanager
def _state_transaction(paths: Paths, files):
    # Keep backups on disk so large existing thumbnails do not inflate RSS.
    with tempfile.TemporaryDirectory(prefix=".transaction-", dir=paths.wallpaper_dir) as directory:
        backups = {}
        for index, path in enumerate(dict.fromkeys(files)):
            backup = Path(directory) / str(index)
            if path.exists() or path.is_symlink():
                shutil.copy2(path, backup, follow_symlinks=False)
                backups[path] = backup
            else:
                backups[path] = None
        try:
            yield
        except BaseException as error:
            failures = []
            for path, backup in backups.items():
                try:
                    if backup is None:
                        path.unlink(missing_ok=True)
                    else:
                        backup.replace(path)
                except OSError as rollback:
                    failures.append(f"{path}: {rollback}")
            if failures:
                raise WallpaperError(f"{error}; could not restore state: {'; '.join(failures)}") from error
            raise


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
        scheme = services.generate_palette(source, services.palette_settings, services.run)
    except WallpaperError as exc:
        result["error"] = str(exc)
        return result
    except Exception as exc:  # noqa: BLE001 - any generation failure is fatal
        result["error"] = f"palette generation failed: {exc}"
        return result

    try:
        with _wallpaper_lock(paths):
            if destination == "monitor":
                monitor = monitor or ""
                pointer = paths.monitor_dir / f"{monitor_slug(monitor)}.txt"
                palette = paths.monitor_dir / f"{monitor_slug(monitor)}-scheme.json"
                files = [pointer, palette]
            else:
                overrides = list(paths.monitor_dir.glob("*.txt")) if destination == "all" else [
                    paths.monitor_dir / f"{monitor_slug(services.primary_monitor)}.txt"]
                palettes = list(paths.monitor_dir.glob("*-scheme.json")) if destination == "all" else [
                    paths.monitor_dir / f"{monitor_slug(services.primary_monitor)}-scheme.json"]
                files = [paths.wallpaper_dir / "path.txt", paths.wallpaper_dir / "current",
                         paths.wallpaper_dir / "thumbnail.jpg", paths.scheme_file, *overrides, *palettes]
            with _state_transaction(paths, files):
                if destination == "monitor":
                    atomic_write(pointer, str(path.resolve()))
                    atomic_write(palette, __import__("json").dumps(scheme))
                else:
                    _write_state_file(paths, "path.txt", str(path.resolve()))
                    if destination != "all":
                        _write_state_file(paths, "current", str(path.resolve()))
                    _copy_to_thumbnail(source, paths)
                    for override in overrides:
                        if override.exists():
                            atomic_write(override, "")
                    for palette in palettes:
                        if palette.exists():
                            atomic_write(palette, "{}")
                    services.save_scheme(paths, scheme)
            if destination != "monitor" or monitor == services.primary_monitor:
                try:
                    result["theme"] = services.theme_applier(scheme)
                except Exception as exc:  # Theme failure does not roll back a committed wallpaper.
                    print(f"zesti: theme apply: {exc}", file=sys.stderr)
                    result["theme"] = [{"target": "apply", "ok": False, "error": str(exc)}]
    except Exception as exc:
        result["error"] = f"could not write wallpaper state: {exc}"
        return result

    result["ok"] = True
    result["path"] = str(path.resolve())
    return result


def refresh_palettes(paths: Paths, services: WallpaperServices) -> dict:
    try:
        with _wallpaper_lock(paths):
            return _refresh_palettes_locked(paths, services)
    except OSError as exc:
        return {"ok": False, "updated": 0, "error": f"could not refresh wallpaper palettes: {exc}"}


def _refresh_palettes_locked(paths: Paths, services: WallpaperServices) -> dict:
    """Regenerate active palettes without changing wallpaper paths or overrides.

    Finish generation before writing schemes so unreadable wallpapers keep all
    previous palettes. Empty monitor overrides are intentionally ignored.
    """
    result = {"ok": False, "updated": 0, "error": None}
    try:
        targets = []
        global_path = effective_wallpaper(paths, None)
        if global_path:
            targets.append((paths.scheme_file, global_path))
        if paths.monitor_dir.is_dir():
            for override in sorted(paths.monitor_dir.glob("*.txt")):
                value = override.read_text(encoding="utf-8").strip()
                if value:
                    targets.append((override.with_name(override.stem + "-scheme.json"), Path(value)))
        generated = {}
        pending = []
        for destination, wallpaper in targets:
            if wallpaper not in generated:
                source = extract_palette_source(wallpaper, paths, services.run)
                generated[wallpaper] = services.generate_palette(source, services.palette_settings, services.run)
            pending.append((destination, generated[wallpaper]))
        with _state_transaction(paths, [destination for destination, _ in pending]):
            for destination, scheme in pending:
                atomic_write(destination, __import__("json").dumps(scheme))
        result["updated"] = len(pending)
    except Exception as exc:
        result["error"] = f"could not refresh wallpaper palettes: {exc}"
        return result
    primary_scheme = paths.monitor_dir / f"{monitor_slug(services.primary_monitor)}-scheme.json"
    app_scheme = next((scheme for destination, scheme in pending if destination == primary_scheme), None)
    if app_scheme is None:
        app_scheme = next((scheme for destination, scheme in pending if destination == paths.scheme_file), None)
    if app_scheme:
        try:
            result["theme"] = services.theme_applier(app_scheme)
        except Exception as exc:
            print(f"zesti: theme apply: {exc}", file=sys.stderr)
            result["theme"] = [{"target": "apply", "ok": False, "error": str(exc)}]
    result["ok"] = True
    return result
