"""Scheme state management for zesti.

Static schemes and application templates are repository data under ``data/``.
Runtime state (the active ``scheme.json``) lives under Zestify XDG state and is
written atomically.
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from zesti.paths import atomic_json, load_json


#: Palette variants accepted by ``zesti scheme set`` (and Matugen spellings).
VALID_VARIANTS = frozenset({
    "tonalspot",
    "vibrant",
    "expressive",
    "fidelity",
    "fruitsalad",
    "monochrome",
    "neutral",
    "rainbow",
    "content",
})

#: Scheme file extensions recognised as static scheme data.
SCHEME_EXTENSIONS = {".json", ".toml", ".yaml", ".yml"}


@dataclass(frozen=True)
class SchemeChoice:
    name: str
    flavour: str
    path: Path


def _default_flavour(name: str) -> str:
    lowered = name.lower()
    for variant in sorted(VALID_VARIANTS, key=len, reverse=True):
        if lowered.startswith(variant):
            return variant
    return "tonalspot"


def list_schemes(data_dir: Path) -> list[SchemeChoice]:
    """Discover static scheme files in ``data_dir``.

    Returns one :class:`SchemeChoice` per recognised scheme file, sorted by
    name. Non-scheme files are ignored.
    """
    data_dir = Path(data_dir)
    if not data_dir.is_dir():
        return []
    choices = []
    for entry in sorted(data_dir.iterdir()):
        if not entry.is_file():
            continue
        if entry.suffix.lower() not in SCHEME_EXTENSIONS:
            continue
        choices.append(
            SchemeChoice(
                name=entry.stem,
                flavour=_default_flavour(entry.stem),
                path=entry,
            )
        )
    choices.sort(key=lambda c: c.name)
    return choices


def validate_variant(variant: str) -> None:
    """Raise :class:`ValueError` if ``variant`` is not a documented variant.

    ``random`` is not an explicit variant; it is handled by the caller.
    """
    if variant not in VALID_VARIANTS:
        raise ValueError(f"unknown scheme variant: {variant!r}")


def select_variant(variant: str, rng: random.Random | None = None) -> str:
    """Resolve a variant selection.

    Explicit variants are validated and returned as-is. ``random`` picks one
    documented variant using ``rng`` (defaults to :mod:`random`).
    """
    if variant == "random":
        rng = rng or random
        return rng.choice(sorted(VALID_VARIANTS))
    validate_variant(variant)
    return variant


def load_scheme(paths) -> dict:
    """Load the active scheme from Zestify state.

    Returns an empty dict when no scheme file exists yet (first run). Raises
    :class:`ValueError` if the file is present but not valid JSON.
    """
    path = Path(paths.scheme_file)
    if not path.exists():
        return {}
    return load_json(path)


def save_scheme(paths, scheme: Mapping[str, object]) -> None:
    """Atomically persist the active scheme to Zestify state."""
    atomic_json(Path(paths.scheme_file), dict(scheme))
