#!/usr/bin/env python3
"""Decode a local track through cavacore and replay production party motion.

Requires ffmpeg, node and the installed libcava; no audio is played aloud.
The core settings match party capture: 32 stereo bars, 60fps, fixed gain,
50-10000Hz and no Cava temporal smoothing. Render with run-party-ui.py --audio-trace.
"""
import argparse
from array import array
import ctypes
from ctypes.util import find_library
import json
import importlib.util
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time


def spectrum_frames(source):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(source), "-vn", "-ar", "44100",
        "-ac", "2", "-f", "s16le", "pipe:1",
    ])
    pcm = array("h")
    pcm.frombytes(raw)
    if sys.byteorder != "little":
        pcm.byteswap()
    name = find_library("cava")
    if not name:
        raise RuntimeError("libcava is required for the audio replay check")
    lib = ctypes.CDLL(name)
    lib.cava_init.argtypes = [ctypes.c_int, ctypes.c_uint, ctypes.c_int,
                             ctypes.c_int, ctypes.c_double, ctypes.c_int, ctypes.c_int]
    lib.cava_init.restype = ctypes.c_void_p
    lib.cava_execute.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int,
                                ctypes.POINTER(ctypes.c_double), ctypes.c_void_p]
    lib.cava_destroy.argtypes = [ctypes.c_void_p]
    plan = lib.cava_init(16, 44100, 2, 0, 0, 50, 10000)
    if not plan:
        raise RuntimeError("cavacore could not initialize")
    output = (ctypes.c_double * 32)()
    frames = []
    try:
        # 735 samples/channel is exactly one 60Hz update at 44100Hz.
        for start in range(0, len(pcm) - 1470 + 1, 1470):
            chunk = array("d", pcm[start:start + 1470])
            data = (ctypes.c_double * len(chunk)).from_buffer(chunk)
            lib.cava_execute(data, len(chunk), output, plan)
            bins = [min(65535, max(0, int(value * 65535))) / 65535 for value in output]
            frames.append(bins[:16][::-1] + bins[16:])
    finally:
        lib.cava_destroy(plan)
    return frames


