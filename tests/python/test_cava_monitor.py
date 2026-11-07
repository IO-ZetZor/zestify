import configparser
import importlib.util
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
