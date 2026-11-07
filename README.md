# Zestify

A minimal, hand-built Quickshell shell for Hyprland: one centered pill per
monitor, a wallpaper-derived palette, native animated wallpaper backgrounds,
and compact surfaces for the things you reach for most.

Zestify replaces the Caelestia shell UI. It is designed for a single
Quickshell process and does not depend on the Caelestia QML modules or CLI.

## Status

The v1 scope is implemented: the bar, theming, wallpaper backend,
system/media/audio/calendar surfaces, launcher, session handling,
notifications/OSD/tray, power surface, and installer. Acceptance and measured
performance results, including known misses, live in
[`docs/acceptance.md`](docs/acceptance.md).

Implementation notes live in `docs/superpowers/`.

## Requirements

- Hyprland with Lua configuration support
- Quickshell (`qs`) and Qt 6
- `hyprlock`
- `python3`
- `ffmpeg`
- `jq`
- `brightnessctl`
- PipeWire + WirePlumber (`wpctl`)
- Nerd Fonts: CaskaydiaCove Nerd Font, plus the configured UI/mono fonts

## Install

From the repository root:

```sh
./install.sh
```

The installer:

- links `~/.config/quickshell/zestify` to this repository's `shell/`
- links `~/.local/bin/zesti` to `bin/zesti` (canonical CLI)
- links `~/.local/bin/zestify` to `bin/zestify` (compatibility entry point)
- copies `hypr/zestify.lua` to `~/.config/hypr/conf/zestify.lua`
- adds marked include/autostart blocks to the Hyprland Lua configs
- creates `~/.config/zestify/config.json` from `config/default.json` if absent
- migrates the current Caelestia wallpaper state once (copy-only; Caelestia is
  never modified or deleted)
- starts Zestify via `zesti shell start`, replacing a running Caelestia shell

Useful options:

```sh
./install.sh --dry-run    # print every action, write nothing
./install.sh --no-start   # install files but do not start the shell
```

Modified Hyprland files are backed up as `*.zestify.bak.<timestamp>`.
Re-running the installer is safe: marked blocks are not duplicated and user
edits outside them are preserved.

## Uninstall

```sh
./uninstall.sh
```

This stops Zestify, removes both CLI links (`zesti` and `zestify`) and its
Lua include, removes only the marked Hyprland blocks, and restores the original
Caelestia autostart line. Configuration, state, and cache are kept unless you
pass `--purge`:

```sh
./uninstall.sh --purge
```

Caelestia is not restored or restarted by the uninstaller; Zestify is the
owned installation.

## Keybinds

The installed Lua file adds:

| Binding | Action |
| --- | --- |
| `Super + Escape` | Lock the session |
| `Super + D` | Open the launcher |
| `Super + W` | Open the wallpaper studio |

Other surfaces are available from the pill, or through the CLI, for example:

```sh
zesti shell open system
zesti shell open audio
zesti shell open calendar
```

The canonical CLI is `zesti`; `zestify` remains as a silent compatibility entry
point that translates legacy flat commands (`zestify start`, `zestify ipc
...`, `zestify wallpaper ...`) into the equivalent `zesti` commands. The shell
and keybindings use `zesti` by default while honoring `ZESTI_BIN`, then the old
`ZESTIFY_BIN` override.

`zesti shell start|stop|restart|status|logs` control the Quickshell process
(config/IPC target stays `zestify`). `zesti wallpaper list|set|random|get`,
`zesti theme ...`, `zesti scheme list|get|set|apply`, `zesti capture
screenshot|record start|stop|toggle|pause`, `zesti clipboard pick|delete`,
`zesti emoji list|pick|fetch`, `zesti workspace toggle`, `zesti window
resize`, `zesti lock|sleep|volume|mic|brightness`, `zesti config
path|show|validate|edit`, `zesti cache status|clean`, and `zesti
doctor|version|install|update|uninstall` cover the remaining capabilities.
Run `zesti --help` for the full command tree.

## Configuration

User configuration lives at:

```text
~/.config/zestify/config.json
```

It is merged over `config/default.json`, so partial files are fine. Settings
cover the bar, theme/fonts, wallpaper directory and proxy options, polling
intervals, notifications, OSD, power confirmation, and session idle timeouts.

State and caches:

```text
~/.local/state/zestify/        # install/session state
~/.cache/zestify/wallpapers/   # generated video proxies
~/.cache/zestify/lock/         # cached lock-screen frames
```

The wallpaper directory defaults to `~/Pictures/Wallpapers` and can be changed
under `wallpaper.dir`.

## Development

Run the full test suite (Python + QML + qmllint):

```sh
./scripts/test.sh
```

Run a development shell without installing:

```sh
PATH="$PWD/bin:$PATH" qs -p "$PWD/shell"
```

The `PATH` prefix is needed because QML invokes the repository's `zestify` CLI.
Open surfaces from another terminal with:

```sh
qs ipc -p "$PWD/shell" call zestify openSurface launcher
```

or start the installed shell:

```sh
zesti shell start
```

## Performance

Sample CPU, RSS, and child processes once per second:

```sh
pid=$(pgrep -f '^qs -p .*zestify/shell$' | head -1)
./scripts/perf-sample.sh "$pid" 60
```

The target and measured numbers are in
[`docs/acceptance.md`](docs/acceptance.md#performance). Video proxies are
generated at the monitor resolution and capped at 30 fps; the original is used
for palette extraction and thumbnails, not steady-state decoding.

## License

GPL-3.0-only. See `LICENSE` and `NOTICE` for credits.
