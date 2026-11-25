import configparser
import importlib.util
import json
import os
import selectors
import subprocess
import struct
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
CAVA_MONITOR = REPO / "scripts" / "cava-monitor.py"
CAVA_CONFIG = REPO / "config" / "cava.conf"


def load_cava_monitor():
    spec = importlib.util.spec_from_file_location("zestify_cava_monitor", CAVA_MONITOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ChunkedReader:
    def __init__(self, chunks):
        self.chunks = iter(chunks)

    def read(self, _size):
        return next(self.chunks, b"")


class CavaMonitorTest(unittest.TestCase):
    def test_party_stop_removes_temporary_config_and_reaps_cava(self):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            record = directory / "capture.txt"
            fake = directory / "cava"
            fake.write_text(
                f"#!{sys.executable}\n"
                "import os, sys, time\n"
                "from pathlib import Path\n"
                "Path(os.environ['CAVA_TEST_RECORD']).write_text(sys.argv[2] + '\\n' + str(os.getpid()))\n"
                "sys.stdout.buffer.write(bytes([1]) * 64)\n"
                "sys.stdout.buffer.flush()\n"
                "time.sleep(60)\n"
            )
            fake.chmod(0o755)
            env = dict(os.environ, HOME=scratch, CAVA_TEST_RECORD=str(record),
                       PATH=scratch + os.pathsep + os.environ.get("PATH", ""))
            process = subprocess.Popen([sys.executable, str(CAVA_MONITOR), "--party"],
                                       env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=5), "monitor should emit a frame")
                    packet = json.loads(process.stdout.readline())
                    self.assertTrue(packet["fixedGain"])
                    self.assertEqual(len(packet["levels"]), 32)
                config_path, child_pid = record.read_text().splitlines()
                self.assertTrue(Path(config_path).exists())
                process.terminate()
                self.assertEqual(process.wait(timeout=5), 0)
                self.assertFalse(Path(config_path).exists(), "stop should unlink its temp config")
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(child_pid), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                process.stdout.close()
                process.stderr.close()

    def test_party_config_preserves_capture_and_format(self):
        module = load_cava_monitor()
        text = CAVA_CONFIG.read_text() + "\n[input]\nmethod = fifo\nsource = /tmp/music.fifo\n"
        config = configparser.ConfigParser()
        config.read_string(module.party_config(text))
        self.assertEqual(config.getint("smoothing", "noise_reduction"), 0)
        self.assertEqual(config.get("input", "method"), "fifo")
        self.assertEqual(config.get("input", "source"), "/tmp/music.fifo")
        self.assertEqual(config.getint("general", "bars"), 32)
        self.assertEqual(config.getint("general", "framerate"), 60)
        self.assertEqual(config.getint("output", "bit_format"), 16)
        self.assertEqual(config.getint("general", "autosens"), 0)
        self.assertEqual(config.getint("general", "sensitivity"), 100)
        self.assertEqual(config.get("output", "channels"), "stereo")
        self.assertIn("noise_reduction = 77", text, "the original config is untouched")

    def test_party_config_handles_missing_option_and_section(self):
        module = load_cava_monitor()
        for text in ["[general]\nbars=32", "[smoothing]\nmonstercat=0\n[output]\nchannels=stereo"]:
            config = configparser.ConfigParser()
            config.read_string(module.party_config(text))
            self.assertEqual(config.getint("smoothing", "noise_reduction"), 0)

    def test_party_packet_preserves_sub_byte_impacts(self):
        module = load_cava_monitor()
        packet = module.party_packet(struct.pack("=32H", *([1, 255, 65535, 0] * 8)), 12)
        self.assertEqual(packet["sequence"], 12)
        self.assertEqual(packet["levels"][:4], [1 / 65535, 255 / 65535, 1, 0])
        self.assertGreater(packet["time"], 0)
        self.assertGreater(packet["emittedAt"], 0)

    def test_frame_clock_keeps_batched_frames_spaced_and_recovers_stall(self):
        clock = load_cava_monitor().FrameClock()
        times = [clock.advance(value) for value in [1000, 1050, 1050, 1050, 1067]]
        for before, after in zip(times, times[1:]):
            self.assertGreater(after - before, 15)
            self.assertLess(after - before, 18)
        self.assertEqual(clock.advance(2000), 2000)
        for _ in range(20):
            before = clock.previous
            self.assertGreater(clock.advance(2000), before)

    def test_short_reads_are_buffered_into_complete_frames(self):
        module = load_cava_monitor()
        stream = ChunkedReader([
            bytes([1, 2, 3]),
            bytes(range(4, 18)),
            bytes(range(18, 25)),
        ])

        frames = list(module.read_frames(stream, 12))

        self.assertEqual(frames, [bytes(range(1, 13)), bytes(range(13, 25))])

    def test_incomplete_final_frame_is_not_emitted(self):
        module = load_cava_monitor()
        stream = ChunkedReader([bytes(range(10)), b""])

        self.assertEqual(list(module.read_frames(stream, 12)), [])

    def test_config_frame_size_matches_monitor(self):
        """Cava writes `bars * bit_format / 8` bytes per raw frame.

        The monitor reads BAR_COUNT bytes per frame, so the config must
        produce exactly one byte per bar. Getting this wrong makes cava
        data arrive misaligned and look random instead of musical.
        """
        module = load_cava_monitor()
        config = configparser.ConfigParser()
        config.read(CAVA_CONFIG)

        bars = config.getint("general", "bars")
        bit_format = config.getint("output", "bit_format")

        self.assertEqual(bars, module.BAR_COUNT)
        self.assertEqual(bit_format, 8)
        self.assertEqual(bars * bit_format // 8, module.BAR_COUNT)

    def test_config_keeps_channels_under_output_section(self):
        """cava ignores `channels` anywhere except [output]."""
        config = configparser.ConfigParser()
        config.read(CAVA_CONFIG)

        self.assertEqual(config.get("output", "channels"), "stereo")
        self.assertFalse(config.has_option("raw", "channels"))

    def test_config_refreshes_at_cava_framerate(self):
        config = configparser.ConfigParser()
        config.read(CAVA_CONFIG)

        self.assertEqual(config.getint("general", "framerate"), 60)


if __name__ == "__main__":
    unittest.main()
