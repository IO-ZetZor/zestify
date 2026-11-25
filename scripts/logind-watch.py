#!/usr/bin/env python3
"""Watch logind and hold a sleep delay inhibitor until the lock is secure."""

from __future__ import annotations

import json
import os
import re
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

MONITOR_COMMAND = [
    "dbus-monitor",
    "--system",
    "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'",
]

_BOOLEAN = re.compile(r"\bboolean\s+(true|false)\b")


def lock_before_sleep() -> bool:
    directory = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    try:
        config = json.loads((directory / "zestify/config.json").read_text())
        return config.get("session", {}).get("lockBeforeSleep", True) is not False
    except (OSError, ValueError, AttributeError):
        return True


class DelayInhibitor:
    def __init__(self):
        self.process = None
        self.retry_at = 0.0

    def acquire(self):
        if self.process is not None and self.process.poll() is None:
            return
        if time.monotonic() < self.retry_at:
            return
        self.release()
        self.retry_at = time.monotonic() + 30
        try:
            self.process = subprocess.Popen(
                ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Zestify",
                 "--why=Cover all outputs with the session lock", sys.executable, "-u", "-c",
                 "import sys; print('ready', flush=True); sys.stdin.read()"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            ready, _, _ = select.select([self.process.stdout], [], [], 2)
            if not ready or self.process.stdout.readline().strip() != b"ready":
                self.release()
                print("zestify: could not acquire the logind sleep delay inhibitor", file=sys.stderr, flush=True)
        except OSError as error:
            self.release()
            print("zestify: sleep inhibitor: " + str(error), file=sys.stderr, flush=True)

    def release(self):
        process, self.process = self.process, None
        if process is None:
            return
        if process.stdin:
            process.stdin.close()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        if process.stdout:
            process.stdout.close()


def handle_sleep(value: bool, inhibitor: DelayInhibitor) -> None:
    emit(value)
    if not value:
        inhibitor.release()
        inhibitor.retry_at = 0
        if lock_before_sleep():
            inhibitor.acquire()
        return
    if not lock_before_sleep():
        inhibitor.release()
        return
    try:
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("lock.py"))],
                                capture_output=True, text=True, timeout=4)
        if result.returncode == 0:
            inhibitor.release()
        else:
            print("zestify: lock before sleep failed: " + result.stderr.strip(), file=sys.stderr, flush=True)
    except (OSError, subprocess.TimeoutExpired) as error:
        # Keep the delay until logind's maximum expires. Never unlock on failure.
        print("zestify: lock before sleep failed: " + str(error), file=sys.stderr, flush=True)


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
        )
    except OSError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr, flush=True)
        return 1

    inhibitor = DelayInhibitor()
    sleeping = False
    buffer = ""
    event = ""
    try:
        if process.stdout is None:
            return 1
        while not stopping:
            if not sleeping:
                if lock_before_sleep():
                    inhibitor.acquire()
                else:
                    inhibitor.release()
            ready, _, _ = select.select([process.stdout], [], [], 0.5)
            if not ready:
                continue
            chunk = os.read(process.stdout.fileno(), 8192)
            if not chunk:
                break
            buffer += chunk.decode("utf-8", errors="replace")
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                if line.startswith("signal "):
                    event = line
                else:
                    event += " " + line
                value = parse_event(event)
                if value is not None:
                    sleeping = value
                    handle_sleep(value, inhibitor)
                    event = ""
    finally:
        inhibitor.release()
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        if process.stdout:
            process.stdout.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
