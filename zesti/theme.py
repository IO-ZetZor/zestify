"""Application theme rendering for zesti.

Renders repository-owned templates against a normalized scheme and writes the
result to application config locations, one target at a time, serialized by a
state lock so a failure in one adapter never rolls back the shell palette.
"""

from __future__ import annotations

import fcntl
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Mapping

from zesti.paths import Paths, atomic_write
from zesti import ROOT


_PLACEHOLDER = re.compile(r"\{([^}]+)\}")

DEFAULT_TEMPLATE_DIR = ROOT / "data" / "templates"
THEME_LOCK = "theme.lock"


class ThemeError(Exception):
    """Raised when a template cannot be rendered (e.g. unknown placeholder)."""


@dataclass(frozen=True)
class ThemeTarget:
    name: str
    enabled: bool = True
    template: str | None = None
    template_path: Path | None = None
    output: Path | None = None
    renderer: str = "template"


@dataclass(frozen=True)
class ThemeResult:
    target: str
    ok: bool
    error: str | None = None


def render_template(text: str, colours: Mapping[str, str], mode: str, *, hash_prefix: bool = False) -> str:
    """Render placeholders ``{key}`` (and ``#{key}``) against scheme colours.

    ``{mode}`` is substituted with the requested mode. Any placeholder that
    remains after substitution (including ``{mode}`` when colours lacks it) is
    reported as unknown via :class:`ThemeError`.
    """
    result = str(text).replace("{mode}", mode)
    for key, value in colours.items():
        val = str(value)
        if hash_prefix and not val.startswith("#"):
            val = "#" + val
        result = result.replace("#{" + key + "}", val)
        result = result.replace("{" + key + "}", val)
    unknown = sorted(set(_PLACEHOLDER.findall(result)))
    if unknown:
        raise ThemeError("unknown placeholder(s): " + ", ".join(unknown))
    return result


def theme_targets(paths: Paths, config: Mapping[str, object], data_dir: Path | None = None) -> list[ThemeTarget]:
    """Discover theme targets from repository data and user configuration."""
    if data_dir is None:
        data_dir = DEFAULT_TEMPLATE_DIR
    data_dir = Path(data_dir)
    targets: list[ThemeTarget] = []
    if data_dir.is_dir():
        for f in sorted(data_dir.iterdir()):
            if f.is_file():
                targets.append(
                    ThemeTarget(
                        name=f.stem,
                        enabled=True,
                        template=f.read_text(encoding="utf-8"),
                        output=paths.state_home / "zestify" / f"{f.stem}.rendered",
                    )
                )
    apply_cfg = config.get("theme", {}).get("apply", {}) if isinstance(config, dict) else {}
    if isinstance(apply_cfg, dict):
        for name, spec in apply_cfg.items():
            if not isinstance(spec, dict):
                continue
            output = spec.get("output")
            targets.append(
                ThemeTarget(
                    name=name,
                    enabled=bool(spec.get("enabled", True)),
                    template=spec.get("template"),
                    template_path=Path(spec["template_path"]) if spec.get("template_path") else None,
                    output=Path(output) if output else None,
                    renderer=str(spec.get("renderer", "template")),
                )
            )
    return targets


def _lock_file(paths: Paths) -> Path:
    lock_dir = paths.state_home / "zestify"
    lock_dir.mkdir(parents=True, exist_ok=True)
    return lock_dir / THEME_LOCK


def _default_run(cmd, **kwargs):  # pragma: no cover - real subprocess path
    import subprocess

    return subprocess.run(cmd, **kwargs).returncode


def apply_theme(
    scheme: Mapping[str, object],
    paths: Paths,
    config: Mapping[str, object],
    run: Callable = _default_run,
) -> list[dict]:
    """Render every enabled theme target against ``scheme``.

    Returns a list of ``{"target", "ok", "error"}`` dicts. A failure in one
    target does not prevent the others from being written, and the shell
    palette (scheme.json) is never rolled back.
    """
    colours = scheme.get("colours", {}) if isinstance(scheme, dict) else {}
    meta = scheme.get("metadata", {}) if isinstance(scheme, dict) else {}
    mode = str(meta.get("mode", scheme.get("mode", "dark") if isinstance(scheme, dict) else "dark"))

    results: list[dict] = []
    lock_path = _lock_file(paths)
    with lock_path.open("a+") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        try:
            for target in theme_targets(paths, config):
                if not target.enabled:
                    results.append({"target": target.name, "ok": True, "error": None})
                    continue
                if not target.output:
                    results.append({"target": target.name, "ok": False, "error": "no output path"})
                    continue
                try:
                    template_text = target.template
                    if template_text is None and target.template_path is not None:
                        template_text = target.template_path.read_text(encoding="utf-8")
                    if template_text is None:
                        raise ThemeError("no template to render")
                    rendered = render_template(template_text, colours, mode)
                    atomic_write(target.output, rendered)
                    results.append({"target": target.name, "ok": True, "error": None})
                except ThemeError as exc:
                    results.append({"target": target.name, "ok": False, "error": str(exc)})
                except OSError as exc:
                    results.append({"target": target.name, "ok": False, "error": str(exc)})
        finally:
            fcntl.flock(lock_handle, fcntl.LOCK_UN)
    return results
