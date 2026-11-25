"""Application theme rendering for zesti.

Renders repository-owned templates against a normalized scheme and writes the
result to application config locations, one target at a time, serialized by a
state lock so a failure in one adapter never rolls back the shell palette.
"""

from __future__ import annotations

import fcntl
import configparser
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Callable, Mapping

from zesti.paths import Paths, atomic_write
from zesti import ROOT
from zesti import dolphin, gtk_theme, zen


_PLACEHOLDER = re.compile(r"(#?)\{([A-Za-z][A-Za-z0-9_]*)\}")

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
    values = dict(colours, mode=mode)
    unknown = set()

    def substitute(match):
        prefix, key = match.groups()
        if key not in values:
            unknown.add(key)
            return match.group(0)
        value = str(values[key])
        if (prefix or hash_prefix) and key != "mode":
            value = "#" + value.lstrip("#")
        return value

    result = _PLACEHOLDER.sub(substitute, str(text))
    if unknown:
        raise ThemeError("unknown placeholder(s): " + ", ".join(sorted(unknown)))
    return result


def theme_targets(paths: Paths, config: Mapping[str, object], data_dir: Path | None = None) -> list[ThemeTarget]:
    """Discover theme targets from repository data and user configuration."""
    if data_dir is None:
        data_dir = DEFAULT_TEMPLATE_DIR
    data_dir = Path(data_dir)
    targets: dict[str, ThemeTarget] = {}
    destinations = {
        "colors": (paths.config_home / "kitty/zestify-colors.conf", "kitty"),
        "gtk": (paths.config_home / "zestify/theme/gtk.css", "gtk"),
        "qt": (paths.config_home / "qtengine/zestify.colors", "qtengine"),
        "dolphin": (paths.config_home / "zestify/theme/dolphin.qss", "dolphin"),
        "fuzzel": (paths.config_home / "fuzzel/fuzzel.ini", "ini"),
        "cava": (paths.config_home / "cava/config", "ini"),
        "spicetify": (paths.config_home / "spicetify/Themes/zestify/color.ini", "spicetify"),
        "zen": (paths.config_home / "zestify/theme/zen.css", "zen"),
    }
    if data_dir.is_dir():
        for f in sorted(data_dir.iterdir()):
            if f.is_file():
                output, renderer = destinations.get(f.stem, (
                    paths.state_home / "zestify" / f"{f.stem}.rendered", "template"))
                targets[f.stem] = ThemeTarget(
                        name=f.stem,
                        enabled=(zen.configured(paths) if f.stem == "zen" else
                                 (paths.config_home / "zestify/theme/dolphin-launch").is_file() if f.stem == "dolphin" else
                                 f.stem != "spicetify" or (paths.config_home / "spicetify/config-xpui.ini").is_file()),
                        template_path=f,
                        output=output,
                        renderer=renderer,
                )
    apply_cfg = config.get("theme", {}).get("apply", {}) if isinstance(config, dict) else {}
    if isinstance(apply_cfg, dict):
        for name, spec in apply_cfg.items():
            if not isinstance(spec, dict):
                continue
            output = spec.get("output")
            target = targets.get(name, ThemeTarget(name=name))
            updates = {"enabled": bool(spec.get("enabled", True))}
            if output:
                updates["output"] = Path(output).expanduser()
            if "template" in spec:
                updates.update(template=spec["template"], template_path=None)
            if spec.get("template_path"):
                updates.update(template=None, template_path=Path(spec["template_path"]).expanduser())
            if "renderer" in spec:
                updates["renderer"] = str(spec["renderer"])
            targets[name] = replace(target, **updates)
    return list(targets.values())


def scheme_colours(scheme: Mapping, config: Mapping) -> tuple[dict, str]:
    """Choose the same mode/palette as the shell and fill optional app roles."""
    theme = config.get("theme", {})
    mode = theme.get("mode", scheme.get("metadata", {}).get("mode", scheme.get("mode", "dark")))
    if mode not in ("dark", "light"):
        mode = scheme.get("mode", "dark")
    if mode not in ("dark", "light"):
        mode = "dark"
    colours = dict(scheme.get("palettes", {}).get(mode, scheme.get("colours", {})))
    if not colours and isinstance(scheme.get("colors"), dict):
        for role, entry in scheme["colors"].items():
            selected = entry.get(mode, entry) if isinstance(entry, dict) else entry
            value = selected.get("color") if isinstance(selected, dict) else selected
            if isinstance(value, str):
                parts = role.split("_")
                key = parts[0] + "".join(part[:1].upper() + part[1:] for part in parts[1:])
                colours[key] = value.lstrip("#")
    if not colours:
        raise ThemeError("no palette available; apply a wallpaper first")
    for key, value in list(colours.items()):
        if isinstance(value, str):
            colours[key] = value.lstrip("#")
    colours.setdefault("surfaceVariant", colours.get("surface", ""))
    for key, fallback in {
        "background": "surface", "onBackground": "onSurface",
        "onSurfaceVariant": "onSurface", "outline": "onSurfaceVariant",
        "surfaceContainerLow": "surface", "surfaceContainer": "surface",
        "surfaceContainerHigh": "surfaceVariant", "surfaceContainerHighest": "surfaceVariant",
    }.items():
        if key not in colours and fallback in colours:
            colours[key] = colours[fallback]
    ansi_roles = ["background", "error", "secondary", "tertiary", "primary", "tertiary",
                  "secondary", "onBackground", "outline", "error", "secondary", "tertiary",
                  "primary", "tertiary", "secondary", "onBackground"]
    for i, role in enumerate(ansi_roles):
        colours.setdefault(f"term{i}", scheme.get(f"term{i}", colours.get(role, "")))
    return colours, mode


