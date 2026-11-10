"""Canonical Zesti argument parser and command dispatch."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from zesti import __version__, ROOT
from zesti import shell as shell_mod
from zesti import scheme as scheme_mod
from zesti import palette as palette_mod
from zesti import theme as theme_mod
from zesti import wallpaper as wallpaper_mod
from zesti import capture as capture_mod
from zesti import desktop as desktop_mod
from zesti import hypr as hypr_mod
from zesti import controls as controls_mod
from zesti import operations as operations_mod
from zesti.paths import Paths
from zesti.config import load_config
from zesti.palette import PaletteSettings

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_RUNTIME = 1


def _default_run(cmd, **kwargs):  # pragma: no cover - real subprocess path
    import subprocess

    return subprocess.run(cmd, **kwargs).returncode


class FeatureError(Exception):
    """A requested feature is unavailable or failed; exit nonzero with a message."""


def _version_handler(args: argparse.Namespace) -> int:
    print(__version__)
    return EXIT_OK


def _placeholder_handler(args: argparse.Namespace) -> int:
    """Handler for command families not yet wired to an implementation.

    Returns a feature error (exit 1) naming the missing feature instead of
    raising a parser traceback, per the failure-handling policy.
    """
    command = getattr(args, "command", None)
    sub = getattr(args, "subcommand", None)
    target = sub or command
    print(f"zesti: {target}: not yet implemented", file=sys.stderr)
    return EXIT_RUNTIME


def _shell_start(args: argparse.Namespace) -> int:
    return shell_mod.start_shell(args)


def _shell_stop(args: argparse.Namespace) -> int:
    return shell_mod.stop_shell()


def _shell_restart(args: argparse.Namespace) -> int:
    return shell_mod.shell_restart()


def _shell_status(args: argparse.Namespace) -> int:
    return shell_mod.shell_status(json_output=getattr(args, "json", False))


def _shell_logs(args: argparse.Namespace) -> int:
    return shell_mod.shell_logs(args)


def _shell_show(args: argparse.Namespace) -> int:
    return shell_mod.shell_show(args)


def _shell_call(args: argparse.Namespace) -> int:
    return shell_mod.shell_call(args)


def _shell_open(args: argparse.Namespace) -> int:
    return shell_mod.shell_open(args)


def _scheme_data_dir() -> Path:
    return ROOT / "data" / "schemes"


def _scheme_list(args: argparse.Namespace) -> int:
    choices = scheme_mod.list_schemes(_scheme_data_dir())
    out = [{"name": c.name, "flavour": c.flavour} for c in choices]
    print(json.dumps(out, indent=2))
    return EXIT_OK


def _scheme_get(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    name = getattr(args, "name", None)
    if name:
        choices = scheme_mod.list_schemes(_scheme_data_dir())
        match = next((c for c in choices if c.name == name), None)
        if match is None:
            print(f"zesti: scheme: no static scheme named {name!r}", file=sys.stderr)
            return EXIT_RUNTIME
        scheme = json.loads(match.path.read_text())
    else:
        scheme = scheme_mod.load_scheme(paths)
    print(json.dumps(scheme, indent=2))
    return EXIT_OK


def _scheme_set(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    variant = getattr(args, "variant", None)
    mode = getattr(args, "mode", "smart")
    try:
        if variant == "random":
            resolved = scheme_mod.select_variant("random")
        else:
            scheme_mod.validate_variant(variant)
            resolved = variant
    except (TypeError, ValueError) as exc:
        print(f"zesti: scheme set: {exc}", file=sys.stderr)
        return EXIT_RUNTIME
    scheme = {
        "name": "user",
        "flavour": resolved,
        "mode": mode,
        "variant": resolved,
        "colours": {},
    }
    scheme_mod.save_scheme(paths, scheme)
    print(json.dumps(scheme, indent=2))
    return EXIT_OK


def _scheme_apply(args: argparse.Namespace) -> int:
    return _theme_apply(args)


def _app_scheme(paths: Paths, config: dict) -> dict:
    # Primary overrides select app colours; secondary overrides and focus do not.
    primary = config.get("monitor", {}).get("primary", "eDP-1")
    slug = wallpaper_mod.monitor_slug(primary)
    monitor = paths.monitor_dir / f"{slug}-scheme.json"
    override = paths.monitor_dir / f"{slug}.txt"
    if override.exists() and override.read_text().strip() and monitor.exists():
        return json.loads(monitor.read_text())
    return scheme_mod.load_scheme(paths)


def _theme_apply(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    config = load_config(ROOT / "config/default.json", paths.config_file)
    results = theme_mod.apply_theme(_app_scheme(paths, config), paths, config, _default_run)
    _theme_errors(results)
    ok = all(result["ok"] for result in results)
    print(json.dumps({"ok": ok, "targets": results}, indent=2))
    return EXIT_OK if ok else EXIT_RUNTIME


def _theme_list(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    config = load_config(ROOT / "config/default.json", paths.config_file)
    print(json.dumps([{"name": t.name, "enabled": t.enabled, "output": str(t.output)}
                      for t in theme_mod.theme_targets(paths, config)], indent=2))
    return EXIT_OK


def _theme_show(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    config = load_config(ROOT / "config/default.json", paths.config_file)
    colours, mode = theme_mod.scheme_colours(_app_scheme(paths, config), config)
    print(json.dumps({"mode": mode, "colours": colours}, indent=2))
    return EXIT_OK


def _theme_errors(results: list) -> None:
    for result in results:
        if not result.get("ok"):
            print(f"zesti: theme {result.get('target', 'apply')}: {result.get('error')}", file=sys.stderr)
        elif result.get("restart_required"):
            print(f"zesti: theme {result['target']}: restart Zen to load the updated profile theme; later palette changes update live", file=sys.stderr)


def _make_theme_applier(paths: Paths):
    def apply(scheme: dict) -> list:
        try:
            config = load_config(ROOT / "config" / "default.json", paths.config_file)
        except (OSError, ValueError) as exc:
            raise theme_mod.ThemeError(f"cannot load theme configuration: {exc}") from exc
        if config.get("theme", {}).get("apply") is False:
            return []
        results = theme_mod.apply_theme(scheme, paths, config, _default_run)
        _theme_errors(results)
        return results

    return apply


def _wallpaper_services() -> wallpaper_mod.WallpaperServices:
    paths = Paths.from_env(os.environ)
    try:
        config = load_config(ROOT / "config" / "default.json", paths.config_file)
    except (OSError, ValueError):
        config = {}
    mode = config.get("theme", {}).get("mode", "dark")
    if mode not in ("dark", "light"):
        mode = "dark"

    def generate(source, settings, run):
        payload = palette_mod.generate_palette(source, settings, run)
        palettes = {}
        for variant in ("dark", "light"):
            metadata = palette_mod.SchemeMetadata(
                name=source.stem, flavour=settings.variant, mode=variant,
                variant=settings.variant, colours=len(payload["colors"]),
            )
            colours = palette_mod.normalize_matugen(payload, variant, metadata)
            colours.pop("metadata")
            palettes[variant] = colours
        return {
            "name": source.stem, "flavour": settings.variant,
            "mode": mode, "variant": settings.variant,
            "colours": palettes[mode], "palettes": palettes,
        }

    return wallpaper_mod.WallpaperServices(
        generate_palette=generate,
        save_scheme=scheme_mod.save_scheme,
        theme_applier=_make_theme_applier(paths),
        run=_default_run,
        primary_monitor=config.get("monitor", {}).get("primary", "eDP-1"),
    )


def _wallpaper_config_dir(paths: Paths) -> Path:
    try:
        config = load_config(ROOT / "config" / "default.json", paths.config_file)
    except (OSError, ValueError):
        config = {}
    raw = str(config.get("wallpaper", {}).get("dir", "~/Pictures/Wallpapers"))
    return Path(raw).expanduser()


def _wallpaper_list(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    services = _wallpaper_services()
    directory = Path(getattr(args, "dir", None) or _wallpaper_config_dir(paths))
    items = wallpaper_mod.list_wallpapers(directory, paths, services.run)
    print(json.dumps(items, indent=2))
    return EXIT_OK


def _wallpaper_get(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    wallpaper = wallpaper_mod.effective_wallpaper(paths, getattr(args, "monitor", None))
    if wallpaper is None:
        print("zesti: wallpaper: no current wallpaper", file=sys.stderr)
        return EXIT_RUNTIME
    print(str(wallpaper))
    return EXIT_OK


def _wallpaper_set(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    services = _wallpaper_services()
    if getattr(args, "all", False):
        target = wallpaper_mod.WallpaperTarget("all")
    elif getattr(args, "monitor", None):
        target = wallpaper_mod.WallpaperTarget("monitor", args.monitor)
    else:
        target = wallpaper_mod.WallpaperTarget("global")
    result = wallpaper_mod.set_wallpaper(Path(args.file).expanduser(), target, paths, services)
    print(json.dumps(result, indent=2))
    return EXIT_OK if result["ok"] else EXIT_RUNTIME


def _wallpaper_random(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    services = _wallpaper_services()
    directory = Path(getattr(args, "dir", None) or _wallpaper_config_dir(paths))
    no_filter = bool(getattr(args, "no_filter", False))
    if getattr(args, "all", False):
        target = wallpaper_mod.WallpaperTarget("all", random=True, no_filter=no_filter)
    elif getattr(args, "monitor", None):
        target = wallpaper_mod.WallpaperTarget(
            "monitor", args.monitor, random=True, no_filter=no_filter
        )
    else:
        target = wallpaper_mod.WallpaperTarget("random", no_filter=no_filter)
    result = wallpaper_mod.set_wallpaper(directory, target, paths, services)
    print(json.dumps(result, indent=2))
    return EXIT_OK if result["ok"] else EXIT_RUNTIME


def _wallpaper_thumb(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    services = _wallpaper_services()
    thumb = wallpaper_mod.make_thumbnail(Path(args.file).expanduser(), paths, services.run)
    print(json.dumps({"ok": True, "thumb": str(thumb)}))
    return EXIT_OK


def _wallpaper_print(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    services = _wallpaper_services()
    settings = PaletteSettings(
        mode=getattr(args, "mode", "smart"), variant=getattr(args, "variant", "tonalspot")
    )
    try:
        payload = palette_mod.generate_palette(
            Path(args.file).expanduser(), settings, services.run
        )
    except palette_mod.PaletteError as exc:
        print(f"zesti: wallpaper print: {exc}", file=sys.stderr)
        return EXIT_RUNTIME
    scheme = palette_mod.normalize_matugen(
        payload,
        settings.mode,
        scheme_mod.SchemeMetadata(
            "print", settings.mode, settings.mode, settings.variant, 0
        ),
    )
    print(json.dumps(scheme, indent=2))
    return EXIT_OK


def _capture_result_dict(result: capture_mod.CaptureResult) -> dict:
    return {
        "ok": result.ok,
        "path": result.path,
        "error": result.error,
        "cancelled": result.cancelled,
    }


def _capture_services() -> capture_mod.CaptureServices:
    return capture_mod.CaptureServices(run=_default_run)


def _capture_screenshot(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    options = capture_mod.ScreenshotOptions(
        region=getattr(args, "region", None), freeze=bool(getattr(args, "freeze", False))
    )
    result = capture_mod.take_screenshot(options, paths, _capture_services())
    print(json.dumps(_capture_result_dict(result), indent=2))
    return EXIT_OK if result.ok else EXIT_RUNTIME


def _capture_record_start(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    options = capture_mod.RecordOptions(
        region=getattr(args, "region", None),
        sound=bool(getattr(args, "sound", False)),
        monitor=getattr(args, "monitor", None),
    )
    result = capture_mod.record_start(options, paths, _capture_services())
    print(json.dumps(_capture_result_dict(result), indent=2))
    return EXIT_OK if result.ok else EXIT_RUNTIME


def _capture_record_stop(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    result = capture_mod.record_stop(
        bool(getattr(args, "clipboard", False)), paths, _capture_services()
    )
    print(json.dumps(_capture_result_dict(result), indent=2))
    return EXIT_OK if result.ok else EXIT_RUNTIME


def _capture_record_toggle(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    result = capture_mod.record_toggle(paths, _capture_services())
    print(json.dumps(_capture_result_dict(result), indent=2))
    return EXIT_OK if result.ok else EXIT_RUNTIME


def _capture_record_pause(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    result = capture_mod.record_pause(paths, _capture_services())
    print(json.dumps(_capture_result_dict(result), indent=2))
    return EXIT_OK if result.ok else EXIT_RUNTIME


def _clipboard_pick(args: argparse.Namespace) -> int:
    return desktop_mod.clipboard_pick(delete=bool(getattr(args, "delete", False)))


def _emoji_list(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    print(desktop_mod.emoji_list(paths), end="")
    return EXIT_OK


def _emoji_pick(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    return desktop_mod.emoji_pick(paths)


def _emoji_fetch(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    return desktop_mod.emoji_fetch(paths, lambda url: "")


def _workspace_toggle(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    config = load_config(ROOT / "config" / "default.json", paths.config_file)
    return desktop_mod.toggle_workspace(args.name, config, hypr_mod.HyprClient())


def _window_resize(args: argparse.Namespace) -> int:
    return desktop_mod.window_resize(args.client, args.action, args.width, args.height)


def _window_pip(args: argparse.Namespace) -> int:
    return desktop_mod.window_pip(args.client)


def _window_watch(args: argparse.Namespace) -> int:
    return desktop_mod.window_watch()


def _run_repo_script(script_name: str, argv: list[str]) -> int:
    return subprocess.run([sys.executable, str(ROOT / "scripts" / f"{script_name}.py")] + argv).returncode


def _proxy_ensure(args: argparse.Namespace) -> int:
    return _run_repo_script("wallpaper-proxy", ["proxy", "ensure", "--source", args.source,
                                                "--width", str(args.width), "--height", str(args.height),
                                                "--codec", args.codec, "--crf", str(args.crf)])


def _proxy(args: argparse.Namespace) -> int:
    if args.proxy_command == "ensure":
        return _proxy_ensure(args)
    print(f"zesti: proxy: unknown subcommand {args.proxy_command!r}", file=sys.stderr)
    return EXIT_RUNTIME


def _cache_status(args: argparse.Namespace) -> int:
    return _run_repo_script("wallpaper-proxy", ["cache", "status"])


def _cache_prune(args: argparse.Namespace) -> int:
    return _run_repo_script("wallpaper-proxy", ["cache", "prune", "--keep", *args.keep])


def _sleep(args: argparse.Namespace) -> int:
    """Lock the session, then suspend (lock-before-sleep per spec)."""
    lock_rc = _run_repo_script("lock", ["--config-only"])
    if lock_rc != 0:
        return lock_rc
    try:
        res = subprocess.run(["systemctl", "suspend-then-hibernate"], capture_output=True, text=True)
        return res.returncode
    except FileNotFoundError:
        print("zesti: sleep: missing dependency: systemctl", file=sys.stderr)
        return 1


def _migrate(args: argparse.Namespace) -> int:
    argv = []
    if args.force:
        argv.append("--force")
    return _run_repo_script("migrate-state", argv)


def _volume(args: argparse.Namespace) -> int:
    if args.action == "set":
        return controls_mod.volume("set", args.value, run=_default_run)
    return controls_mod.volume(args.action, run=_default_run)


def _mic(args: argparse.Namespace) -> int:
    return controls_mod.mic(args.action, run=_default_run)


def _brightness(args: argparse.Namespace) -> int:
    if args.action == "set":
        return controls_mod.brightness("set", args.value, run=_default_run)
    return controls_mod.brightness(args.action, run=_default_run)


def _config(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    action = getattr(args, "action", None) or getattr(args, "subcommand", None)
    rc, out = controls_mod.config_command(action, paths)
    print(out, end="")
    return rc


def _doctor(args: argparse.Namespace) -> int:
    paths = Paths.from_env(os.environ)
    result = operations_mod.doctor(paths, _default_run, json_output=args.json)
    print(result if isinstance(result, str) else json.dumps(result, indent=2))
    return EXIT_OK


def _install(args: argparse.Namespace) -> int:
    return operations_mod.install(ROOT, [], _default_run)


def _update(args: argparse.Namespace) -> int:
    services = {
        "run": _default_run,
        "is_attached": lambda: True,
        "is_dirty": lambda: False,
        "is_detached": lambda: False,
        "has_upstream": lambda: True,
    }
    return operations_mod.update(ROOT, check_only=args.check, services=services)


def _lock(args: argparse.Namespace) -> int:
    """Dispatch ``zesti lock`` to the lock script, forwarding its flags."""
    lock_script = ROOT / "scripts" / "lock.py"
    forward: list[str] = []
    if getattr(args, "wait", False):
        forward.append("--wait")
    if getattr(args, "config_only", False):
        forward.append("--config-only")
    if getattr(args, "out", None):
        forward.extend(["--out", args.out])
    return subprocess.run([sys.executable, str(lock_script)] + forward).returncode


def _add_family(subparsers: argparse._SubParsersAction, name: str, subcommands: list[str]) -> argparse.ArgumentParser:
    """Add a top-level family subparser with its own nested sub-subcommands."""
    family_parser = subparsers.add_parser(name, help=f"{name} commands")
    family_sub = family_parser.add_subparsers(dest="subcommand", required=True)
    for sub in subcommands:
        p = family_sub.add_parser(sub)
        p.set_defaults(func=_placeholder_handler)
    return family_parser


def build_parser(prog: str = "zesti") -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=prog, description="Zesti CLI")
    parser.add_argument("--version", action="version", version=__version__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Shell lifecycle / IPC / surfaces (real handlers; config/IPC stay "zestify").
    shell_parser = subparsers.add_parser("shell", help="shell commands")
    shell_sub = shell_parser.add_subparsers(dest="subcommand", required=True)

    def shell_subparser(name, handler, flags=None):
        p = shell_sub.add_parser(name)
        for flag in (flags or []):
            if flag in ("--json", "--foreground", "--follow"):
                p.add_argument(flag, action="store_true")
            else:
                p.add_argument(flag)
        p.set_defaults(func=handler)
        return p

    shell_subparser("start", _shell_start, ["--foreground", "--log-rules"])
    shell_subparser("stop", _shell_stop)
    shell_subparser("restart", _shell_restart)
    shell_subparser("status", _shell_status, ["--json"])
    shell_subparser("logs", _shell_logs, ["--follow", "--log-rules"])
    shell_subparser("show", _shell_show)
    shell_call_parser = shell_subparser("call", _shell_call)
    shell_call_parser.add_argument("target")
    shell_call_parser.add_argument("function")
    shell_call_parser.add_argument("arg", nargs="*")
    shell_subparser("open", _shell_open, ["SURFACE"])

    # Wallpaper.
    wallpaper_parser = subparsers.add_parser("wallpaper", help="wallpaper commands")
    wallpaper_sub = wallpaper_parser.add_subparsers(dest="subcommand", required=True)
    wl = wallpaper_sub.add_parser("list")
    wl.add_argument("dir", nargs="?")
    wl.add_argument("--json", action="store_true", help="output JSON (always)")
    wl.set_defaults(func=_wallpaper_list)
    wg = wallpaper_sub.add_parser("get")
    wg.add_argument("--monitor")
    wg.set_defaults(func=_wallpaper_get)
    ws = wallpaper_sub.add_parser("set")
    ws.add_argument("file")
    group = ws.add_mutually_exclusive_group()
    group.add_argument("--monitor")
    group.add_argument("--all", action="store_true")
    ws.add_argument("--no-smart", action="store_true")
    ws.set_defaults(func=_wallpaper_set)
    wr = wallpaper_sub.add_parser("random")
    wr.add_argument("dir", nargs="?")
    random_group = wr.add_mutually_exclusive_group()
    random_group.add_argument("--monitor")
    random_group.add_argument("--all", action="store_true")
    wr.add_argument("--no-filter", action="store_true")
    wr.add_argument("--threshold", type=float, default=0.8)
    wr.add_argument("--no-smart", action="store_true")
    wr.set_defaults(func=_wallpaper_random)
    wt = wallpaper_sub.add_parser("thumb")
    wt.add_argument("file")
    wt.set_defaults(func=_wallpaper_thumb)
    wp = wallpaper_sub.add_parser("print")
    wp.add_argument("file")
    wp.add_argument("--mode", default="smart")
    wp.add_argument("--variant", default="tonalspot")
    wp.set_defaults(func=_wallpaper_print)

    # Theme.
    theme_parser = subparsers.add_parser("theme", help="application theme commands")
    theme_sub = theme_parser.add_subparsers(dest="subcommand", required=True)
    for name, handler in (("list", _theme_list), ("show", _theme_show), ("apply", _theme_apply)):
        theme_sub.add_parser(name).set_defaults(func=handler)
    for name in ("set", "generate"):
        theme_sub.add_parser(name).set_defaults(func=_placeholder_handler)

    # Scheme.
    scheme_parser = subparsers.add_parser("scheme", help="scheme commands")
    scheme_sub = scheme_parser.add_subparsers(dest="subcommand", required=True)
    sl = scheme_sub.add_parser("list")
    sl.set_defaults(func=_scheme_list)
    sg = scheme_sub.add_parser("get")
    sg.add_argument("--name")
    sg.set_defaults(func=_scheme_get)
    ss = scheme_sub.add_parser("set")
    ss.add_argument("--variant")
    ss.add_argument("--mode", default="smart")
    ss.set_defaults(func=_scheme_set)
    scheme_sub.add_parser("apply").set_defaults(func=_scheme_apply)

    # Capture (screenshot / record).
    capture_parser = subparsers.add_parser("capture", help="capture commands")
    capture_sub = capture_parser.add_subparsers(dest="subcommand", required=True)
    screenshot_parser = capture_sub.add_parser("screenshot")
    screenshot_parser.add_argument("--region")
    screenshot_parser.add_argument("--freeze", action="store_true")
    screenshot_parser.set_defaults(func=_capture_screenshot)
    record_parser = capture_sub.add_parser("record")
    record_sub = record_parser.add_subparsers(dest="record_subcommand", required=True)
    rs = record_sub.add_parser("start")
    rs.add_argument("--region")
    rs.add_argument("--sound", action="store_true")
    rs.add_argument("--monitor")
    rs.set_defaults(func=_capture_record_start)
    rs = record_sub.add_parser("stop")
    rs.add_argument("--clipboard", action="store_true")
    rs.set_defaults(func=_capture_record_stop)
    record_sub.add_parser("toggle").set_defaults(func=_capture_record_toggle)
    record_sub.add_parser("pause").set_defaults(func=_capture_record_pause)

    # Clipboard.
    clip_parser = subparsers.add_parser("clipboard", help="clipboard commands")
    clip_parser.add_argument("--delete", action="store_true")
    clip_parser.set_defaults(func=_clipboard_pick)

    # Emoji.
    emoji_parser = subparsers.add_parser("emoji", help="emoji commands")
    emoji_sub = emoji_parser.add_subparsers(dest="subcommand", required=True)
    emoji_sub.add_parser("list").set_defaults(func=_emoji_list)
    emoji_sub.add_parser("pick").set_defaults(func=_emoji_pick)
    emoji_sub.add_parser("fetch").set_defaults(func=_emoji_fetch)

    # Workspace.
    ws_parser = subparsers.add_parser("workspace", help="workspace commands")
    ws_sub = ws_parser.add_subparsers(dest="subcommand", required=True)
    wt = ws_sub.add_parser("toggle")
    wt.add_argument("name")
    wt.set_defaults(func=_workspace_toggle)

    # Window.
    win_parser = subparsers.add_parser("window", help="window commands")
    win_sub = win_parser.add_subparsers(dest="subcommand", required=True)
    wr = win_sub.add_parser("resize")
    wr.add_argument("client")
    wr.add_argument("action")
    wr.add_argument("width", type=int)
    wr.add_argument("height", type=int)
    wr.set_defaults(func=_window_resize)
    wpip = win_sub.add_parser("pip")
    wpip.add_argument("client")
    wpip.set_defaults(func=_window_pip)
    win_sub.add_parser("watch").set_defaults(func=_window_watch)

    # Standalone control commands.
    sp = subparsers.add_parser("sleep")
    sp.set_defaults(func=_sleep)
    for name, handler in [("volume", _volume), ("mic", _mic), ("brightness", _brightness)]:
        p = subparsers.add_parser(name)
        p.add_argument("action")
        p.add_argument("value", nargs="?")
        p.set_defaults(func=handler)

    # Lock dispatches to scripts/lock.py (Zestify state, no Caelestia).
    lock_parser = subparsers.add_parser("lock", help="lock the session")
    lock_parser.add_argument("--wait", action="store_true")
    lock_parser.add_argument("--config-only", action="store_true")
    lock_parser.add_argument("--out")
    lock_parser.set_defaults(func=_lock)

    # Config.
    cfg_parser = subparsers.add_parser("config", help="config commands")
    cfg_sub = cfg_parser.add_subparsers(dest="subcommand", required=True)
    for action in ["path", "show", "validate", "edit"]:
        p = cfg_sub.add_parser(action)
        p.set_defaults(func=_config)

    # Proxy.
    proxy_parser = subparsers.add_parser("proxy", help="wallpaper proxy commands")
    proxy_sub = proxy_parser.add_subparsers(dest="proxy_command", required=True)
    pe = proxy_sub.add_parser("ensure")
    pe.add_argument("--source", required=True)
    pe.add_argument("--width", required=True, type=int)
    pe.add_argument("--height", required=True, type=int)
    pe.add_argument("--codec", default="h264", choices=["h264", "h265", "hevc"])
    pe.add_argument("--crf", default=20, type=int)
    pe.set_defaults(func=_proxy)

    # Cache.
    cache_parser = subparsers.add_parser("cache", help="cache commands")
    cache_sub = cache_parser.add_subparsers(dest="cache_command", required=True)
    cache_sub.add_parser("status").set_defaults(func=_cache_status)
    cache_prune = cache_sub.add_parser("prune")
    cache_prune.add_argument("--keep", action="append", default=[])
    cache_prune.set_defaults(func=_cache_prune)

    # Operational commands.
    doc = subparsers.add_parser("doctor")
    doc.add_argument("--json", action="store_true")
    doc.set_defaults(func=_doctor)
    subparsers.add_parser("install").set_defaults(func=_install)
    sup = subparsers.add_parser("update")
    sup.add_argument("--check", action="store_true")
    sup.set_defaults(func=_update)
    mp = subparsers.add_parser("migrate")
    mp.add_argument("--force", action="store_true")
    mp.set_defaults(func=_migrate)
    p = subparsers.add_parser("version")
    p.set_defaults(func=_version_handler)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else EXIT_USAGE
    func = getattr(args, "func", None)
    if func is None:
        parser.print_help(sys.stderr)
        return EXIT_USAGE
    try:
        return func(args)
    except FeatureError as exc:
        print(f"zesti: {exc}", file=sys.stderr)
        return EXIT_RUNTIME
    except BrokenPipeError:
        return EXIT_OK
    except (theme_mod.ThemeError, OSError, ValueError) as exc:
        print(f"zesti: {exc}", file=sys.stderr)
        return EXIT_RUNTIME


if __name__ == "__main__":
    sys.exit(main())
