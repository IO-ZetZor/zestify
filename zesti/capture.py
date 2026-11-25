"""Screenshot and screen-recording capture utilities for zesti.

All subprocess invocation uses argument arrays (never shell interpolation).
Notifications are optional and non-fatal. Cancellation (selector exit 1 or
empty output) is a clean success, distinct from a runtime failure. Temporary
files live inside Zestify cache/state.
"""

from __future__ import annotations

import os
import fcntl
import json
import re
import select
import signal
import subprocess
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from zesti.paths import Paths, atomic_json


VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}


def _default_run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    return subprocess.run(cmd, **kwargs)


class CaptureError(Exception):
    """Raised when a capture operation cannot complete."""


@dataclass(frozen=True)
class ScreenshotOptions:
    region: str | None = None
    freeze: bool = False


@dataclass(frozen=True)
class RecordOptions:
    region: str | None = None
    sound: bool = True
    monitor: str | None = None


@dataclass(frozen=True)
class CaptureServices:
    run: Callable = field(default_factory=lambda: _default_run)
    start_detached: Callable = field(default_factory=lambda: _default_start_detached)
    notify: Callable[..., object] = field(default_factory=lambda: lambda *a, **k: None)
    clipboard: Callable[[str], int] = field(default_factory=lambda: _default_clipboard)


_children: dict[int, subprocess.Popen] = {}


def _default_start_detached(cmd, **kwargs) -> subprocess.Popen:
    """Launch a recorder and retain its PID for precise lifecycle control."""
    child = subprocess.Popen(cmd, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _children[child.pid] = child
    return child


def _default_clipboard(data: str) -> int:
    # wl-copy forks a clipboard owner that can retain stderr. Captured pipes
    # would keep communicate() waiting after the foreground command exits.
    return _default_run(["wl-copy", "--type", "text/uri-list"], input=data + "\r\n",
                        capture_output=False, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL).returncode


@dataclass(frozen=True)
class CaptureResult:
    ok: bool
    path: str | None = None
    error: str | None = None
    cancelled: bool = False
    recording: bool | None = None


def _stamp() -> str:
    return str(int(time.time() * 1000))


def _cache_dir(paths: Paths, sub: str) -> Path:
    d = paths.cache_home / "zestify" / sub
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


def _returncode(result) -> int:
    return result if isinstance(result, int) else result.returncode


def _geometry(value: str) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"(-?\d+),(-?\d+)\s+(\d+)x(\d+)", value.strip())
    if match:
        x, y, width, height = map(int, match.groups())
    else:
        match = re.fullmatch(r"(\d+)x(\d+)([+-]\d+)([+-]\d+)", value.strip())
        if not match:
            raise CaptureError("invalid region geometry")
        width, height, x, y = map(int, match.groups())
    if width <= 0 or height <= 0:
        raise CaptureError("invalid region size")
    return x, y, width, height


def _select_region(value: str, services: CaptureServices):
    if value != "auto":
        return _geometry(value)
    result = services.run(["slurp"])
    rc = _returncode(result)
    if rc == 1 or rc == 0 and not getattr(result, "stdout", "").strip():
        return None
    if rc != 0:
        raise CaptureError("region selector failed")
    return _geometry(result.stdout.strip())


def _monitors(services: CaptureServices) -> list[dict]:
    result = services.run(["hyprctl", "-j", "monitors"])
    if _returncode(result) != 0:
        raise CaptureError("cannot query Hyprland monitors")
    monitors = json.loads(result.stdout)
    if not isinstance(monitors, list) or not monitors:
        raise CaptureError("no monitor is available for capture")
    return monitors


def _focused_monitor(services: CaptureServices) -> dict:
    monitors = _monitors(services)
    return next((monitor for monitor in monitors if monitor.get("focused")), monitors[0])


def _config(paths: Paths) -> dict:
    from zesti import ROOT
    from zesti.config import load_config

    return load_config(ROOT / "config/default.json", paths.config_file)