def _update_config(path: Path, text: str) -> bool:
    """Back up a pre-existing application config once, then update atomically."""
    previous = path.read_text(encoding="utf-8") if path.exists() else None
    if previous == text:
        return False
    backup = path.with_name(path.name + ".zestify.bak")
    if previous is not None and not backup.exists():
        atomic_write(backup, previous)
    atomic_write(path, text)
    return True


def _replace_ini_section(existing: str, section: str, contents: str) -> str:
    """Replace all copies of a colour section, keeping other settings/comments."""
    out = []
    skipping = False
    for line in existing.splitlines(keepends=True):
        header = re.match(r"\s*\[([^]]+)\]", line)
        if header:
            skipping = header.group(1) == section
        if not skipping:
            out.append(line)
    return "".join(out).rstrip() + "\n\n" + contents.rstrip() + "\n"


def _reload_kitty(paths: Paths, run: Callable) -> None:
    # Limit reloads to Kitty instances using this XDG config. Temporary-home
    # tests and other sessions must never signal the user's real terminals.
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / "comm").read_text().strip() != "kitty":
                continue
            env = dict(entry.split(b"=", 1) for entry in (proc / "environ").read_bytes().split(b"\0") if b"=" in entry)
            home = os.fsdecode(env.get(b"HOME", b""))
            config_home = Path(os.fsdecode(env[b"XDG_CONFIG_HOME"])) if env.get(b"XDG_CONFIG_HOME") else Path(home) / ".config"
            if config_home != paths.config_home:
                continue
            status = run(["kill", "-USR1", proc.name])
            if status != 0:
                raise ThemeError(f"could not reload Kitty process {proc.name}")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue


def _spotify_running(paths: Paths) -> bool:
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / "comm").read_text().strip() != "spotify":
                continue
            env = dict(entry.split(b"=", 1) for entry in (proc / "environ").read_bytes().split(b"\0") if b"=" in entry)
            config_home = os.fsdecode(env.get(b"XDG_CONFIG_HOME", b""))
            if not config_home:
                config_home = str(Path(os.fsdecode(env.get(b"HOME", b""))) / ".config")
            if Path(config_home) == paths.config_home:
                return True
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return False


def _reload_cava(output: Path, paths: Paths, run: Callable, proc_root: Path = Path("/proc")) -> None:
    """Reload only standalone cava instances actually reading this output."""
    for proc in proc_root.iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / "comm").read_text().strip() != "cava":
                continue
            env = dict(entry.split(b"=", 1) for entry in (proc / "environ").read_bytes().split(b"\0") if b"=" in entry)
            home = Path(os.fsdecode(env.get(b"HOME", b"")))
            config_home = Path(os.fsdecode(env[b"XDG_CONFIG_HOME"])) if env.get(b"XDG_CONFIG_HOME") else home / ".config"
            if config_home != paths.config_home:
                continue
            args = [os.fsdecode(arg) for arg in (proc / "cmdline").read_bytes().split(b"\0") if arg]
            config = config_home / "cava/config"
            for i, arg in enumerate(args):
                if arg == "-p" and i + 1 < len(args):
                    config = Path(args[i + 1])
                elif arg.startswith("-p") and len(arg) > 2:
                    config = Path(arg[2:])
            if not config.is_absolute():
                config = (proc / "cwd").resolve() / config
            if config.resolve() == output.resolve() and run(["kill", "-USR2", proc.name]) != 0:
                raise ThemeError(f"could not reload cava process {proc.name}")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue


