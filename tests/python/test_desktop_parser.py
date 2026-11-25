import os
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
QMLTESTRUNNER = Path("/usr/lib/qt6/bin/qmltestrunner")


class DesktopParserTest(unittest.TestCase):
    def test_qml_desktop_parser_suite(self):
        env = os.environ.copy()
        env["QT_QPA_PLATFORM"] = "offscreen"
        result = subprocess.run(
            [
                str(QMLTESTRUNNER),
                "-input",
                str(REPO / "tests" / "qml" / "tst_desktop.qml"),
                "-import",
                str(REPO / "shell"),
            ],
            env=env,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Totals: 10 passed, 0 failed", result.stdout)


if __name__ == "__main__":
    unittest.main()
