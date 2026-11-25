#!/usr/bin/env python3
"""Measure known PCM kick writes -> production detection -> offscreen frame swap.

Uses an isolated FIFO and D-Bus session; no audio is played aloud. The FIFO
measurement includes Cava analysis/capture and scheduling, not speaker latency.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import struct
import subprocess
import tempfile
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/zestify-party-latency.json"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    writes = []
    errors = []
    with tempfile.TemporaryDirectory(prefix="zestify-party-latency-") as scratch:
        directory = Path(scratch)
        shutil.copytree(repo / "shell", directory / "shell")
        source = (repo / "tests/quickshell/party-latency.qml").read_text()
        (directory / "shell/shell.qml").write_text(source.replace("../../shell/", ""))
        fifo = directory / "audio.fifo"
        os.mkfifo(fifo)
        config = directory / "cava.conf"
        config.write_text(f"[input]\nmethod=fifo\nsource={fifo}\nsample_rate=44100\nsample_bits=16\n")
        # Existing VisualiserLevels uses its normal command; the wrapper only
        # supplies an isolated input config to the production monitor.
        wrapper = directory / "python-wrapper"
        wrapper.write_text(f"#!/bin/sh\nexec python3 \"$@\" --config '{config}'\n")
        wrapper.chmod(0o755)
        env = dict(os.environ, PARTY_LATENCY_SCRIPTS=str(repo / "scripts"),
                   PARTY_LATENCY_PYTHON=str(wrapper), QT_QPA_PLATFORM="offscreen",
                   QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl")
        env.pop("WAYLAND_DISPLAY", None)
        process = subprocess.Popen(["dbus-run-session", "qs", "-p", str(directory / "shell/shell.qml"),
                                    "--no-color"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def write_audio():
            try:
                # Nonblocking open keeps a failed QML launch from hanging tests.
                deadline = time.monotonic() + 5
                while True:
                    try:
                        descriptor = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
                        os.set_blocking(descriptor, True)
                        break
                    except OSError:
                        if time.monotonic() > deadline:
                            raise RuntimeError("Cava did not open the impulse FIFO")
                        time.sleep(0.02)
                with os.fdopen(descriptor, "wb", buffering=0) as stream:
                    started = time.monotonic()
                    for chunk in range(800):
                        target = started + chunk * 0.01
                        time.sleep(max(0, target - time.monotonic()))
                        kick = (chunk - 100) // 80
                        age = (chunk - 100) % 80
                        active = 0 <= kick < 8 and age < 12
                        values = []
                        for sample in range(441):
                            t = age * 0.01 + sample / 44100
                            value = int(22000 * math.sin(2 * math.pi * 85 * t)
                                        * min(1, t / 0.002) * math.exp(-t / 0.04)) if active else 0
                            values.extend([value, value])
                        if active and age == 0:
                            writes.append(time.time_ns() / 1_000_000)
                        stream.write(struct.pack("<882h", *values))
            except Exception as error:
                errors.append(str(error))

        writer = threading.Thread(target=write_audio)
        writer.start()
        try:
            stdout, stderr = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            process.terminate()
            stdout, stderr = process.communicate(timeout=3)
            errors.append("rendered latency check timed out")
        writer.join(timeout=3)
        log = (stdout + stderr).decode()
        events = [json.loads(value) for value in re.findall(r"PARTY LATENCY EVENT (\{[^\n]+\})", log)]
        matched = []
        for written in writes:
            candidates = [event for event in events if 0 <= event['detectedAt'] - written < 350]
            if candidates:
                event = min(candidates, key=lambda item: item['detectedAt'])
                matched.append({"captureToDetectionMs": event['detectedAt'] - written,
                                "captureToFrameMs": event['presentedAt'] - written,
                                "guiDeliveryMs": event['detectedAt'] - event['emittedAt']})
        result = {"kicksWritten": len(writes), "kicksMatched": len(matched), "events": matched,
                  "scope": "FIFO PCM write to offscreen Qt frame swap; excludes speaker latency"}
        if matched:
            for key in matched[0]:
                result[key] = {"median": statistics.median(item[key] for item in matched),
                               "maximum": max(item[key] for item in matched)}
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
        if errors or process.returncode != 0 or len(matched) != 8:
            raise RuntimeError("; ".join(errors) + "\n" + log)


if __name__ == "__main__":
    main()
