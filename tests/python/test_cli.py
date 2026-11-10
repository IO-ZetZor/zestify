import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
CLI = REPO / "bin" / "zestify"


class CliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.qs = self.bin / "qs"
        self.qs.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\"\n")
        self.qs.chmod(0o755)
        self.env = os.environ.copy()
        self.env["QS_BIN"] = str(self.qs)

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args):
        return subprocess.run(
            [str(CLI), *args],
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_start_uses_detached_named_config(self):
        result = self.run_cli("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-c zestify", result.stdout)
        self.assertIn("-n", result.stdout)
        self.assertIn("-d", result.stdout)

    def test_status_calls_ping_ipc(self):
        log = self.root / "qs-status.log"
        self.env["QS_STATUS_LOG"] = str(log)
        self.qs.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$QS_STATUS_LOG\"\nprintf 'pong\\n'\n")
        result = self.run_cli("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "pong")
        self.assertEqual(log.read_text().strip(), "ipc -c zestify call zestify ping")

    def test_call_forwards_zero_or_multiple_arguments(self):
        for arguments in [(), ("theme.transparency", "0.5")]:
            with self.subTest(arguments=arguments):
                result = self.run_cli("shell", "call", "zestify", "setConfig", *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), " ".join([
                    "ipc", "-c", "zestify", "call", "zestify", "setConfig", *arguments,
                ]))

    def test_stop_calls_quit_ipc(self):
        result = self.run_cli("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "")

    def test_logs_reads_named_config_log(self):
        result = self.run_cli("logs")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "-c zestify log")


if __name__ == "__main__":
    unittest.main()
