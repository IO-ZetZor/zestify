"""Legacy ``zestify`` command normalization.

Translates the existing flat ``zestify`` interface into the canonical
``zesti`` command tree. Pure argument rewriting: no implementation, no
warnings, no deprecation text.
"""

from __future__ import annotations

from typing import Sequence

# Canonical action for each legacy flat command when no sub-verb is given.
_LEGACY_TO_CANONICAL = {
    "start": "shell start",
    "stop": "shell stop",
    "restart": "shell restart",
    "status": "shell status",
    "logs": "shell logs",
    "ipc": "shell open",
}

# Legacy wallpaper-family verbs delegate to the wallpaper family.
_WALLPAPER_VERBS = {"wallpaper", "random", "list", "thumb"}

# ``wallpaper FILE`` needs an explicit ``set`` subcommand; the other verbs are
# already canonical wallpaper subcommands.
_WALLPAPER_SET_VERBS = {"wallpaper"}


def normalize_legacy_args(argv: Sequence[str]) -> list[str]:
    """Rewrite flat ``zestify`` args into canonical ``zesti`` args.

    The first token is the legacy command; everything after it is preserved
    byte-for-byte and appended to the canonical action.
    """
    if not argv:
        return list(argv)

    command, *rest = argv

    if command in _LEGACY_TO_CANONICAL:
        return _LEGACY_TO_CANONICAL[command].split() + rest

    if command in _WALLPAPER_VERBS:
        if command in _WALLPAPER_SET_VERBS:
            # ``zestify wallpaper FILE`` -> ``zesti wallpaper set FILE``.
            return ["wallpaper", "set"] + rest
        return ["wallpaper", command] + rest

    if command in {"proxy", "cache"}:
        return [command] + rest

    # Standalone control commands are already canonical.
    return [command] + rest
