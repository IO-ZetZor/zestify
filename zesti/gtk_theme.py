"""Named GTK themes provide native palette notifications to GTK and Gecko."""

from __future__ import annotations

import configparser
import hashlib
import json
import os
import pwd
import re
import tempfile
from pathlib import Path
from typing import Callable

from zesti.paths import Paths, atomic_write


def _theme_file(paths: Paths, name: str, version: str, dark: bool = False) -> Path | None:
    roots = [paths.data_home / "themes"]
    if paths.config_home.name == ".config":
        roots.append(paths.config_home.parent / ".themes")
    roots.extend(Path(root) / "themes" for root in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"))
    for root in roots:
        directory = root / name / f"gtk-{version}"
        variant = directory / "gtk-dark.css"
        normal = directory / "gtk.css"
        if dark and variant.is_file():
            return variant
        if normal.is_file():
            return normal
    return None


def _set_ini(text: str, values: dict[str, str]) -> str:
    """Update owned Settings keys without dropping comments or other sections."""
    out, pending, in_settings, found = [], dict(values), False, False
    for line in text.splitlines(keepends=True):
        header = re.match(r"\s*\[([^]]+)\]", line)
        if header:
            if in_settings:
                out.extend(f"{key}={value}\n" for key, value in pending.items())
                pending.clear()
            in_settings = header.group(1) == "Settings"
            found |= in_settings
        key = re.match(r"\s*([^#;=\s]+)\s*=", line) if in_settings else None
        if key and key.group(1) in values:
            if key.group(1) in pending:
                out.append(f"{key.group(1)}={pending.pop(key.group(1))}\n")
        else:
            out.append(line if line.endswith("\n") else line + "\n")
    if not found:
        out.append("\n[Settings]\n")
    out.extend(f"{key}={value}\n" for key, value in pending.items())
    return "".join(out)


def apply(output: Path, rendered: str, mode: str, paths: Paths,
          update: Callable[[Path, str], object], run: Callable) -> None:
    state_file = paths.config_home / "zestify/theme/gtk-state.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    if not isinstance(state, dict):
        raise ValueError("invalid Zestify GTK theme state")
    settings = paths.config_home / "gtk-3.0/settings.ini"
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    if settings.exists():
        try:
            parser.read_string(settings.read_text())
        except configparser.Error as exc:
            raise ValueError("invalid GTK settings") from exc
    current = parser.get("Settings", "gtk-theme-name", fallback="")
    base = state.get("base", "adw-gtk3" if _theme_file(paths, "adw-gtk3", "3.0") else "Adwaita")
    if current and not current.startswith("Zestify-"):
        base = current
    if not isinstance(base, str) or Path(base).name != base or base in (".", ".."):
        raise ValueError("invalid GTK base theme")
    base_name = re.sub(r"[-_]dark$", "", base, flags=re.I)
    wanted = base_name + "-dark" if mode == "dark" else base_name
    if not _theme_file(paths, wanted, "3.0"):
        wanted = base
    fingerprint = hashlib.sha256((mode + wanted + rendered).encode()).hexdigest()
    previous_slot = state.get("slot", "b")
    if previous_slot not in ("a", "b"):
        raise ValueError("invalid GTK theme slot")
    slot = previous_slot if state.get("fingerprint") == fingerprint else ("a" if previous_slot == "b" else "b")
    name = f"Zestify-{mode}-{slot}"
    for version in ("3.0", "4.0"):
        source = _theme_file(paths, wanted, version, mode == "dark")
        if source:
            include = source.as_uri()
        else:
            theme = "Adwaita" if version == "3.0" else "Default"
            if version == "3.0":
                variant = "gtk-contained-dark.css" if mode == "dark" else "gtk-contained.css"
            else:
                variant = "Default-dark.css" if mode == "dark" else "Default-light.css"
            include = f"resource:///org/gtk/libgtk/theme/{theme}/{variant}"
        text = f'@import url("{include}");\n' + rendered
        directory = paths.data_home / "themes" / name / f"gtk-{version}"
        for filename in ("gtk.css", "gtk-dark.css"):
            path = directory / filename
            if not path.exists() or path.read_text() != text:
                atomic_write(path, text)
        css = paths.config_home / f"gtk-{version}/gtk.css"
        previous = css.read_text() if css.exists() else ""
        owned_import = '@import url("' + output.as_uri() + '");'
        roles = set(re.findall(r"@define-color\s+(\w+)\s", rendered))
        lines = []
        for line in previous.splitlines():
            definition = re.match(r"\s*@define-color\s+(\w+)\s", line)
            if line.strip() != owned_import and not (definition and definition.group(1) in roles):
                lines.append(line)
        if version == "3.0":
            # GTK caches user CSS once. Move owned colours to the reloadable
            # theme provider, preserving custom rules and unrelated colours.
            update(css, "\n".join(lines).rstrip() + "\n")
        else:
            # libadwaita supplies its own theme provider; keep user CSS for
            # its exact palette on startup. Native mode changes remain live.
            update(css, owned_import + "\n" + "\n".join(lines).lstrip() + "\n")
        config = paths.config_home / f"gtk-{version}/settings.ini"
        previous = config.read_text() if config.exists() else ""
        update(config, _set_ini(previous, {"gtk-theme-name": name,
                                          "gtk-application-prefer-dark-theme": "1" if mode == "dark" else "0"}))
    atomic_write(state_file, json.dumps({"base": base, "slot": slot, "fingerprint": fingerprint}) + "\n")
    # Never publish another XDG home's test palette to the real desktop.
    desktop_config = Path(os.environ.get("ZESTI_DESKTOP_CONFIG_HOME", str(Path(pwd.getpwuid(os.getuid()).pw_dir) / ".config")))
    if paths.config_home == desktop_config and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        with tempfile.TemporaryFile(mode="w+") as diagnostics:
            for key, value in (("gtk-theme", name), ("color-scheme", "prefer-" + mode)):
                if run(["gsettings", "set", "org.gnome.desktop.interface", key, value],
                       stdout=diagnostics, stderr=diagnostics) != 0:
                    diagnostics.seek(0)
                    detail = diagnostics.read()[-1000:].strip()
                    raise ValueError(f"could not publish GTK {key}; generated configs are saved: {detail}")
