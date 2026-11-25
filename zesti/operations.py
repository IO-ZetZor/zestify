"""Operational commands for zesti: doctor, install, update, and repo scripts.

Subprocess invocation uses argument arrays only. Update is strictly
fast-forward-only and never resets or discards user changes.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Literal, Mapping

from zesti.paths import Paths


class DoctorReport(dict):
    """Diagnostics report: required/optional tool availability and path state."""

    def __init__(self, **kwargs):
        super().__init__(kwargs)


REQUIRED_TOOLS = ("qs", "python3", "ffmpeg", "brightnessctl", "wpctl")

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
    kwargs.setdefault("text", True)
    return subprocess.run(cmd, **kwargs)


def doctor(paths: Paths, *, lookup: Callable = shutil.which, json_output: bool = False):
    """Check required and optional tooling plus writable XDG paths.

    Returns a :class:`DoctorReport` (a dict) unless ``json_output`` is set, in
    which case a JSON string is returned.
    """
    required_missing = [t for t in REQUIRED_TOOLS if not lookup(t)]
    optional_missing = [t for t in OPTIONAL_TOOLS if not lookup(t)]

    path_problems = []
    for name, p in (
        ("config", paths.config_file.parent),
        ("state", paths.state_home / "zestify"),
        ("cache", paths.cache_home / "zestify"),
    ):
        try:
            p.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryFile(dir=p):
                pass
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
    def git(*args):
        return runner(["git", "-C", str(repo), *args], capture_output=True, text=True)

    def state(name, query):
        return services[name]() if name in services else query()

    try:
        attached = state("is_attached", lambda: git("rev-parse", "--is-inside-work-tree").stdout.strip() == "true")
        if not attached:
            print("zesti: update: not a Git worktree; refusing", file=sys.stderr)
            return 1
        is_detached = state("is_detached", lambda: git("symbolic-ref", "--quiet", "HEAD").returncode != 0)
        status = None if "is_dirty" in services else git("status", "--porcelain")
        if status is not None and status.returncode != 0:
            print("zesti: update: cannot inspect worktree; refusing", file=sys.stderr)
            return 1
        is_dirty = state("is_dirty", lambda: bool(status.stdout.strip()))
        has_upstream = state("has_upstream", lambda: git("rev-parse", "--verify", "@{upstream}").returncode == 0)
    except OSError as exc:
        print(f"zesti: update: {exc}", file=sys.stderr)
        return 1

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

    from zesti import shell

    was_running = state("shell_was_running", lambda: bool(shell.list_instances()))

    res = runner(["git", "-C", str(repo), "pull", "--ff-only"])
    rc = getattr(res, "returncode", res) if not isinstance(res, int) else res
    if rc != 0:
        print("zesti: update: fast-forward pull failed", file=sys.stderr)
        return rc

    # Reinstall and restart only if the shell was running.
    rc = install(repo, ["--no-start"], runner)
    if rc != 0:
        return rc
    if was_running:
        return services.get("restart_shell", shell.shell_restart)()
    return 0
