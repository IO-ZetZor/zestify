#!/usr/bin/env python3
"""Generate hyprlock config from the Zestify palette and run hyprlock."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import pwd
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov", ".m4v"}

FALLBACK_COLOURS = {
    "background": "020305",
    "onBackground": "e6e4f0",
    "surface": "020305",
    "surfaceContainerHigh": "08090d",
    "primary": "bfc4ee",
    "onPrimary": "383e61",
    "error": "f97386",
    "onSurfaceVariant": "abaab5",
    "outline": "74757f",
}


def home() -> Path:
    return Path(os.environ.get("HOME", str(Path.home())))


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME")
    return Path(base) if base else home() / ".local" / "state"


def cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    return (Path(base) if base else home() / ".cache") / "zestify"


def config_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME")
    return (Path(base) if base else home() / ".config") / "zestify" / "config.json"


def read_config() -> dict:
    try:
        data = json.loads(config_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def monitor_slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", str(name).strip().lower()).strip("-") or "_"


def read_scheme(monitor: str = "") -> dict:
    paths = [state_dir() / "zestify" / "scheme.json"]
    if monitor:
        paths.insert(0, wallpaper_state() / "monitors" / (monitor_slug(monitor) + "-scheme.json"))
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict) and any(isinstance(data.get(key), dict) for key in ("colours", "palettes", "colors")):
                return data
        except (OSError, ValueError):
            pass
    return {"name": "zestify-fallback", "mode": "dark", "colours": dict(FALLBACK_COLOURS)}


def rgb(value: str) -> str:
    text = str(value or "").strip().lstrip("#")
    if len(text) == 8:
        text = text[:6]
    if len(text) != 6 or any(ch not in "0123456789abcdefABCDEF" for ch in text):
        text = "000000"
    return "rgb(%s)" % text.lower()


def palette(scheme: dict, mode: str = "dark") -> dict:
    colours = scheme.get("colours") if isinstance(scheme.get("colours"), dict) else {}
    palettes = scheme.get("palettes")
    if isinstance(palettes, dict) and isinstance(palettes.get(mode), dict):
        colours = palettes[mode]
    elif isinstance(scheme.get("colors"), dict):
        colours = {}
        for role, entry in scheme["colors"].items():
            selected = entry.get(mode, {}) if isinstance(entry, dict) else {}
            if isinstance(selected, dict) and isinstance(selected.get("color"), str):
                key = re.sub(r"_([a-z])", lambda match: match[1].upper(), role)
                colours[key] = selected["color"]
    merged = dict(FALLBACK_COLOURS)
    for key, value in colours.items():
        if isinstance(value, str):
            merged[key] = value
    return merged


def wallpaper_state() -> Path:
    return state_dir() / "zestify" / "wallpaper"


def current_wallpaper(monitor: str = "") -> str:
    config = read_config()
    name = monitor or str(config.get("monitor", {}).get("primary", "eDP-1"))
    state = wallpaper_state()
    legacy = state / "monitors" / (name + ".txt") if Path(name).name == name else state / "missing"
    for path in (state / "monitors" / (monitor_slug(name) + ".txt"), legacy, state / "path.txt"):
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    return ""


def lock_frame(source: str) -> str:
    path = Path(source).expanduser()
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTENSIONS and path.is_file():
        return str(path.resolve())
    if suffix not in VIDEO_EXTENSIONS or not path.is_file() or not shutil.which("ffmpeg"):
        return ""
    try:
        stamp = "%s:%s:%s" % (path.resolve(), path.stat().st_size, path.stat().st_mtime_ns)
    except OSError:
        return ""
    key = hashlib.sha256(stamp.encode("utf-8")).hexdigest()[:24]
    target = cache_dir() / "lock" / (key + ".jpg")
    if target.exists() and target.stat().st_size > 0:
        return str(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-ss", "1", "-i", str(path), "-frames:v", "1",
             "-vf", "scale=1920:-2", str(target)],
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode == 0 and target.exists() and target.stat().st_size > 0:
        return str(target)
    return ""


def monitors() -> list[dict]:
    try:
        result = subprocess.run(
            [os.environ.get("HYPRCTL_BIN", "hyprctl"), "-j", "monitors"],
            capture_output=True, text=True, timeout=3,
        )
        data = json.loads(result.stdout) if result.returncode == 0 else []
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict) and item.get("name") and not item.get("disabled")]
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return []


def rgba(value: str, alpha: float) -> str:
    return "rgba(%s%02x)" % (rgb(value)[4:-1], round(max(0, min(1, alpha)) * 255))


def user_name() -> str:
    try:
        account = pwd.getpwuid(os.getuid())
        return account.pw_gecos.split(",")[0] or account.pw_name
    except KeyError:
        return os.environ.get("USER", "Welcome back")


def battery_status() -> str:
    for device in sorted(Path("/sys/class/power_supply").glob("*")):
        try:
            if (device / "type").read_text().strip() != "Battery":
                continue
            percent = int((device / "capacity").read_text().strip())
            status = (device / "status").read_text().strip()
            return "%d%% · %s" % (percent, status)
        except (OSError, ValueError):
            continue
    return ""


def build_config(scheme: dict, background: str = "", font_family: str = "SF Pro", *,
                 screens: list[dict] | None = None, mode: str = "dark", icon_font: str = "CaskaydiaCove Nerd Font",
                 transparency: float = 0.88, background_opacity: float = 1) -> str:
    screens = screens or [{"name": "", "background": background, "scheme": scheme, "auth": True, "s": 1}]
    chunks = ["""# Generated by zestify lock. Do not edit; it is regenerated on every lock.
