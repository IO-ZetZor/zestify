"""Session controls for zesti: volume, mic, brightness, and config.

Subprocess invocation uses argument arrays only. The OSD IPC is best-effort
and never makes a control command fail.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Callable, Sequence

from zesti.paths import Paths


AUDIO_SINK = "@DEFAULT_AUDIO_SINK"
AUDIO_SOURCE = "@DEFAULT_AUDIO_SOURCE"


class Result:
    def __init__(self, returncode, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def _default_run(cmd: Sequence[str], **kwargs) -> Result:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def _parse(command, *args):
    value = None
    run = _default_run
    if len(args) == 1:
        if callable(args[0]):
            run = args[0]
        else:
            value = args[0]
    elif len(args) >= 2:
        value, run = args[0], args[1]
    return command, value, run


def _wpctl(args, run) -> int:
    try:
        res = run(["wpctl", *args])
        return res.returncode
    except FileNotFoundError:
        print("zesti: missing dependency: wpctl", file=sys.stderr)
        return 1


def _brightnessctl(args, run) -> int:
    try:
        res = run(["brightnessctl", *args])
        return res.returncode
    except FileNotFoundError:
        print("zesti: missing dependency: brightnessctl", file=sys.stderr)
        return 1


def volume(command, *args) -> int:
    """Control volume: up/down/mute/set N (exact 5% steps, exact set values)."""
    command, value, run = _parse(command, *args)
    if command == "up":
        return _wpctl(["set-volume", AUDIO_SINK, "5%+"], run)
    if command == "down":
        return _wpctl(["set-volume", AUDIO_SINK, "5%-"], run)
    if command == "mute":
        return _wpctl(["set-mute", AUDIO_SINK, "toggle"], run)
    if command == "set":
        if value is None:
            return 2
        return _wpctl(["set-volume", AUDIO_SINK, f"{int(value)}%"], run)
    print(f"zesti: volume: unknown command {command!r}", file=sys.stderr)
    return 2


def mic(command, *args) -> int:
    """Control the microphone: up/down/mute."""
    command, value, run = _parse(command, *args)
    if command == "up":
        return _wpctl(["set-volume", AUDIO_SOURCE, "5%+"], run)
    if command == "down":
        return _wpctl(["set-volume", AUDIO_SOURCE, "5%-"], run)
    if command == "mute":
        return _wpctl(["set-mute", AUDIO_SOURCE, "toggle"], run)
    print(f"zesti: mic: unknown command {command!r}", file=sys.stderr)
    return 2


def brightness(command, *args) -> int:
    """Control brightness: up/down/set N (normalized percent values)."""
    command, value, run = _parse(command, *args)
    if command == "up":
        return _brightnessctl(["s", "5%+"], run)
    if command == "down":
        return _brightnessctl(["s", "5%-"], run)
    if command == "set":
        if value is None:
            return 2
        return _brightnessctl(["s", f"{int(value)}%"], run)
    print(f"zesti: brightness: unknown command {command!r}", file=sys.stderr)
    return 2


def config_command(action: str, paths: Paths, **kwargs) -> tuple[int, str]:
    """Inspect or validate the user config. Returns (rc, output)."""
    if action == "path":
        return 0, str(paths.config_file)
    if action == "show":
        try:
            return 0, paths.config_file.read_text(encoding="utf-8")
        except FileNotFoundError:
            return 1, "no config file"
    if action == "validate":
        try:
            json.loads(paths.config_file.read_text(encoding="utf-8"))
            return 0, "config is valid"
        except FileNotFoundError:
            return 1, "no config file"
        except json.JSONDecodeError:
            return 1, "config is not valid JSON"
    if action == "edit":
        editor = shlex.split(os.environ.get("EDITOR", "editor"))
        if not editor:
            return 1, "no editor configured"
        try:
            result = subprocess.run([*editor, str(paths.config_file)], check=False)
        except FileNotFoundError:
            return 1, f"missing editor: {editor[0]}"
        return result.returncode, ""
    print(f"zesti: config: unknown action {action!r}", file=sys.stderr)
    return 2, ""
