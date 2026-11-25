#!/usr/bin/env python3
"""Narrow inference entry point; independent of shell palette dependencies."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from zesti.paths import Paths
from zesti.wallfx import prepare_effect


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--no-inference', action='store_true')
    args = parser.parse_args()
    if not args.no_inference:
        try:
            os.nice(10)
        except OSError:
            pass
    try:
        maps = prepare_effect(Path(args.source).expanduser(), Paths.from_env(os.environ),
                              allow_inference=not args.no_inference)
    except Exception as exc:
        print(json.dumps({'ok': False, 'error': str(exc)}))
        return 1
    print(json.dumps({'ok': True, **maps}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