def take_screenshot(
    options: ScreenshotOptions, paths: Paths, services: CaptureServices
) -> CaptureResult:
    """Capture PNG data from the focused monitor or selected region."""
    out = None
    try:
        out = _cache_dir(paths, "screenshots") / f"screenshot-{_stamp()}.png"
        if options.freeze:
            if options.region not in (None, "auto"):
                raise CaptureError("freeze supports interactive selection only")
            backend = _config(paths).get("screenshot", {}).get("freezeBackend", "grimblast")
            result = services.run([backend, "--freeze", "save", "area", str(out)])
            if _returncode(result) == 1 and not out.exists():
                return CaptureResult(True, cancelled=True)
        else:
            command = ["grim"]
            if options.region:
                region = _select_region(options.region, services)
                if region is None:
                    return CaptureResult(True, cancelled=True)
                x, y, width, height = region
                command += ["-g", f"{x},{y} {width}x{height}"]
            else:
                command += ["-o", _focused_monitor(services)["name"]]
            result = services.run([*command, str(out)])
        if _returncode(result) != 0 or not out.is_file() or out.stat().st_size == 0:
            raise CaptureError("screenshot backend did not produce a PNG")
        image = out.read_bytes()
        if not image.startswith(b"\x89PNG\r\n\x1a\n"):
            raise CaptureError("screenshot backend returned invalid PNG data")
        copied = services.run(["wl-copy", "--type", "image/png"], input=image, text=False,
                              capture_output=False, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)
        if _returncode(copied) != 0:
            return CaptureResult(False, str(out), "could not copy screenshot to clipboard")
        _notify(services, "Screenshot", f"Saved to {out.name}")
        return CaptureResult(True, str(out))
    except FileNotFoundError as exc:
        return CaptureResult(False, str(out) if out and out.exists() else None, f"missing dependency: {exc}")
    except Exception as exc:
        return CaptureResult(False, str(out) if out and out.exists() else None, str(exc))


def _process_identity(pid: int) -> str:
    if not isinstance(pid, int) or pid <= 1:
        raise CaptureError("recorder did not return a valid PID")
    path = Path(f"/proc/{pid}/stat")
    if path.stat().st_uid != os.getuid():
        raise CaptureError("recorder has an unexpected owner")
    fields = path.read_text().rsplit(")", 1)[1].split()
    if fields[0] in ("Z", "X"):
        raise CaptureError("recorder is no longer running")
    return fields[19]


def _boot_id() -> str:
    return Path("/proc/sys/kernel/random/boot_id").read_text().strip()


