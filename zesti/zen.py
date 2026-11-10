"""Profile-owned Zen integration; native GTK colours update without restarts."""

from __future__ import annotations

import configparser
import re
from pathlib import Path
from typing import Callable

from zesti.paths import Paths


def _roots(paths: Paths) -> list[Path]:
    roots = [paths.config_home / "zen"]
    if paths.config_home.name == ".config":
        roots.append(paths.config_home.parent / ".zen")
    return roots


def configured(paths: Paths) -> bool:
    return any((root / "profiles.ini").is_file() for root in _roots(paths))


def profiles(paths: Paths) -> list[Path]:
    result = []
    for root in _roots(paths):
        ini = root / "profiles.ini"
        if not ini.is_file():
            continue
        parser = configparser.ConfigParser(interpolation=None)
        try:
            parser.read_string(ini.read_text())
        except configparser.Error as exc:
            raise ValueError(f"invalid Zen profiles configuration: {ini}") from exc
        for section in parser.sections():
            if not section.startswith("Profile") or not parser.has_option(section, "Path"):
                continue
            path = Path(parser[section]["Path"])
            if parser[section].get("IsRelative", "1") == "1":
                path = root / path
            path = path.resolve()
            if path.is_dir() and path not in result:
                result.append(path)
    return result


def apply(output: Path, paths: Paths, update: Callable[[Path, str], object]) -> dict:
    restart = False
    for profile in profiles(paths):
        css = profile / "chrome/userChrome.css"
        previous = css.read_text() if css.exists() else ""
        include = '@import url("' + output.as_uri() + '");'
        lines = [line for line in previous.splitlines() if line.strip() != include]
        # Imports must precede CSS rules. The imported declarations use
        # !important, while personal !important rules can still override them.
        restart |= bool(update(css, include + "\n" + "\n".join(lines).lstrip() + "\n"))
        user = profile / "user.js"
        previous = user.read_text() if user.exists() else ""
        begin, end = "// >>> zestify-theme >>>", "// <<< zestify-theme <<<"
        block = re.compile(r"(?m)^" + re.escape(begin) + r"\n.*?^" + re.escape(end) + r"(?:\n|$)", re.S)
        if (begin in previous or end in previous) and not block.search(previous):
            raise ValueError(f"incomplete Zestify theme block in {user}")
        prefs = (
            'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
            'user_pref("zen.view.window.scheme", 2);',
            'user_pref("zen.theme.use-system-colors", true);',
            'user_pref("zen.theme.accent-color", "AccentColor");',
            'user_pref("widget.gtk.libadwaita-colors.enabled", false);',
        )
        restart |= bool(update(user, block.sub("", previous).rstrip() + "\n\n" + begin + "\n"
                               + "\n".join(prefs) + "\n" + end + "\n"))
    return {"restart_required": restart}