general {
    hide_cursor = false
    ignore_empty_input = true
}
animations {
    enabled = true
    bezier = smooth, 0.22, 1, 0.36, 1
    animation = fadeIn, 1, 3, smooth
    animation = fadeOut, 0
    animation = inputFieldDots, 1, 3, smooth
    animation = inputFieldColors, 1, 3, smooth
}
"""]
    font = font_family.replace("\n", " ").replace("\r", " ")
    panel_opacity = max(0, min(1, transparency * background_opacity))
    status_command = shlex.join([sys.executable, str(Path(__file__).resolve()), "--status", "battery"])

    for screen in screens:
        name = screen["name"]
        colours = palette(screen.get("scheme", scheme), mode)
        s = screen.get("s", 1)
        fg = rgb(colours.get("onSurface", colours["onBackground"]))
        dim = rgb(colours["onSurfaceVariant"])
        primary = rgb(colours["primary"])

        def widget(kind: str, values: dict) -> None:
            entries = {"monitor": name, **values}
            chunks.append(kind + " {\n" + "".join("    %s = %s\n" % item for item in entries.items()) + "}\n")

        def label(text: str, size: int, position: str, **extra) -> None:
            # Hyprlock/Pango uses points; the curtain uses logical pixels.
            widget("label", {"text": text, "font_family": font, "font_size": max(1, round(size * s * 0.75)),
                "color": fg, "halign": "center", "valign": "center", "position": position, **extra})

        def pos(x: float, y: float) -> str:
            return "%d, %d" % (round(x * s), round(y * s))

        widget("background", {"path": screen.get("background", ""), "color": rgb(colours["background"]),
            "blur_passes": 3, "blur_size": 8, "brightness": 1, "contrast": 1,
            "vibrancy": 0, "noise": 0})
        # The full-screen wash follows PillBody's alpha, rather than only the
        # password card. Keep the wallpaper's brightness independent of it.
        widget("shape", {"size": "100%, 100%", "color": rgba(colours["surfaceContainerHigh"], panel_opacity),
            "border_size": 0, "zindex": 0})
        label("Z E S T I F Y", 11, pos(36, -32), halign="left", valign="top", color=dim)
        label("cmd[update:10000] " + status_command, 12, pos(-36, -32),
              halign="right", valign="top", color=dim)
        label("󰌾", 24, pos(0, 300), font_family=icon_font, color=primary)
        label('<span weight="light">$TIME</span>', 88, pos(0, 200))
        label('cmd[update:60000] date +"%A, %B %-d"', 17, pos(0, 120), color=dim)

        if screen.get("auth", True):
            widget("shape", {"size": pos(380, 180), "position": pos(0, -35), "rounding": round(28 * s),
                "color": "rgba(00000000)", "border_size": 1,
                "border_color": rgba(colours["outline"], 0.3)})
            label('<span weight="medium">' + html.escape(user_name()) + '</span>', 17, pos(0, 15))
            widget("input-field", {"size": pos(310, 52), "position": pos(0, -45),
                "halign": "center", "valign": "center", "outline_thickness": 2,
                "rounding": round(14 * s), "dots_size": 0.22, "dots_spacing": 0.25,
                "outer_color": rgba(colours["primary"], 0.6), "inner_color": "rgba(00000000)",
                "font_color": fg, "font_family": font, "fade_on_empty": "false",
                "placeholder_text": "Password", "check_text": "Verifying…", "check_color": primary,
                "fail_text": "<i>$FAIL</i>", "fail_color": rgb(colours["error"]),
                "capslock_color": "rgb(e6c77d)"})
            label("Enter to unlock · Esc to clear", 11, pos(0, -100), color=dim)
            label("$LAYOUT", 12, pos(0, 36), valign="bottom", color=dim,
                  onclick="hyprctl switchxkblayout all next")
        else:
            label("Session locked", 17, pos(0, -10), color=dim)

        widget("shape", {"size": pos(90, 36), "position": pos(-36, 28), "halign": "right", "valign": "bottom",
            "rounding": round(18 * s), "color": "rgba(00000000)",
            "border_size": 1, "border_color": rgba(colours["outline"], 0.3), "onclick": "systemctl suspend"})
        label("Sleep", 12, pos(-62, 36), halign="right", valign="bottom", color=dim, onclick="systemctl suspend")
    return "\n".join(chunks)


def screen_configs(config: dict) -> list[dict]:
    outputs = monitors()
    if not outputs:
        outputs = [{"name": str(config.get("monitor", {}).get("primary", "eDP-1"))}]
    primary = config.get("monitor", {}).get("primary", "eDP-1")
    auth_output = next((item["name"] for item in outputs if item.get("focused")),
                       next((item["name"] for item in outputs if item["name"] == primary), outputs[0]["name"]))
    frames = {}
    screens = []
    for output in outputs:
        name = output["name"]
        source = current_wallpaper(name)
        if source not in frames:
            frames[source] = lock_frame(source)
        short_edge = min(output.get("width", 1080), output.get("height", 1080)) / max(output.get("scale", 1), 0.1)
        s = max(0.75, min(1.1, short_edge / 1080)) * config.get("bar", {}).get("scale", 1)
        screens.append({"name": name, "scheme": read_scheme(name), "background": frames[source],
                        "auth": name == auth_output, "s": s})
    return screens


def output_path(value: str | None) -> Path:
    if value:
        return Path(value).expanduser()
    base = os.environ.get("XDG_CONFIG_HOME")
    return (Path(base) if base else home() / ".config") / "zestify" / "hyprlock.conf"


def wrote(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def qs_bin() -> str:
    return os.environ.get("QS_BIN") or shutil.which("qs") or "qs"


def ipc_call(method: str, value: str) -> None:
    try:
        subprocess.run(
            [qs_bin(), "ipc", "-c", "zestify", "call", "zestify", method, value],
            capture_output=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def process_alive(pid: int) -> bool:
    try:
        with open("/proc/%d/stat" % pid, "r", encoding="utf-8") as handle:
            fields = handle.read().rsplit(") ", 1)
        if len(fields) != 2:
            return False
        return fields[1].split()[0] != "Z"
    except OSError:
        return False


def watcher_command(pid: int, log_path: str = "") -> list[str]:
    command = [sys.executable, str(Path(__file__).resolve()), "--watch-pid", str(pid)]
    if log_path:
        command.extend(["--watch-log", log_path])
    return command


def watch(pid: int, log_path: str = "") -> int:
    # Hyprlock reports the compositor's locked event after all lock surfaces
    # cover the outputs. Watching that event avoids a guessed startup delay.
    ready = False
    offset = 0
    tail = ""
    try:
        while process_alive(pid):
            if log_path and not ready:
                try:
                    with open(log_path, encoding="utf-8", errors="replace") as log:
                        log.seek(offset)
                        tail = (tail + log.read())[-8192:]
                        offset = log.tell()
                    if "onLockLocked called" in tail:
                        ready = True
                        ipc_call("lockState", "true")
                except OSError:
                    pass
            time.sleep(0.05)
    finally:
        ipc_call("lockState", "false")
        if log_path:
            Path(log_path).unlink(missing_ok=True)
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="zesti lock")
    parser.add_argument("--wait", action="store_true", help="wait for hyprlock to exit")
    parser.add_argument("--config-only", action="store_true", help="only write the config")
    parser.add_argument("--out", help="config output path")
    parser.add_argument("--status", choices=["battery", "user"], help=argparse.SUPPRESS)
    parser.add_argument("--watch-pid", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--watch-log", default="", help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.watch_pid is not None:
        return watch(args.watch_pid, args.watch_log)
    if args.status == "battery":
        print(battery_status())
        return 0
    if args.status == "user":
        print(user_name())
        return 0

    scheme = read_scheme()
    config = read_config()
    font = str(config.get("theme", {}).get("font", "SF Pro"))
    text = build_config(scheme, font_family=font, screens=screen_configs(config),
                        mode=str(config.get("theme", {}).get("mode", "dark")),
                        icon_font=str(config.get("theme", {}).get("iconFont", "CaskaydiaCove Nerd Font")),
                        transparency=config.get("theme", {}).get("transparency", 0.88),
                        background_opacity=config.get("bar", {}).get("opacity", 1))
    target = output_path(args.out)
    wrote(target, text)

    if args.config_only:
        print(json.dumps({"ok": True, "config": str(target)}))
        return 0

    binary = os.environ.get("HYPRLOCK_BIN") or shutil.which("hyprlock")
    if not binary:
        ipc_call("lockState", "false")
        print(json.dumps({"ok": False, "error": "hyprlock not found"}))
        return 1

    log_path = ""
    try:
        log_dir = cache_dir() / "lock"
        log_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix="hyprlock-", suffix=".log", dir=log_dir, delete=False) as log:
            log_path = log.name
            # Fade-in also enables Hyprlock's pre-lock screencopy: its native
            # background renderer crossfades the completed curtain to wallpaper.
            process = subprocess.Popen([binary, "--config", str(target)], stdout=log, stderr=subprocess.STDOUT)
    except OSError as error:
        ipc_call("lockState", "false")
        if log_path:
            Path(log_path).unlink(missing_ok=True)
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1

    time.sleep(0.1)
    if process.poll() is not None:
        ipc_call("lockState", "false")
        Path(log_path).unlink(missing_ok=True)
        print(json.dumps({"ok": False, "error": "hyprlock exited immediately"}))
        return 1

    if args.wait:
        watch(process.pid, log_path)
        return process.wait()

    subprocess.Popen(
        watcher_command(process.pid, log_path),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    print(json.dumps({"ok": True, "pid": process.pid, "config": str(target)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
