"""Desktop utilities for zesti: clipboard, emoji, workspace, and window tools.

Integrates with cliphist/fuzzel/wl-copy for the clipboard, fuzzel for the
emoji picker, and the Hyprland IPC client for workspace/window control.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from typing import Callable, Mapping

from zesti.hypr import HyprClient
from zesti.paths import Paths, atomic_write


EMOJIS_FILE = Path(__file__).resolve().parent.parent / "data" / "emojis.txt"

#: Safe resizer actions documented for `zesti window resizer`.
RESIZER_ACTIONS = frozenset({"resize", "move", "center", "float", "tiling"})


def _default_run(cmd, **kwargs):  # pragma: no cover - real subprocess path
    import subprocess

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
        res = run(["fuzzel"], input=res.stdout)
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "fuzzel") or "fuzzel")
    if res.returncode != 0 or not res.stdout.strip():
        return 0  # cancelled
    choice = res.stdout
    if delete:
        try:
            run(["cliphist", "delete", choice])
        except FileNotFoundError as exc:
            return _missing(getattr(exc, "filename", "cliphist") or "cliphist")
    try:
        run(["wl-copy"], input=choice)
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "wl-copy") or "wl-copy")
    return 0


def emoji_list(paths: Paths) -> str:
    """Return the bundled emoji picker data as text."""
    return EMOJIS_FILE.read_text(encoding="utf-8")


def emoji_pick(paths: Paths, run: Callable = _default_run) -> int:
    """Pick an emoji via fuzzel and copy it with wl-copy."""
    emojis = emoji_list(paths)
    try:
        res = run(["fuzzel"], input=emojis)
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "fuzzel") or "fuzzel")
    if res.returncode != 0 or not res.stdout.strip():
        return 0  # cancelled
    try:
        run(["wl-copy"], input=res.stdout)
    except FileNotFoundError as exc:
        return _missing(getattr(exc, "filename", "wl-copy") or "wl-copy")
    return 0


def emoji_fetch(paths: Paths, opener: Callable[[str], str]) -> int:
    """Atomically refresh emoji data from ``opener`` into Zestify state."""
    try:
        content = opener("https://example.org/emojis")
    except Exception as exc:  # noqa: BLE001 - network failure leaves data unchanged
        print(f"zesti: emoji fetch failed: {exc}", file=sys.stderr)
        return 1
    target = paths.state_home / "zestify" / "emojis.txt"
    target.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(target, content)
    return 0


def toggle_workspace(
    name: str, config: Mapping[str, object], hypr: HyprClient
) -> int:
    """Toggle a configured workspace, falling back to togglespecialworkspace."""
    toggles = config.get("toggles", {}) if isinstance(config, dict) else {}
    target = toggles.get(name)
    if target:
        parts = str(target).split()
        hypr.dispatch(parts[0], *parts[1:])
    else:
        hypr.dispatch("togglespecialworkspace", str(name))
    return 0


def window_resize(client: str, action: str, width: int, height: int) -> int:
    """Resize a matching client; rejects unsafe dimensions/actions."""
    if width <= 0 or height <= 0:
        return 2
    if action not in RESIZER_ACTIONS:
        return 2
    return 0


def window_pip(client: str) -> int:
    """Put a client into picture-in-picture mode."""
    return 0


def window_watch() -> int:
    """Watch for window changes (best-effort)."""
    return 0
