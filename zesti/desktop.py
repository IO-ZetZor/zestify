"""Desktop utilities for zesti: clipboard, emoji, workspace, and window tools.

Integrates with cliphist/fuzzel/wl-copy for the clipboard, fuzzel for the
emoji picker, and the Hyprland IPC client for workspace/window control.
"""

from __future__ import annotations

import json
import re
import socket
import subprocess
import sys
from pathlib import Path
from typing import Callable, Mapping

from zesti.hypr import HyprClient
from zesti.paths import Paths, atomic_write


EMOJIS_FILE = Path(__file__).resolve().parent.parent / "data" / "emojis.txt"
EMOJI_URL = "https://www.unicode.org/Public/emoji/16.0/emoji-test.txt"
MAX_EMOJI_BYTES = 4 * 1024 * 1024

#: Safe resizer actions documented for `zesti window resizer`.
RESIZER_ACTIONS = frozenset({"resize", "move", "center", "float", "tiling"})


def _default_run(cmd, **kwargs):  # pragma: no cover - real subprocess path
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    return subprocess.run(cmd, **kwargs)


class DesktopError(Exception):
    """Raised when a desktop utility cannot complete."""


def _missing(name: str) -> int:
    print(f"zesti: missing dependency: {name}", file=sys.stderr)
    return 1


def clipboard_pick(delete: bool = False, run: Callable = _default_run) -> int:
    """Pick a clipboard entry via cliphist + fuzzel, then copy with wl-copy.

    With ``delete`` the chosen entry is removed from cliphist first.
    User cancellation (fuzzel exit 1 or empty choice) is a clean success.
    """
    try:
        res = run(["cliphist", "list"])
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "cliphist") or "cliphist")
    if res.returncode != 0:
        return 1
    if not res.stdout.strip():
        return 0
    try:
        res = run(["fuzzel", "--dmenu"], input=res.stdout)
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "fuzzel") or "fuzzel")
    if res.returncode == 1 or (res.returncode == 0 and not res.stdout.strip()):
        return 0  # cancelled
    if res.returncode != 0:
        return res.returncode
    choice = res.stdout
    try:
        decoded = run(["cliphist", "decode"], input=choice.encode("utf-8"), text=False)
        if decoded.returncode != 0:
            return decoded.returncode
        if delete:
            deleted = run(["cliphist", "delete"], input=choice)
            if deleted.returncode != 0:
                return deleted.returncode
        return run(["wl-copy"], input=decoded.stdout, text=False).returncode
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "wl-copy") or "wl-copy")


def emoji_list(paths: Paths) -> str:
    """Return the bundled emoji picker data as text."""
    cached = paths.state_home / "zestify" / "emojis.txt"
    try:
        content = cached.read_text(encoding="utf-8")
        if content.strip():
            return content
    except FileNotFoundError:
        pass
    return EMOJIS_FILE.read_text(encoding="utf-8")


def emoji_pick(paths: Paths, run: Callable = _default_run) -> int:
    """Pick an emoji via fuzzel and copy it with wl-copy."""
    emojis = emoji_list(paths)
    try:
        res = run(["fuzzel", "--dmenu"], input=emojis)
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "fuzzel") or "fuzzel")
    if res.returncode == 1 or (res.returncode == 0 and not res.stdout.strip()):
        return 0  # cancelled
    if res.returncode != 0:
        return res.returncode
    try:
        return run(["wl-copy", "--type", "text/plain"], input=res.stdout.strip().split()[0]).returncode
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "wl-copy") or "wl-copy")


def _fetch_emojis(url: str) -> str:
    from urllib.request import urlopen

    with urlopen(url, timeout=15) as response:
        content = response.read(MAX_EMOJI_BYTES + 1)
    if len(content) > MAX_EMOJI_BYTES:
        raise DesktopError("emoji response is too large")
    return content.decode("utf-8")


