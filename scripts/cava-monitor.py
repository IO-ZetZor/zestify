#!/usr/bin/env python3
"""Read cava raw (binary) output and emit semicolon-separated bar values.

cava in raw mode writes one byte per bar (0-255) per update cycle.
This script reads those bytes and prints them as text so QML can parse
them with SplitParser.
"""

import os
import subprocess
import sys

BAR_COUNT = 32


def read_frames(stream, bar_count=BAR_COUNT):
    """Yield complete cava frames while preserving bytes across short reads."""
    buffered = bytearray()
    while True:
        chunk = stream.read(bar_count)
        if not chunk:
            return
        buffered.extend(chunk)
        while len(buffered) >= bar_count:
            yield bytes(buffered[:bar_count])
            del buffered[:bar_count]


def main() -> int:
    config = os.path.expanduser("~/.config/zestify/cava.conf")
    if not os.path.exists(config):
        # Fall back to the repo config for development.
        config = os.path.join(os.path.dirname(__file__), "..", "config", "cava.conf")
        config = os.path.normpath(config)

    proc = subprocess.Popen(
        ["cava", "-p", config],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    try:
        for frame in read_frames(proc.stdout):
            print(";".join(str(value) for value in frame), flush=True)
    except (BrokenPipeError, OSError):
        pass
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
