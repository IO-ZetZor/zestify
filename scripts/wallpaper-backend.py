#!/usr/bin/env python3
"""Narrow compatibility launcher for wallpaper commands.

Delegates to the :mod:`zesti` package dispatcher so the legacy
``wallpaper-backend.py`` entry keeps working without any Caelestia dependency.
All wallpaper state is owned by Zestify (:mod:`zesti.paths`).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from zesti.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
