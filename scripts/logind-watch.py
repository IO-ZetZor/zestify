#!/usr/bin/env python3
"""Translate logind PrepareForSleep D-Bus signals into JSON lines."""

from __future__ import annotations

import json
import re
import signal
import subprocess
import sys

MONITOR_COMMAND = [
    "dbus-monitor",
    "--system",
    "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'",
]

_BOOLEAN = re.compile(r"\bboolean\s+(true|false)\b")


def parse_event(line: str) -> bool | None:
    if "PrepareForSleep" not in line:
        return None
    match = _BOOLEAN.search(line)
    if not match:
        return None
    return match.group(1) == "true"


def emit(value: bool) -> None:
    print(json.dumps({"aboutToSleep": value}), flush=True)


def main() -> int:
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        process = subprocess.Popen(
            MONITOR_COMMAND,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except OSError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr, flush=True)
        return 1

    try:
        if process.stdout is None:
            return 1
        for line in process.stdout:
            if stopping:
                break
            value = parse_event(line)
            if value is not None:
                emit(value)
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
