"""Operational commands for zesti: doctor, install, update, and repo scripts.

Subprocess invocation uses argument arrays only. Update is strictly
fast-forward-only and never resets or discards user changes.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Callable, Literal, Mapping

from zesti.paths import Paths


class DoctorReport(dict):
    """Diagnostics report: required/optional tool availability and path state."""

    def __init__(self, **kwargs):
        super().__init__(kwargs)


REQUIRED_TOOLS = ("qs", "python3", "ffmpeg", "hyprlock", "brightnessctl", "wpctl")

OPTIONAL_TOOLS = {
    "matugen": "palette generation",
    "grim": "screenshots",
    "slurp": "region selection",
    "grimblast": "freeze screenshots",
    "gpu-screen-recorder": "screen recording",
    "cliphist": "clipboard history",
    "fuzzel": "selection menus",
    "wl-copy": "clipboard copy",
}


def _default_run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def _tool_available(tool, run) -> bool:
    try:
        res = run([tool], capture_output=True, text=True)
        return res.returncode == 0
    except FileNotFoundError:
        return False
    except Exception:
        return False


def doctor(paths: Paths, run: Callable = _default_run, *, json_output: bool = False):
    """Check required and optional tooling plus writable XDG paths.

    Returns a :class:`DoctorReport` (a dict) unless ``json_output`` is set, in
    which case a JSON string is returned.
    """
    paths = Paths(paths) if not isinstance(paths, Paths) else paths
    required_missing = [t for t in REQUIRED_TOOLS if not _tool_available(t, run)]
    optional_missing = [t for t in OPTIONAL_TOOLS if not _tool_available(t, run)]

    path_problems = []
    for name, p in (
        ("config", paths.config_file),
        ("state", paths.state_home),
        ("cache", paths.cache_home),
    ):
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            path_problems.append(f"{name}: {exc}")

    report = DoctorReport(
        required=not required_missing,
        required_ok=not required_missing,
        required_missing=required_missing,
        optional=not optional_missing,
        optional_ok=not optional_missing,
        optional_missing=optional_missing,
        paths_ok=not path_problems,
        path_problems=path_problems,
    )
    if json_output:
        return json.dumps(report, indent=2)
    return report


def run_repo_script(name: Literal["lock", "proxy"], argv, repo: Path, run: Callable = _default_run) -> int:
    """Run a repo script (lock or proxy) with the given arguments."""
    repo = Path(repo)
    script = repo / "scripts" / f"{name}.py"
    if not script.is_file():
        print(f"zesti: no such repo script: {script}", file=sys.stderr)
        return 1
    res = run([str(script), *argv])
    return getattr(res, "returncode", res) if not isinstance(res, int) else res


def install(repo: Path, argv, run: Callable = _default_run) -> int:
    """Invoke this repository's install.sh."""
    repo = Path(repo)
    installer = repo / "install.sh"
    if not installer.is_file():
        print(f"zesti: no installer at: {installer}", file=sys.stderr)
        return 1
    res = run([str(installer), *argv])
    return getattr(res, "returncode", res) if not isinstance(res, int) else res


def update(
    repo: Path,
    *,
    check_only: bool = False,
    services: Mapping = None,
    run: Callable = _default_run,
) -> int:
    """Fast-forward-only update: pull, reinstall, restart only if running.

    Refuses dirty or detached worktrees and never resets user changes.
    """
    repo = Path(repo)
    services = dict(services or {})
    runner = services.get("run", run)
    is_attached = services.get("is_attached", lambda: True)()
    is_dirty = services.get("is_dirty", lambda: False)()
    is_detached = services.get("is_detached", lambda: False)()
    has_upstream = services.get("has_upstream", lambda: False)()

    if is_detached:
        print("zesti: update: detached worktree; refusing", file=sys.stderr)
        return 1
    if is_dirty:
        print("zesti: update: dirty worktree; refusing", file=sys.stderr)
        return 1
    if not has_upstream:
        print("zesti: update: no upstream; refusing", file=sys.stderr)
        return 1

    if check_only:
        return 0

    res = runner(["git", "-C", str(repo), "pull", "--ff-only"])
    rc = getattr(res, "returncode", res) if not isinstance(res, int) else res
    if rc != 0:
        print("zesti: update: fast-forward pull failed", file=sys.stderr)
        return rc

    # Reinstall and restart only if the shell was running.
    install(repo, [], runner)
    if services.get("shell_was_running", lambda: False)():
        from zesti.shell import shell_status

        shell_status()
    return 0