def _apply_spicetify(target: ThemeTarget, rendered: str, paths: Paths, run: Callable) -> None:
    directory = paths.config_home / "spicetify"
    if target.output.name != "color.ini" or target.output.parent.parent != directory / "Themes":
        raise ThemeError("Spicetify output must be Themes/<theme>/color.ini in its config directory")
    theme_name = target.output.parent.name
    config_path = directory / "config-xpui.ini"
    parser = configparser.ConfigParser(interpolation=None, strict=False, inline_comment_prefixes=(";",))
    try:
        parser.read_string(config_path.read_text())
    except configparser.Error as exc:
        raise ThemeError(f"invalid Spicetify configuration: {exc}") from exc
    if not parser.has_section("Setting"):
        raise ThemeError("Spicetify has no [Setting] configuration")
    current = parser["Setting"].get("current_theme", "").strip()
    if current and current != theme_name:
        # Copy the selected user theme once, keeping its CSS/JS/assets intact
        # and leaving the original theme untouched. Future palettes are ours.
        if Path(current).name != current or current in (".", ".."):
            raise ThemeError("invalid Spicetify theme name")
        source = directory / "Themes" / current
        if not source.is_dir():
            raise ThemeError(f"cannot preserve Spicetify theme: {source} is missing")
        for asset in source.rglob("*"):
            destination = target.output.parent / asset.relative_to(source)
            if asset.is_file() and asset != source / "color.ini" and not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(asset, destination)
    atomic_write(target.output, rendered)
    css = target.output.parent / "user.css"
    if not css.exists():
        atomic_write(css, "/* Zestify Spotify palette */\n")
    parser["Setting"].update(current_theme=theme_name, color_scheme="zestify", inject_css="1", replace_colors="1")
    contents = io.StringIO()
    parser.write(contents)
    _update_config(config_path, contents.getvalue())
    env = dict(os.environ, SPICETIFY_CONFIG=str(directory))
    was_running = _spotify_running(paths)
    command = ["spicetify", "refresh"] if was_running else ["spicetify", "-n", "refresh"]
    with tempfile.TemporaryFile(mode="w+") as diagnostics:
        status = run(command, env=env, stdout=diagnostics, stderr=diagnostics)
        if status != 0:
            diagnostics.seek(0)
            detail = diagnostics.read()[-2000:].strip()
            raise ThemeError("Spicetify refresh failed: " + (detail or "run 'spicetify -n refresh' for details"))


def _apply_target(target: ThemeTarget, rendered: str, paths: Paths, run: Callable, mode: str) -> dict | None:
    if target.renderer not in ("template", "kitty", "gtk", "qtengine", "ini", "spicetify", "zen", "dolphin"):
        raise ThemeError(f"unknown renderer: {target.renderer}")
    if target.renderer == "dolphin":
        dolphin.apply(target.output, rendered, paths, _update_config)
        return
    if target.renderer == "spicetify":
        _apply_spicetify(target, rendered, paths, run)
        return
    if target.renderer == "ini":
        section = "colors" if target.name == "fuzzel" else "color"
        previous = target.output.read_text() if target.output.exists() else ""
        _update_config(target.output, _replace_ini_section(previous, section, rendered))
        if target.name == "cava":
            _reload_cava(target.output, paths, run)
        return
    zen_css_changed = target.renderer == "zen" and (
        not target.output.exists() or target.output.read_text() != rendered)
    atomic_write(target.output, rendered)
    if target.renderer == "kitty":
        config = paths.config_home / "kitty/kitty.conf"
        text = config.read_text() if config.exists() else ""
        include = "include " + str(target.output)
        # Keep the include last so old inline colour settings cannot override it.
        lines = [line for line in text.splitlines() if line.strip() != include]
        _update_config(config, "\n".join(lines).rstrip() + "\n\n" + include + "\n")
        _reload_kitty(paths, run)
    elif target.renderer == "gtk":
        gtk_theme.apply(target.output, rendered, mode, paths, _update_config, run)
    elif target.renderer == "zen":
        result = zen.apply(target.output, paths, _update_config)
        result["restart_required"] |= zen_css_changed
        return result
    elif target.renderer == "qtengine":
        config = paths.config_home / "qtengine/config.json"
        data = json.loads(config.read_text()) if config.exists() else {}
        if not isinstance(data, dict) or not isinstance(data.get("theme", {}), dict):
            raise ThemeError("invalid qtengine configuration")
        data.setdefault("theme", {})["colorScheme"] = str(target.output)
        _update_config(config, json.dumps(data, indent=4) + "\n")


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
    if config.get("theme", {}).get("apply") is False:
        return []
    colours, mode = scheme_colours(scheme, config)

    results: list[dict] = []
    lock_path = _lock_file(paths)
    with lock_path.open("a+") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        try:
            targets = theme_targets(paths, config)
            gtk = next((t for t in targets if t.name == "gtk"), None)
            for target in targets:
                if not target.enabled:
                    results.append({"target": target.name, "ok": True, "error": None})
                    continue
                if not target.output:
                    results.append({"target": target.name, "ok": False, "error": "no output path"})
                    continue
                try:
                    if target.renderer == "zen":
                        gtk_result = next((r for r in results if r["target"] == "gtk"), None)
                        if not gtk or not gtk.enabled or gtk.renderer != "gtk" or not gtk_result or not gtk_result["ok"]:
                            raise ThemeError("Zen requires the GTK theme target to be enabled and applied successfully")
                    template_text = target.template
                    if template_text is None and target.template_path is not None:
                        template_text = target.template_path.read_text(encoding="utf-8")
                    if template_text is None:
                        raise ThemeError("no template to render")
                    rendered = render_template(template_text, colours, mode)
                    details = _apply_target(target, rendered, paths, run, mode) or {}
                    results.append({"target": target.name, "ok": True, "error": None, **details})
                except (ThemeError, ValueError) as exc:
                    results.append({"target": target.name, "ok": False, "error": str(exc)})
                except OSError as exc:
                    results.append({"target": target.name, "ok": False, "error": str(exc)})
        finally:
            fcntl.flock(lock_handle, fcntl.LOCK_UN)
    return results