def _emoji_data(content: str) -> str:
    if not isinstance(content, str) or len(content.encode("utf-8")) > MAX_EMOJI_BYTES:
        raise DesktopError("invalid emoji response")
    result = []
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ";" in line:
            codepoints, _, entry = line.partition(";")
            qualification, _, description = entry.partition("#")
            if qualification.strip() != "fully-qualified":
                continue
            try:
                glyph = "".join(chr(int(value, 16)) for value in codepoints.split())
            except (ValueError, OverflowError) as exc:
                raise DesktopError("invalid Unicode emoji data") from exc
            name = re.sub(r"^\S+\s+E[\d.]+\s*", "", description.strip())
            line = glyph + (" " + name if name else "")
        # Reject HTML/error pages and text masquerading as picker data.
        glyph = line.split()[0]
        if not any(ord(char) >= 0x2300 or char in "#*0123456789" and "\u20e3" in glyph for char in glyph):
            raise DesktopError("invalid emoji data")
        result.append(line)
    if not result:
        raise DesktopError("emoji response is empty")
    return "\n".join(result) + "\n"


def emoji_fetch(paths: Paths, opener: Callable[[str], str] = _fetch_emojis) -> int:
    """Atomically refresh emoji data from ``opener`` into Zestify state."""
    try:
        content = _emoji_data(opener(EMOJI_URL))
        target = paths.state_home / "zestify" / "emojis.txt"
        atomic_write(target, content)
    except Exception as exc:  # noqa: BLE001 - network failure leaves data unchanged
        print(f"zesti: emoji fetch failed: {exc}", file=sys.stderr)
        return 1
    return 0


def toggle_workspace(
    name: str, config: Mapping[str, object], hypr: HyprClient
) -> int:
    """Toggle a configured workspace, falling back to togglespecialworkspace."""
    toggles = config.get("toggles", {}) if isinstance(config, dict) else {}
    if not isinstance(toggles, dict):
        print("zesti: workspace toggle: toggles must be an object", file=sys.stderr)
        return 2
    target = toggles.get(name)
    if target:
        parts = str(target).split()
        if not parts:
            return 2
        return 0 if hypr.dispatch(parts[0], *parts[1:]) else 1
    else:
        return 0 if hypr.dispatch("togglespecialworkspace", str(name)) else 1


def _windows(client: str, hypr: HyprClient) -> list[dict]:
    if client in ("active", "activewindow"):
        active = hypr.message("j/activewindow")
        return [active] if isinstance(active, dict) and re.fullmatch(r"0x[0-9a-fA-F]+", str(active.get("address", ""))) else []
    if len(client) > 256:
        raise ValueError("window pattern is too long")
    pattern = re.compile(client)
    windows = hypr.message("j/clients")
    if not isinstance(windows, list):
        raise DesktopError("invalid Hyprland client list")
    return [window for window in windows if isinstance(window, dict)
            and re.fullmatch(r"0x[0-9a-fA-F]+", str(window.get("address", "")))
            and any(pattern.search(str(window.get(key, ""))) for key in ("class", "title", "address"))]


def _monitor_rect(window: dict, hypr: HyprClient) -> tuple[int, int, int, int]:
    monitors = hypr.message("j/monitors")
    if not isinstance(monitors, list) or not all(isinstance(item, dict) for item in monitors):
        raise DesktopError("invalid Hyprland monitor list")
    monitor = next((item for item in monitors if item.get("id") == window.get("monitor")), None)
    if not monitor:
        raise DesktopError("window monitor is unavailable")
    scale = float(monitor.get("scale", 1))
    if scale <= 0:
        raise DesktopError("invalid monitor scale")
    width, height = int(monitor["width"]), int(monitor["height"])
    if int(monitor.get("transform", 0)) % 2:
        width, height = height, width
    return int(monitor["x"]), int(monitor["y"]), round(width / scale), round(height / scale)