@contextmanager
def _record_lock(paths: Paths):
    state_dir = _state_dir(paths, "record")
    with (state_dir / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield state_dir


def _record_state(state_dir: Path) -> dict:
    marker = state_dir / "recording"
    if not marker.exists():
        raise CaptureError("not recording")
    try:
        state = json.loads(marker.read_text())
        output = Path(state["output"])
        if output.parent.resolve() != state_dir.resolve():
            raise ValueError("output outside recording directory")
        if (not isinstance(state["start_ticks"], str)
                or not isinstance(state["boot_id"], str)):
            raise ValueError("invalid process identity")
        return state
    except (ValueError, KeyError, TypeError) as exc:
        raise CaptureError("invalid recording state; refusing to signal an unknown process") from exc


@contextmanager
def _recorder(state: dict):
    # Open the descriptor before verifying the start time. PID reuse between
    # validation and signaling cannot target an unrelated process through it.
    if state["boot_id"] != _boot_id():
        yield None
        return
    try:
        fd = os.pidfd_open(state["pid"])
    except ProcessLookupError:
        yield None
        return
    try:
        if select.select([fd], [], [], 0)[0]:
            yield None
            return
        try:
            identity = _process_identity(state["pid"])
        except FileNotFoundError:
            yield None
            return
        if identity != state["start_ticks"]:
            raise CaptureError("recorder PID was reused; refusing to signal it")
        yield fd
    finally:
        os.close(fd)


def record_start(
    options: RecordOptions, paths: Paths, services: CaptureServices
) -> CaptureResult:
    """Launch gpu-screen-recorder with its native options and persist identity."""
    child = None
    try:
        with _record_lock(paths) as state_dir:
            marker = state_dir / "recording"
            if marker.exists():
                return CaptureResult(False, error="already recording")
            command = ["gpu-screen-recorder"]
            if options.region:
                region = _select_region(options.region, services)
                if region is None:
                    return CaptureResult(True, cancelled=True)
                x, y, width, height = region
                command += ["-w", "region", "-region", f"{width}x{height}{x:+d}{y:+d}"]
                fps = 60
            else:
                monitors = _monitors(services)
                monitor = (next((item for item in monitors if item.get("name") == options.monitor), None)
                           if options.monitor else next((item for item in monitors if item.get("focused")), monitors[0]))
                if monitor is None:
                    raise CaptureError("recording monitor is unavailable")
                fps = max(1, round(float(monitor.get("refreshRate", 60))))
                command += ["-w", monitor["name"]]
            command += ["-f", str(fps), "-c", "mp4"]
            if options.sound:
                command += ["-a", "default_output"]
            extra = _config(paths).get("record", {}).get("extraArgs", [])
            if not isinstance(extra, list) or not all(isinstance(arg, str) for arg in extra):
                raise CaptureError("record.extraArgs must be an array of strings")
            output = state_dir / f"recording-{_stamp()}.mp4"
            command += [*extra, "-o", str(output)]
            child = services.start_detached(command)
            if not hasattr(child, "pid") or not hasattr(child, "poll"):
                raise CaptureError("recorder failed to start: launcher returned no process")
            time.sleep(0.05)
            if child.poll() is not None:
                raise CaptureError("recorder exited during startup")
            identity = _process_identity(child.pid)
            atomic_json(marker, {"pid": child.pid, "start_ticks": identity,
                                 "boot_id": _boot_id(), "output": str(output)})
            _notify(services, "Recording", "started")
            return CaptureResult(True, str(output), recording=True)
    except Exception as exc:
        if child is not None and hasattr(child, "poll") and child.poll() is None:
            # The launcher handle identifies this child even when persisting its
            # state failed; do not leave an unowned recorder running.
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if child is not None and hasattr(child, "pid"):
            _children.pop(child.pid, None)
        error = f"missing dependency: {exc}" if isinstance(exc, FileNotFoundError) else str(exc)
        return CaptureResult(False, error=error)


def record_pause(paths: Paths, services: CaptureServices) -> CaptureResult:
    """Toggle pause for the owned recorder without signaling other sessions."""
    try:
        with _record_lock(paths) as state_dir:
            state = _record_state(state_dir)
            with _recorder(state) as fd:
                if fd is None:
                    raise CaptureError("recorder is no longer running")
                signal.pidfd_send_signal(fd, signal.SIGUSR2)
            _notify(services, "Recording", "pause toggled")
            return CaptureResult(True)
    except Exception as exc:
        return CaptureResult(False, error=str(exc))


def record_stop(
    copy_to_clipboard: bool, paths: Paths, services: CaptureServices
) -> CaptureResult:
    """Stop the owned recorder, wait for finalization, and return its real file."""
    try:
        with _record_lock(paths) as state_dir:
            state = _record_state(state_dir)
            source = Path(state["output"])
            interrupted = False
            with _recorder(state) as fd:
                if fd is None:
                    interrupted = True
                else:
                    try:
                        signal.pidfd_send_signal(fd, signal.SIGINT)
                    except ProcessLookupError:
                        interrupted = True
                    poller = select.poll()
                    poller.register(fd, select.POLLIN)
                    if not poller.poll(10000):
                        return CaptureResult(False, str(source) if source.exists() else None,
                                             "recorder did not stop; recording state was retained")
            child = _children.get(state["pid"])
            if child is not None and (not interrupted or child.poll() is not None):
                _children.pop(state["pid"], None)
                child.wait()
            (state_dir / "recording").unlink(missing_ok=True)
            if interrupted or child is not None and child.returncode != 0:
                return CaptureResult(False, str(source) if source.exists() else None,
                                     "recording ended unexpectedly; any partial file was preserved")
            if not source.is_file() or source.stat().st_size == 0:
                return CaptureResult(False, error="recorder did not produce a nonempty video")
            if copy_to_clipboard and services.clipboard(source.resolve().as_uri()) != 0:
                return CaptureResult(False, str(source), "could not copy recording URI to clipboard")
            _notify(services, "Recording", "saved")
            return CaptureResult(True, str(source), recording=False)
    except Exception as exc:
        return CaptureResult(False, error=str(exc))


def record_toggle(paths: Paths, services: CaptureServices) -> CaptureResult:
    """Toggle recording on/off."""
    marker = _state_dir(paths, "record") / "recording"
    if marker.exists():
        return record_stop(True, paths, services)
    return record_start(RecordOptions(), paths, services)


def record_status(paths: Paths) -> dict:
    """Read the owned recorder's identity without signaling or changing state."""
    state_dir = paths.state_home / "zestify" / "record"
    status = {"recording": False, "path": None, "error": None}
    if not (state_dir / "recording").exists():
        return status
    try:
        state = _record_state(state_dir)
        status["path"] = state["output"]
        with _recorder(state) as fd:
            status["recording"] = fd is not None
        if not status["recording"]:
            status["error"] = "recording ended unexpectedly; any partial file was preserved"
    except Exception as exc:
        status["error"] = str(exc)
    return status
