"""XDG-aware filesystem paths owned by Zestify, plus atomic writers."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


@dataclass(frozen=True)
class Paths:
    """Immutable XDG paths used by Zestify-owned state/config/cache/data."""

    config_home: Path
    data_home: Path
    state_home: Path
    cache_home: Path
    config_file: Path
    scheme_file: Path
    wallpaper_dir: Path
    monitor_dir: Path
    migration_file: Path

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "Paths":
        home = Path(env.get("HOME") or Path.home())
        config_home = Path(env.get("XDG_CONFIG_HOME") or home / ".config")
        data_home = Path(env.get("XDG_DATA_HOME") or home / ".local/share")
        state_home = Path(env.get("XDG_STATE_HOME") or home / ".local/state")
        cache_home = Path(env.get("XDG_CACHE_HOME") or home / ".cache")

        zestify_config = config_home / "zestify"
        zestify_state = state_home / "zestify"
        wallpaper_dir = zestify_state / "wallpaper"

        return cls(
            config_home=config_home,
            data_home=data_home,
            state_home=state_home,
            cache_home=cache_home,
            config_file=zestify_config / "config.json",
            scheme_file=zestify_state / "scheme.json",
            wallpaper_dir=wallpaper_dir,
            monitor_dir=wallpaper_dir / "monitors",
            migration_file=zestify_state / "migration.json",
        )


def atomic_write(path: Path, content: str) -> None:
    """Write ``content`` to ``path`` atomically, creating parents as needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def atomic_json(path: Path, value: object) -> None:
    """Atomically write ``value`` as compact, sorted JSON to ``path``."""
    atomic_write(path, json.dumps(value, sort_keys=True))


def load_json(path: Path) -> object:
    """Parse a JSON file, raising ``ValueError`` on invalid top-level JSON."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in {path}: {exc}") from exc
