"""Copy-only migration of legacy shell state into Zestify-owned state.

Migration never moves or deletes legacy data. It copies the current global
and per-monitor wallpaper paths plus the current scheme into Zestify state,
best-effort regenerates the palette from the source wallpaper, and writes a
schema marker *last* so an interrupted run is safe to retry.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from zesti.paths import Paths, atomic_write, atomic_json
from zesti.wallpaper import monitor_slug


MIGRATION_SCHEMA = 1
MIGRATION_FILE = "migration.json"


@dataclass
class MigrationResult:
    copied_global: bool = False
    copied_monitors: dict[str, str] = field(default_factory=dict)
    copied_scheme: bool = False
    regenerated: bool = False
    marker_written: bool = False
    skipped: bool = False
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


PaletteGenerator = Callable[[Path, Paths], dict]


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def _marker_path(paths: Paths) -> Path:
    return paths.state_home / "zestify" / MIGRATION_FILE


def _already_migrated(paths: Paths) -> bool:
    try:
        data = json.loads(_marker_path(paths).read_text(encoding="utf-8"))
        return (isinstance(data, dict) and data.get("schema") == MIGRATION_SCHEMA
                and data.get("completed") is True)
    except (OSError, json.JSONDecodeError):
        return False


def migrate(
    source_state: Path,
    source_config: Path | None,
    paths: Paths,
    *,
    force: bool = False,
    generate: PaletteGenerator | None = None,
) -> MigrationResult:
    """Copy legacy wallpaper/state into Zestify state.

    Source files are only ever read. On any failure the previously valid
    destination state is left untouched and the schema marker is not written,
    so the run is safe to retry.
    """
    source_state = Path(source_state)
    result = MigrationResult()

    if not force and _already_migrated(paths):
        result.skipped = True
        return result

    errors: list[str] = []

    # 1. Copy the global wallpaper path (never the image itself).
    source_global = source_state / "path.txt"
    if source_global.is_file():
        value = _read_text(source_global)
        if value:
            paths.wallpaper_dir.mkdir(parents=True, exist_ok=True)
            atomic_write(paths.wallpaper_dir / "path.txt", value)
            result.copied_global = True

    # 2. Copy per-monitor overrides (copied, not truncated).
    source_monitors = source_state / "monitors"
    if source_monitors.is_dir():
        paths.monitor_dir.mkdir(parents=True, exist_ok=True)
        for entry in sorted(source_monitors.iterdir()):
            if entry.suffix != ".txt":
                continue
            value = _read_text(entry)
            if not value:
                continue
            target = paths.monitor_dir / f"{monitor_slug(entry.stem)}.txt"
            try:
                atomic_write(target, value)
                result.copied_monitors[entry.stem] = str(target)
            except OSError as exc:
                errors.append(f"monitor {entry.stem}: {exc}")

    # 3. Copy the current scheme as an immediate fallback.
    source_scheme = source_state / "scheme.json"
    if source_scheme.is_file():
        try:
            scheme = json.loads(source_scheme.read_text(encoding="utf-8"))
            if isinstance(scheme, dict):
                atomic_json(paths.scheme_file, scheme)
                result.copied_scheme = True
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"scheme: {exc}")

    # 4. Best-effort palette regeneration from the source wallpaper.
    if generate is not None and result.copied_global:
        global_value = _read_text(source_state / "path.txt")
        if global_value and Path(global_value).exists():
            try:
                regenerated = generate(Path(global_value), paths)
                if isinstance(regenerated, dict):
                    atomic_json(paths.scheme_file, regenerated)
                    result.regenerated = True
            except Exception as exc:  # noqa: BLE001 - keep copied fallback
                errors.append(f"palette: {exc}")

    # 5. Write the schema marker *last*, only after everything above.
    try:
        marker = {
            "schema": MIGRATION_SCHEMA,
            "completed": not errors,
            "copied_global": result.copied_global,
            "copied_monitors": result.copied_monitors,
            "copied_scheme": result.copied_scheme,
            "regenerated": result.regenerated,
        }
        atomic_json(_marker_path(paths), marker)
        result.marker_written = True
    except OSError as exc:
        errors.append(f"marker: {exc}")

    result.errors = errors
    return result
