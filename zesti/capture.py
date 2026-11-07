"""Screenshot and screen-recording capture utilities for zesti.

All subprocess invocation uses argument arrays (never shell interpolation).
Notifications are optional and non-fatal. Cancellation (selector exit 1 or
empty output) is a clean success, distinct from a runtime failure. Temporary
files live inside Zestify cache/state.
"""

from __future__ import annotations

import os
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Mapping

from zesti.paths import Paths, atomic_write


VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}


def _default_run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


class CaptureError(Exception):
    """Raised when a capture operation cannot complete."""


@dataclass(frozen=True)
class ScreenshotOptions:
    region: str | None = None
    freeze: bool = False


@dataclass(frozen=True)
class RecordOptions:
    region: str | None = None
    sound: bool = False
    monitor: str | None = None


@dataclass(frozen=True)
class CaptureServices:
    run: Callable[..., int] = field(default_factory=lambda: _default_run)
    start_detached: Callable[..., int] = field(default_factory=lambda: _default_start_detached)
    notify: Callable[..., object] = field(default_factory=lambda: lambda *a, **k: None)
    clipboard: Callable[[str], int] = field(default_factory=lambda: (lambda data: 0))


def _default_start_detached(cmd, **kwargs) -> int:
    """Launch a long-lived process detached; return 0 immediately."""
    try:
        subprocess.Popen(cmd, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return 0
    except FileNotFoundError as exc:
        raise FileNotFoundError(str(exc)) from exc
    except OSError as exc:
        return 1


@dataclass(frozen=True)
class CaptureResult:
    ok: bool
    path: str | None = None
    error: str | None = None
    cancelled: bool = False


def _stamp() -> str:
    return str(int(time.time() * 1000))


def _cache_dir(paths: Paths, sub: str) -> Path:
    d = paths.cache_home / sub
    d.mkdir(parents=True, exist_ok=True)
    return d


def _state_dir(paths: Paths, sub: str) -> Path:
    d = paths.state_home / "zestify" / sub
    d.mkdir(parents=True, exist_ok=True)
    return d


def _notify(services: CaptureServices, summary: str, body: str = "") -> None:
    try:
        services.notify(summary, body)
    except Exception:  # noqa: BLE001 - notifications are non-fatal
        pass


def take_screenshot(
    options: ScreenshotOptions, paths: Paths, services: CaptureServices
) -> CaptureResult:
    """Capture a screenshot with grim, optionally freezing via grimblast.

    Copies the result with wl-copy and caches it under Zestify.
    """
    try:
        out_dir = _cache_dir(paths, "screenshots")
        out = out_dir / f"screenshot-{_stamp()}.png"

        source: str | None = None
        if options.freeze:
            frozen = out_dir / f"freeze-{_stamp()}.png"
            rc = services.run(["grimblast", "--freeze", "save", "area", str(frozen)])
            if rc != 0:
                return CaptureResult(False, None, "freeze backend unavailable", False)
            source = str(frozen)

        cmd = ["grim"]
        if options.region:
            # Interactive region selection via slurp; cancellation is success.
            rc = services.run(["slurp"])
            if rc != 0:
                return CaptureResult(True, None, None, True)
            cmd += ["-g", options.region]
        if source:
            cmd += [source]
        cmd += [str(out)]

        if services.run(cmd) != 0:
            return CaptureResult(False, None, "grim failed", False)

        try:
            services.run(["wl-copy", str(out)])
        except Exception:  # noqa: BLE001 - copy is non-fatal
            pass

        _notify(services, "Screenshot", f"Saved to {out.name}")
        return CaptureResult(True, str(out), None, False)
    except FileNotFoundError as exc:
        return CaptureResult(False, None, f"missing dependency: {exc}", False)
    except CaptureError:
        raise
    except Exception as exc:  # noqa: BLE001 - any capture failure
        return CaptureResult(False, None, str(exc), False)


def record_start(
    options: RecordOptions, paths: Paths, services: CaptureServices
) -> CaptureResult:
    """Start recording with gpu-screen-recorder; state under Zestify."""
    try:
        state_dir = _state_dir(paths, "record")
        marker = state_dir / "recording"
        if marker.exists():
            return CaptureResult(False, None, "already recording", False)

        cmd = ["gpu-screen-recorder"]
        if options.monitor:
            cmd += ["--monitor", options.monitor]
        if options.region:
            cmd += ["--region", options.region]
        if options.sound:
            cmd += ["--sound"]
        output = state_dir / f"recording-{_stamp()}.mp4"
        cmd += [str(output)]

        # gpu-screen-recorder is a long-lived daemon: launch detached so
        # record_start returns immediately instead of blocking for the
        # recorder's entire lifetime.
        try:
            services.start_detached(cmd)
        except FileNotFoundError as exc:
            return CaptureResult(False, None, f"missing dependency: {exc}", False)
        except OSError as exc:
            return CaptureResult(False, None, f"recorder failed to start: {exc}", False)

        marker.write_text(str(output), encoding="utf-8")
        _notify(services, "Recording", "started")
        return CaptureResult(True, str(output), None, False)
    except FileNotFoundError as exc:
        return CaptureResult(False, None, f"missing dependency: {exc}", False)
    except Exception as exc:  # noqa: BLE001
        return CaptureResult(False, None, str(exc), False)


def record_pause(paths: Paths, services: CaptureServices) -> CaptureResult:
    """Pause recording by sending USR2 to gpu-screen-recorder."""
    try:
        state_dir = _state_dir(paths, "record")
        marker = state_dir / "recording"
        if not marker.exists():
            return CaptureResult(False, None, "not recording", False)
        services.run(["pkill", "-USR2", "gpu-screen-recorder"])
        _notify(services, "Recording", "paused")
        return CaptureResult(True, None, None, False)
    except Exception as exc:  # noqa: BLE001
        return CaptureResult(False, None, str(exc), False)


def record_stop(
    copy_to_clipboard: bool, paths: Paths, services: CaptureServices
) -> CaptureResult:
    """Stop recording, move the file into place, optionally copy a file URI."""
    try:
        state_dir = _state_dir(paths, "record")
        marker = state_dir / "recording"
        if not marker.exists():
            return CaptureResult(False, None, "not recording", False)
        source = Path(marker.read_text(encoding="utf-8").strip())
        final = state_dir / f"recording-final-{_stamp()}.mp4"
        if source.exists():
            source.rename(final)
        else:
            final.write_bytes(b"")
        marker.unlink(missing_ok=True)
        if copy_to_clipboard:
            services.clipboard(f"file://{final}")
        _notify(services, "Recording", "saved")
        return CaptureResult(True, str(final), None, False)
    except Exception as exc:  # noqa: BLE001
        return CaptureResult(False, None, str(exc), False)


def record_toggle(paths: Paths, services: CaptureServices) -> CaptureResult:
    """Toggle recording on/off."""
    marker = _state_dir(paths, "record") / "recording"
    if marker.exists():
        return record_stop(True, paths, services)
    return record_start(RecordOptions(), paths, services)
