"""Quickshell lifecycle and IPC handlers for zesti.

All subprocess/sleep/kill operations are injected through ``run``/``sleep``/
``kill`` callables so tests can drive behavior without touching the desktop.
Quickshell config name and IPC target remain exactly ``zestify``.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
from argparse import Namespace
from time import monotonic, sleep
from typing import Callable, Mapping, Sequence

from zesti.paths import Paths

# Exit codes mirrored from zesti.cli.
EXIT_OK = 0
EXIT_RUNTIME = 1

CONFIG = "zestify"
IPC_TARGET = "zestify"


def _qs_bin() -> str:
    return os.environ.get("QS_BIN", "qs")


def _default_run(cmd: Sequence[str], **kwargs) -> str:
    # The first element is expected to be "qs"; honor QS_BIN like the legacy
    # bin/zestify wrapper did.
    if cmd and cmd[0] == "qs":
        cmd = [_qs_bin(), *cmd[1:]]
    completed = subprocess.run(
        list(cmd), text=True, capture_output=True, **kwargs
    )
    if completed.returncode and completed.stderr:
        print(completed.stderr.strip(), file=sys.stderr)
    return completed.stdout


def _checked_run(run: Callable[..., str], cmd: Sequence[str], **kwargs) -> tuple[str, int]:
    try:
        return run(cmd, check=True, **kwargs), EXIT_OK
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or str(exc)).strip()
        print(f"zesti: {detail}", file=sys.stderr)
        return "", EXIT_RUNTIME


def _default_sleep(seconds: float) -> None:
    sleep(seconds)


def _default_kill(pid: int, sig: int) -> None:
    os.kill(pid, sig)


def list_instances(
    run: Callable[..., str] = _default_run,
) -> list[dict]:
    """Return the list of running Quickshell ``zestify`` instances.

    Only JSON output or the exact "No running instances" text is parsed;
    anything else yields an empty list (never crashes the caller).
    """
    out = run(["qs", "list", "-c", CONFIG, "--json"], check=False)
    text = out.strip()
    if text == "No running instances" or not text:
        return []
    try:
        data = json.loads(text)
    except (ValueError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    return [entry for entry in data if isinstance(entry, dict)]


_ZESTI_BIN = os.path.realpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "zesti")
)


def start_shell(
    args: Namespace,
    run: Callable[..., str] = _default_run,
    sleep: Callable[[float], None] = _default_sleep,
) -> int:
    """Start the Quickshell ``zestify`` instance detached.

    An already-running instance counts as success (no duplicate launch).
    Passes ``ZESTI_BIN`` into Quickshell's environment so QML-side
    :mod:`zesti.wallpaper` can find the ``zesti`` executable via
    ``Quickshell.env("ZESTI_BIN")`` even when PATH is minimal.
    """
    instances = list_instances(run=run)
    if instances:
        return EXIT_OK
    env = dict(os.environ)
    env["ZESTI_BIN"] = _ZESTI_BIN
    env["ZESTI_DESKTOP_CONFIG_HOME"] = str(Paths.from_env(env).config_home)
    cmd = ["qs", "-c", CONFIG, "-n"]
    if not getattr(args, "foreground", False):
        cmd.append("-d")
    if getattr(args, "log_rules", None):
        cmd.extend(["--log-rules", args.log_rules])
    out, status = _checked_run(run, cmd, env=env)
    print(out, end="")
    return status


def stop_shell(
    run: Callable[..., str] = _default_run,
    *,
    timeout: float = 5.0,
    sleep: Callable[[float], None] = _default_sleep,
    kill: Callable[[int, int], None] = _default_kill,
) -> int:
    """Stop every running instance: SIGTERM each, then SIGKILL after timeout."""
    instances = list_instances(run=run)
    pids = [int(entry["pid"]) for entry in instances if "pid" in entry]
    if not pids:
        return EXIT_OK

    for pid in pids:
        try:
            kill(pid, signal.SIGTERM)
        except OSError:
            pass

    deadline = monotonic() + timeout
    while monotonic() < deadline:
        remaining = [
            int(entry["pid"])
            for entry in list_instances(run=run)
            if "pid" in entry
        ]
        if not remaining:
            return EXIT_OK
        sleep(min(0.25, max(0.0, deadline - monotonic())))

    for pid in pids:
        try:
            kill(pid, signal.SIGKILL)
        except OSError:
            pass
    return EXIT_OK


def shell_status(
    run: Callable[..., str] = _default_run,
    *,
    json_output: bool = False,
) -> int:
    """Report shell status via the ``ping`` IPC call."""
    out = run(
        ["qs", "ipc", "-c", CONFIG, "call", IPC_TARGET, "ping"],
        check=False,
    )
    text = out.strip()
    if json_output:
        running = text == "pong"
        print(json.dumps({"ok": running, "running": running, "ping": text}))
        return EXIT_OK if running else EXIT_RUNTIME
    else:
        print(text)
    return EXIT_OK if text == "pong" else EXIT_RUNTIME


def shell_open(
    args: Namespace,
    run: Callable[..., str] = _default_run,
) -> int:
    surface = getattr(args, "SURFACE", None) or getattr(args, "surface", None)
    if not surface:
        return EXIT_RUNTIME
    _, status = _checked_run(
        run,
        [
            "qs",
            "ipc",
            "-c",
            CONFIG,
            "call",
            IPC_TARGET,
            "openSurface",
            surface,
        ],
    )
    return status


def shell_show(args: Namespace, run: Callable[..., str] = _default_run) -> int:
    out = run(["qs", "ipc", "-c", CONFIG, "show"], check=False)
    print(out, end="")
    return EXIT_OK


def shell_call(
    args: Namespace,
    run: Callable[..., str] = _default_run,
) -> int:
    target = getattr(args, "target", IPC_TARGET)
    function = getattr(args, "function", None)
    arg = getattr(args, "arg", None) or []
    cmd = ["qs", "ipc", "-c", CONFIG, "call", target, function]
    cmd.extend(arg)
    out = run(cmd, check=False)
    print(out, end="")
    return EXIT_OK


def shell_logs(
    args: Namespace,
    run: Callable[..., str] = _default_run,
) -> int:
    out = run(["qs", "-c", CONFIG, "log"], check=False)
    print(out, end="")
    return EXIT_OK


def shell_restart(
    run: Callable[..., str] = _default_run,
    *,
    timeout: float = 5.0,
    sleep: Callable[[float], None] = _default_sleep,
    kill: Callable[[int, int], None] = _default_kill,
) -> int:
    """Restart: stop every instance, wait for an empty list, then launch."""
    stop_shell(run=run, timeout=timeout, sleep=sleep, kill=kill)
    # Wait until no instances remain before launching.
    deadline = monotonic() + timeout
    while monotonic() < deadline:
        if not list_instances(run=run):
            break
        sleep(min(0.25, max(0.0, deadline - monotonic())))
    env = dict(os.environ)
    env["ZESTI_BIN"] = _ZESTI_BIN
    env["ZESTI_DESKTOP_CONFIG_HOME"] = str(Paths.from_env(env).config_home)
    out, status = _checked_run(run, ["qs", "-c", CONFIG, "-n", "-d"], env=env)
    print(out, end="")
    return status
