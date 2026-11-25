#!/usr/bin/env python3
"""Copy-only migration of legacy shell state into Zestify-owned state.

Entry point for ``zesti migrate``. Delegates to :mod:`zesti.migrate`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from zesti.migrate import migrate
from zesti.paths import Paths
from zesti.palette import PaletteSettings, generate_palette


def _default_run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs).returncode


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="zesti-migrate-state")
    parser.add_argument("--force", action="store_true", help="re-copy without skipping")
    parser.add_argument("--source-state", help="legacy shell wallpaper state dir")
    parser.add_argument("--source-config", help="legacy shell config file")
    args = parser.parse_args(argv)

    paths = Paths.from_env(os.environ)
    source_state = (
        Path(args.source_state)
        if args.source_state
        else Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
        / "caelestia"
        / "wallpaper"
    )
    source_config = Path(args.source_config) if args.source_config else None

    result = migrate(
        source_state,
        source_config,
        paths,
        force=args.force,
        generate=lambda src, p: generate_palette(src, PaletteSettings(), _default_run),
    )
    output = dict(result.__dict__)
    output["ok"] = result.ok
    print(json.dumps(output, indent=2, sort_keys=True))
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
