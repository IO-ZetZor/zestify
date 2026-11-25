#!/usr/bin/env python3
"""Emit cava frames: ordinary byte bars or timestamped fixed-gain party JSON."""

import argparse
from contextlib import ExitStack
import json
import os
import re
import signal
import struct
import subprocess
import sys
import tempfile
import time

BAR_COUNT = 32


def set_option(lines, section_name, key, value):
    """Update owned analysis settings without rewriting input routing."""
    section = ""
    insertion = None
    replaced = False
    for index, line in enumerate(lines):
        header = re.match(r"\s*\[([^]]+)\]", line)
        if header:
            section = header.group(1).strip().lower()
            if section == section_name:
                insertion = index + 1
        elif section == section_name and re.match(r"\s*" + re.escape(key) + r"\s*=", line, re.I):
            lines[index] = f"{key} = {value}"
            replaced = True
    if not replaced:
        if insertion is None:
            lines.extend(["", f"[{section_name}]", f"{key} = {value}"])
        else:
            lines.insert(insertion, f"{key} = {value}")


def party_config(text):
    """Fixed-gain, high-resolution spectrum; display normalization lives in QML.

    Preserve the input backend/source. The temporary analysis configuration
    owns its frame format so user visualiser settings cannot misalign reads.
    """
    lines = text.splitlines()
    for section, settings in {
        "general": {"bars": 32, "framerate": 60, "autosens": 0, "sensitivity": 100},
        "output": {"method": "raw", "channels": "stereo", "bit_format": 16,
                   "raw_target": "/dev/stdout"},
        "smoothing": {"noise_reduction": 0, "monstercat": 0, "waves": 0},
    }.items():
        for key, value in settings.items():
            set_option(lines, section, key, value)
    return "\n".join(lines) + "\n"


class FrameClock:
    """Estimate the 60Hz analysis cadence despite batched pipe delivery.

    This is not a PCM timestamp. Re-anchor after a stall; small scheduling
    differences are corrected gradually instead of inventing 0ms beat gaps.
    """
    def __init__(self):
        self.previous = None

    def advance(self, received):
        expected = received if self.previous is None else self.previous + 1000 / 60
        if abs(received - expected) > 100:
            value = received
        else:
            value = expected + (received - expected) * 0.02
        if self.previous is not None:
            value = max(self.previous + 0.001, value)
        self.previous = value
        return value


def party_packet(frame, sequence, clock=None):
    # Cava's binary raw format writes host-endian uint16 values.
    levels = [value / 65535 for value in struct.unpack("=32H", frame)]
    received = time.monotonic_ns() / 1_000_000
    return {"version": 1, "levels": levels, "sequence": sequence,
            "time": clock.advance(received) if clock else received,
            "receivedAt": received,
            "emittedAt": time.time_ns() / 1_000_000, "fixedGain": True}


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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--party", action="store_true", help="preserve fast beat transients")
    parser.add_argument("--config", help="explicit capture configuration (otherwise use the installed config)")
    args = parser.parse_args()
    # Quickshell stops the monitor with SIGTERM. Unwind the process and temp
    # config instead of leaving either behind when the overlay closes.
    signal.signal(signal.SIGTERM, lambda _signal, _frame: sys.exit(0))
    config = args.config or os.path.expanduser("~/.config/zestify/cava.conf")
    if not os.path.exists(config):
        # Fall back to the repo config for development.
        config = os.path.join(os.path.dirname(__file__), "..", "config", "cava.conf")
        config = os.path.normpath(config)

    with ExitStack() as cleanup:
        if args.party:
            with open(config) as source:
                text = party_config(source.read())
            temporary = cleanup.enter_context(tempfile.NamedTemporaryFile(mode="w", suffix=".conf"))
            temporary.write(text)
            temporary.flush()
            config = temporary.name
        proc = subprocess.Popen(
            ["cava", "-p", config],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
        try:
            clock = FrameClock()
            for sequence, frame in enumerate(read_frames(proc.stdout, BAR_COUNT * (2 if args.party else 1))):
                if args.party:
                    print(json.dumps(party_packet(frame, sequence, clock), separators=(",", ":")), flush=True)
                else:
                    print(";".join(str(value) for value in frame), flush=True)
        except (BrokenPipeError, OSError):
            pass
        finally:
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            proc.stdout.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
