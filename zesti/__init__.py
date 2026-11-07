"""Zesti CLI package: Caelestia-free Quickshell control and desktop utilities.

Version is intentionally a single stable string; ``zesti --version`` prints it.
"""

from pathlib import Path

__version__ = "1.0.0"

#: Repository root: parent of the ``zesti`` package directory.
ROOT = Path(__file__).resolve().parent.parent
