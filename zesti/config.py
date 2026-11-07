"""Configuration loading and validation."""

from __future__ import annotations

from pathlib import Path
from typing import Mapping, MutableMapping

from zesti.paths import load_json


def deep_merge(defaults: MutableMapping, override: Mapping) -> MutableMapping:
    """Recursively merge ``override`` into ``defaults`` without mutating either.

    Returns a new mapping; leaf values from ``override`` win.
    """
    result = dict(defaults)
    for key, value in override.items():
        if (
            key in result
            and isinstance(result[key], Mapping)
            and isinstance(value, Mapping)
        ):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(defaults_path: Path, user_path: Path | None = None) -> dict:
    """Load defaults, then deep-merge an optional partial user config."""
    defaults = load_json(defaults_path)
    if not isinstance(defaults, Mapping):
        raise ValueError(f"top-level config must be an object, got {type(defaults).__name__}")
    merged = deep_merge(defaults, {})
    if user_path is not None:
        if not user_path.exists():
            return merged
        user = load_json(user_path)
        if not isinstance(user, Mapping):
            raise ValueError(f"top-level user config must be an object, got {type(user).__name__}")
        merged = deep_merge(merged, user)
    return merged


def validate_config(value: object) -> list[str]:
    """Return a list of human-readable validation problems (empty when valid)."""
    problems: list[str] = []
    if not isinstance(value, Mapping):
        return ["config must be a JSON object"]

    required_sections = {
        "monitor": ("primary",),
        "theme": ("mode",),
        "wallpaper": ("dir",),
        "session": ("lockAfter",),
    }
    for section, keys in required_sections.items():
        section_value = value.get(section)
        if not isinstance(section_value, Mapping):
            problems.append(f"missing or invalid section '{section}'")
            continue
        for key in keys:
            if key not in section_value:
                problems.append(f"section '{section}' missing key '{key}'")

    return problems