def realtime_frames(source):
    """Capture the actual cava executable at audio playback cadence via FIFO."""
    repo = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location("cava_monitor", repo / "scripts/cava-monitor.py")
    monitor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(monitor)
    frames = []
    times = []
    clock = monitor.FrameClock()
    with tempfile.TemporaryDirectory(prefix="zestify-audio-capture-") as scratch:
        fifo = Path(scratch) / "audio.fifo"
        os.mkfifo(fifo)
        config = Path(scratch) / "cava.conf"
        config.write_text(monitor.party_config((repo / "config/cava.conf").read_text())
            + f"\n[input]\nmethod = fifo\nsource = {fifo}\nsample_rate = 44100\nsample_bits = 16\n")
        cava = subprocess.Popen(["cava", "-p", str(config)], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        decoder = None
        try:
            decoder = subprocess.Popen([
                "ffmpeg", "-v", "error", "-re", "-i", str(source), "-vn", "-ar", "44100",
                "-ac", "2", "-f", "s16le", "-y", str(fifo),
            ], stderr=subprocess.PIPE)
            buffered = bytearray()
            ended = None
            started = time.monotonic()
            with selectors.DefaultSelector() as selector:
                selector.register(cava.stdout, selectors.EVENT_READ)
                while True:
                    if cava.poll() is not None:
                        raise RuntimeError("cava exited: " + cava.stderr.read().decode())
                    if decoder.poll() is not None:
                        if decoder.returncode != 0:
                            raise RuntimeError("ffmpeg failed: " + decoder.stderr.read().decode())
                        ended = ended or time.monotonic()
                        if time.monotonic() - ended > 0.4:
                            break
                    # A failed FIFO setup must not leave the decoder blocked indefinitely.
                    if not frames and time.monotonic() - started > 10:
                        raise RuntimeError("cava did not produce audio frames")
                    for key, _ in selector.select(timeout=0.2):
                        chunk = os.read(key.fd, 4096)
                        if not chunk:
                            raise RuntimeError("cava output ended unexpectedly")
                        buffered.extend(chunk)
                        while len(buffered) >= 64:
                            packet = monitor.party_packet(bytes(buffered[:64]), len(frames), clock)
                            frames.append(packet['levels'])
                            times.append(packet['time'])
                            del buffered[:64]
        finally:
            for process in [decoder, cava]:
                if process is None:
                    continue
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                for stream in [process.stdout, process.stderr]:
                    if stream:
                        stream.close()
    return frames, times


REPLAY = r"""
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const party = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8').replace('.pragma library', ''), party);
const trace = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
let state = party.idleImpact(), camera = party.idleCamera(), analysis = party.idleAnalysis();
let rhythm = party.idleRhythm(), tint = 0, maxZoom = 1, maxRhythmConfidence = 0;
let largestDenseStep = 0, largestDenseRecoil = 0;
const hits = [], motion = [];
trace.frames.forEach((frame, index) => {
    const dt = trace.times && index ? trace.times[index] - trace.times[index - 1] : trace.dt;
    const previousAge = state.age;
    const oldCamera = camera;
    analysis = party.advanceAnalysis(analysis, frame, dt);
    state = party.advanceImpact(state, analysis.level, dt, true, undefined, true, 0, analysis);
    rhythm = party.advanceRhythm(rhythm, state, dt);
    camera = party.advanceCamera(camera, state, previousAge, dt, rhythm);
    tint = party.advanceTint(tint, camera.envelope, dt);
    maxRhythmConfidence = Math.max(maxRhythmConfidence, rhythm.confidence);
    const recoil = camera;
    const zoom = 1 + .30 * camera.envelope + .035 * Math.max(0, state.buildup - .01);
    assert(Number.isFinite(zoom) && zoom >= 1 && zoom <= 1.335);
    assert(Number.isFinite(recoil.x) && Math.abs(recoil.x) <= 1);
    assert(Number.isFinite(recoil.y) && Math.abs(recoil.y) <= 1);
    maxZoom = Math.max(maxZoom, zoom);
    if (camera.density > .8 && previousAge < 260) {
        largestDenseStep = Math.max(largestDenseStep, .30 * Math.abs(camera.envelope - oldCamera.envelope));
        largestDenseRecoil = Math.max(largestDenseRecoil, Math.abs(camera.x), Math.abs(camera.y));
    }
    const item = {time: index / 60, hit: state.hit, strength: state.strength,
        intrinsicStrength: state.intrinsicStrength, rawBass: analysis.rawBass,
        rhythmPeriod: rhythm.period, rhythmConfidence: rhythm.confidence, tint,
        zoom, envelope: state.envelope, release: state.release, density: camera.density};
    motion.push(item);
    if (state.hit) hits.push(item);
});
assert(largestDenseStep <= .015, 'dense zoom must travel less than 1.5 percent per 60Hz frame');
for (let index = 0; index < 300; ++index) {
    const previousAge = state.age;
    state = party.advanceImpact(state, 1, trace.dt, true, undefined, false);
    camera = party.advanceCamera(camera, state, previousAge, trace.dt);
}
assert(state.envelope === 0 && state.buildup < .01, 'stalled audio must release');
assert(camera.envelope === 0 && Math.abs(camera.x) < .0001
    && Math.abs(camera.y) < .0001, 'stalled audio must settle the camera');
assert.deepStrictEqual(party.advanceImpact(state, 1, trace.dt, false), party.idleImpact());
const summary = {seconds: trace.frames.length / 60, frames: trace.frames.length,
    detectedOnsets: hits.length, maxZoom, largestDenseStep, largestDenseRecoil, maxRhythmConfidence,
    softOnsets: hits.filter(hit => hit.strength < .15).length,
    strongOnsets: hits.filter(hit => hit.strength >= .4).length};
fs.writeFileSync(process.argv[3], JSON.stringify({summary, hits, motion}));
console.log(JSON.stringify(summary, null, 2));
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio", type=Path)
    parser.add_argument("--output", type=Path, default=Path("/tmp/zestify-party-audio"))
    parser.add_argument("--realtime", action="store_true", help="capture actual cava at playback speed")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    frames, times = realtime_frames(args.audio) if args.realtime else (spectrum_frames(args.audio), None)
    if not frames:
        raise RuntimeError("the track contains no complete audio frames")
    trace = args.output / "spectrum.json"
    trace.write_text(json.dumps({"source": args.audio.name, "dt": 1000 / 60,
                                 "fixedGain": True, "times": times,
                                 "realtime": args.realtime, "frames": frames}))
    repo = Path(__file__).resolve().parents[2]
    subprocess.run(["node", "-e", REPLAY, str(repo / "shell/lib/party.js"),
                    str(trace), str(args.output / "motion.json")], check=True)
    print(f"Audio trace: {trace}")


if __name__ == "__main__":
    main()
