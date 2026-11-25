"""Opt-in Dolphin profile: palette-aware outline icons and soft native controls."""

from __future__ import annotations

import json
import re
import shlex
from pathlib import Path
from typing import Callable

from zesti import ROOT
from zesti.paths import Paths, atomic_write


ICON_THEME = "zestify-minimal"


def _set_key(text: str, group: str, key: str, value: str) -> str:
    lines, active, found = [], False, False
    for line in text.splitlines(keepends=True):
        if line.startswith("["):
            if active and not found:
                lines.append(f"{key}={value}\n")
                found = True
            active = line.strip() == f"[{group}]"
        if active and line.startswith(key + "="):
            line = f"{key}={value}\n"
            found = True
        lines.append(line if line.endswith("\n") else line + "\n")
    if not found:
        if not active:
            lines.append(f"\n[{group}]\n")
        lines.append(f"{key}={value}\n")
    return "".join(lines)


def _desktop_launch(text: str, quoted: str) -> str:
    command = f'Exec=/usr/bin/env "{quoted}"'
    lines, active = [], False
    for line in text.splitlines(keepends=True):
        if line.startswith("["):
            active = line.strip() == "[Desktop Entry]"
        if active and line.startswith("Exec="):
            if not line.startswith(command):
                line = re.sub(r'^Exec=(?:"(?:\\.|[^"\\])*"|\S+)(.*)$',
                              lambda match: command + match[1], line)
        lines.append(line)
    return _set_key("".join(lines), "Desktop Entry", "DBusActivatable", "false")


def _quote_desktop(path: Path) -> str:
    value = str(path).replace("%", "%%")
    value = re.sub(r'([\\"`$])', lambda match: "\\" + match[1], value)
    return value.replace("\\", "\\\\")


def _service_command(launcher: Path) -> str:
    # D-Bus unescapes the key-file value before parsing shell arguments, but
    # unlike desktop Exec it does not expand percent field codes.
    return shlex.quote(str(launcher)).replace("\\", "\\\\") + " --daemon"


def _file_manager(text: str, launcher: Path, *, restore: bool = False) -> str:
    command = shlex.quote(str(launcher))
    replacement = "dolphin" if restore else command
    pattern = re.compile(r'(?m)^(\s*\w+\.fileManager\s*=\s*)("(?:\\.|[^"\\])*"|\x27[^\x27]*\x27)')

    def replace(match):
        literal = match[2]
        try:
            current = json.loads(literal) if literal.startswith('"') else literal[1:-1]
        except ValueError:
            return match[0]
        if current != (command if restore else "dolphin"):
            return match[0]
        return match[1] + json.dumps(replacement, ensure_ascii=False)

    return pattern.sub(replace, text)