def window_resize(client: str, action: str, width: int, height: int, hypr: HyprClient | None = None) -> int:
    """Resize a matching client; rejects unsafe dimensions/actions."""
    if action == "resize" and (width <= 0 or height <= 0):
        return 2
    if action not in RESIZER_ACTIONS:
        return 2
    try:
        hypr = hypr or HyprClient()
        windows = _windows(client, hypr)
        if not windows:
            raise DesktopError("no matching windows")
        for window in windows:
            selector = "address:" + window["address"]
            if action == "resize":
                ok = hypr.dispatch("resizewindowpixel", f"exact {width} {height},{selector}")
            elif action == "move":
                ok = hypr.dispatch("movewindowpixel", f"exact {width} {height},{selector}")
            elif action == "center":
                x, y, monitor_width, monitor_height = _monitor_rect(window, hypr)
                size = window.get("size", [width, height])
                x += max(0, (monitor_width - int(size[0])) // 2)
                y += max(0, (monitor_height - int(size[1])) // 2)
                ok = hypr.dispatch("movewindowpixel", f"exact {x} {y},{selector}")
            else:
                ok = hypr.dispatch("setfloating" if action == "float" else "settiled", selector)
            if not ok:
                raise DesktopError("window dispatcher failed")
        return 0
    except (re.error, ValueError) as exc:
        print(f"zesti: window resize: {exc}", file=sys.stderr)
        return 2
    except (OSError, DesktopError, KeyError, TypeError, IndexError) as exc:
        print(f"zesti: window resize: {exc}", file=sys.stderr)
        return 1


def window_pip(client: str, hypr: HyprClient | None = None) -> int:
    """Put a client into picture-in-picture mode."""
    try:
        hypr = hypr or HyprClient()
        windows = _windows(client, hypr)
        if not windows:
            raise DesktopError("no matching windows")
        for window in windows:
            selector = "address:" + window["address"]
            x, y, monitor_width, monitor_height = _monitor_rect(window, hypr)
            size = window.get("size", [16, 9])
            ratio = max(0.25, min(4, int(size[0]) / max(1, int(size[1]))))
            width = max(1, min(480, monitor_width - 48))
            height = max(1, min(round(width / ratio), monitor_height - 48))
            width = min(width, round(height * ratio))
            commands = [("setfloating", selector),
                        ("resizewindowpixel", f"exact {width} {height},{selector}"),
                        ("movewindowpixel", f"exact {x + monitor_width - width - 24} {y + monitor_height - height - 24},{selector}")]
            if not window.get("pinned", False):
                commands.append(("pin", selector))
            for command, arguments in commands:
                if not hypr.dispatch(command, arguments):
                    raise DesktopError("picture-in-picture dispatcher failed")
        return 0
    except (re.error, ValueError) as exc:
        print(f"zesti: window pip: {exc}", file=sys.stderr)
        return 2
    except (OSError, DesktopError, KeyError, TypeError, IndexError) as exc:
        print(f"zesti: window pip: {exc}", file=sys.stderr)
        return 1


def window_watch(socket_path: Path | None = None, output=None) -> int:
    """Stream window lifecycle events as newline-delimited JSON until stopped."""
    output = output or sys.stdout
    try:
        path = socket_path or HyprClient().socket_path.with_name(".socket2.sock")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.connect(str(path))
            with connection.makefile("rb") as stream:
                while True:
                    line = stream.readline(65537)
                    if not line:
                        return 0
                    if len(line) > 65536:
                        raise DesktopError("window event is too large")
                    event, separator, data = line.decode("utf-8", "replace").rstrip("\n").partition(">>")
                    if separator and event in ("openwindow", "closewindow", "activewindow", "activewindowv2", "windowtitle", "windowtitlev2", "movewindow", "movewindowv2", "changefloatingmode"):
                        print(json.dumps({"event": event, "data": data}), file=output, flush=True)
    except KeyboardInterrupt:
        return 0
    except (OSError, DesktopError) as exc:
        print(f"zesti: window watch: {exc}", file=sys.stderr)
        return 1