def apply(output: Path, rendered: str, paths: Paths,
          update: Callable[[Path, str], object]) -> None:
    config = paths.config_home / "qtengine/config.json"
    data = json.loads(config.read_text()) if config.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get("theme", {}), dict):
        raise ValueError("invalid qtengine configuration")
    source = ROOT / "data/dolphin/icons"
    for asset in source.rglob("*"):
        if asset.is_file():
            destination = paths.data_home / "icons" / ICON_THEME / asset.relative_to(source)
            text = asset.read_text()
            if not destination.exists() or destination.read_text() != text:
                atomic_write(destination, text)

    # Use Qt's palette() roles, rather than baking wallpaper colours into QSS.
    # The platform theme refreshes the existing stylesheet's native palette.
    atomic_write(output, rendered)
    launcher = output.parent / "dolphin-launch"
    command = (ROOT / "data/dolphin/launch.py").read_text()
    if not launcher.exists() or launcher.read_text() != command:
        update(launcher, command)
    launcher.chmod(0o755)
    alias = output.parent / "dolphin"
    if not alias.exists() and not alias.is_symlink():
        alias.symlink_to(launcher.name)
    elif not alias.is_symlink() or alias.resolve() != launcher.resolve():
        raise ValueError(f"cannot install Dolphin command alias: {alias} already exists")
    atomic_write(output.parent / "dolphin.lua", (ROOT / "data/dolphin/hypr.lua").read_text())
    constants = paths.config_home / "hypr/conf/const.lua"
    if constants.exists():
        update(constants, _file_manager(constants.read_text(), launcher))

    # File-manager requests from browsers bypass both PATH and .desktop Exec.
    # A user service takes priority over the distribution's bare --daemon.
    service = paths.data_home / "dbus-1/services/org.kde.dolphin.FileManager1.service"
    update(service, '[D-BUS Service]\nName=org.freedesktop.FileManager1\n'
           + f'Exec={_service_command(launcher)}\n')

    # Preserve the installed desktop metadata and any user customization.
    desktop = paths.data_home / "applications/org.kde.dolphin.desktop"
    installed = Path("/usr/share/applications/org.kde.dolphin.desktop")
    if desktop.exists() or installed.exists():
        text = (desktop if desktop.exists() else installed).read_text()
        # D-Bus activation would bypass the stylesheet launch arguments.
        update(desktop, _desktop_launch(text, _quote_desktop(launcher)))
    data.setdefault("theme", {})["iconTheme"] = ICON_THEME
    update(config, json.dumps(data, indent=4) + "\n")
    # KDE initializes its global icon loader from kdeglobals after the Qt
    # platform theme. Keep that override in sync with the chosen icon theme.
    kde = paths.config_home / "kdeglobals"
    update(kde, _set_key(kde.read_text() if kde.exists() else "", "Icons", "Theme", ICON_THEME))

    # Keep file previews; folder collages hide the minimal directory icons.
    settings = paths.config_home / "dolphinrc"
    if settings.exists():
        text = settings.read_text()
        in_previews = False
        lines = []
        for line in text.splitlines(keepends=True):
            if line.startswith("["):
                in_previews = line.strip() == "[PreviewSettings]"
            if in_previews and line.startswith("Plugins="):
                plugins = line.strip().split("=", 1)[1].split(",")
                line = "Plugins=" + ",".join(p for p in plugins if p != "directorythumbnail") + "\n"
            lines.append(line)
        update(settings, "".join(lines))


def prepare_purge(paths: Paths, home: Path) -> None:
    """Disconnect only owned launch integrations before removing the profile."""
    launcher = paths.config_home / "zestify/theme/dolphin-launch"
    desktop = paths.data_home / "applications/org.kde.dolphin.desktop"
    if desktop.exists():
        prefixes = (f'Exec=/usr/bin/env "{_quote_desktop(launcher)}"',
                    f'Exec="{_quote_desktop(launcher)}"')
        text = desktop.read_text()
        lines, active = [], False
        for line in text.splitlines(keepends=True):
            if line.startswith("["):
                active = line.strip() == "[Desktop Entry]"
            for prefix in prefixes:
                if active and line.startswith(prefix):
                    line = "Exec=/usr/bin/dolphin" + line[len(prefix):]
                    break
            lines.append(line)
        if "".join(lines) != text:
            atomic_write(desktop, "".join(lines))
    link = home / ".local/bin/dolphin"
    if link.is_symlink() and link.resolve() == launcher.resolve():
        link.unlink()
    constants = paths.config_home / "hypr/conf/const.lua"
    if constants.exists():
        text = constants.read_text()
        updated = _file_manager(text, launcher, restore=True)
        if updated != text:
            atomic_write(constants, updated)
    service = paths.data_home / "dbus-1/services/org.kde.dolphin.FileManager1.service"
    if service.exists() and f'Exec={_service_command(launcher)}' in service.read_text():
        backup = service.with_name(service.name + ".zestify.bak")
        if backup.exists():
            atomic_write(service, backup.read_text())
        else:
            service.unlink()
    rules = paths.config_home / "hypr/conf/rules.lua"
    if rules.exists():
        text = rules.read_text()
        updated = re.sub(r'(?m)^-- >>> zestify-dolphin >>>\n.*?^-- <<< zestify-dolphin <<<\n?',
                         "", text, flags=re.S)
        if updated != text:
            atomic_write(rules, updated)
