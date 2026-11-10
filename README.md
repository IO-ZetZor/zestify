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

Release notes: [`v1.0`](docs/releases/v1.0.md).

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
| `Super + P` | Capture a screenshot |

You can also lock by holding the left mouse button at the top edge of any
monitor and pulling down. After about 180 pixels, release to let the curtain
slide the rest of the way down and lock. It follows your cursor for as long as
you hold the button. Releasing before the threshold or pressing `Esc` slides
the curtain back up.

The curtain blurs the live windows underneath it. Its tint and the lock screen's
full-screen tint use the same transparency settings as the pill. On release,
the drag controls fade into the password form, then Hyprlock crossfades from
the completed curtain to each monitor's wallpaper.

Hyprlock uses each monitor's current wallpaper and palette. The active monitor
shows the password card; the other screens show their own blurred wallpaper,
clock and date. The lock screen includes battery status, a clickable keyboard
layout, an amber password outline when Caps Lock is on, authentication feedback,
and a Sleep button.

Other surfaces are available from the pill, or through the CLI, for example:

```sh
zesti shell open system
zesti shell open audio
zesti shell open calendar
```

Pull right from the left edge of any display to open notification history.
The drawer follows your drag and settles with a small spring bounce when you
release. Pull its right-side handle left to close it, click outside, press
`Esc`, or use **Close**. **Do not disturb** pauses popups while keeping history;
**Clear all** dismisses the saved notifications. Popups pause their timeout
while hovered. Notification history lives in this drawer, separate from the pill.

Now playing uses a rotating circular album cover with a border that follows
the current monitor's wallpaper accent color. Rotation pauses with playback
and when the view is hidden.
The expanded player shows lyrics from player metadata or LRCLIB, highlights
synchronized lines, and lets you click a timed line to seek. Online lookups
send the track title, artist, album, and duration to `lrclib.net` only while a
media view is visible; missing lyrics and connection failures have explicit states.

The System surface shows a card for each GPU, including integrated and discrete
adapters on hybrid systems. Cards show usage history, GPU temperature, and GPU
memory when the driver provides them. AMD uses sysfs; Intel and other DRM drivers
use readable process `fdinfo` counters for usage (labelled “Visible clients”, since
other users' processes may be inaccessible). Proprietary NVIDIA telemetry uses
optional `nvidia-smi`. Missing readings are shown as unavailable, and runtime
suspended GPUs show “Sleeping” without being woken to collect telemetry.
GPU cards shrink when temperature and memory telemetry are unavailable.

Use **Speed test** in the System network section or the Network surface to
estimate download/upload speed and latency against Cloudflare. Tests run only
when requested, support cancellation, and need no additional packages. A test
can transfer up to about 43 MiB down and 27 MiB up.

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

Application colours follow the primary monitor's wallpaper and `theme.mode`.
Primary/global wallpaper changes apply templates automatically; secondary
monitor changes keep their palette local. Dark/light settings reapply the app
palette. To reapply the current colours manually:

```sh
zesti theme apply
zesti theme list
```

Templates update Kitty, GTK 3/4, Qt engine, Fuzzel, cava, configured Zen profiles,
and configured Spicetify installations. Spotify keeps the selected theme's CSS, JS and assets in a
Zestify theme and follows its palette; a running client restarts after changes,
while a closed client stays closed. Kitty reloads its
colours in running instances. Standalone cava reloads its colours without
restarting audio processing; the shell visualiser gets its colours directly
from QML. Fuzzel reads the current colours when opened. Qt apps require the Qt
engine platform-theme plugin, which watches its palette file.

GTK uses generated themes based on the current GTK style and publishes native
dark/light settings. Alternating two theme slots on palette changes lets GTK 3
apps and Zen refresh their native colours. Existing GTK 3 apps need reopening
once after migrating from the old user-CSS import. GTK 4/libadwaita apps follow
the system mode live, but may need reopening for exact custom palette changes.
Zen uses a managed `userChrome.css` import and a marked `user.js` block in each
profile. Restart Zen once after the first apply; subsequent palette and mode
changes follow native GTK notifications without browser restarts. Zen requires
the GTK target to be enabled. Its palette roles keep ordinary text separate
from accent text and let Zen Mods, including Transparent Zen, control opacity,
gradients and layout. Zen Internet's page transparency remains untouched.
Changes to the integration stylesheet require a browser restart; ordinary
palette changes do not. No webpage colours or browser data are changed.

Generated includes preserve
existing fonts, styling and other app settings, with an initial `.zestify.bak`
backup for modified configs. Set `theme.apply` to `false` to disable automatic
application theming, or to an object such as `{"gtk": {"enabled": false}}` to
disable individual targets. Target names and paths are shown by `theme list`.
The shell also applies the current app palette when it starts. For sessions
using a custom XDG config directory, the shell passes `ZESTI_DESKTOP_CONFIG_HOME`
to its CLI children; a manual CLI using that directory can set the same variable
to publish GTK settings. Temporary XDG homes do not change the regular desktop
session's GTK settings by default. The Hyprland template remains a rendered
state file and does not change compositor settings.

## Development

Run the full test suite (Python + QML + qmllint):

```sh
./scripts/test.sh
```

Focused native media/notification checks and rendered previews:

```sh
python3 tests/quickshell/run-media-ui.py
sh tests/quickshell/run-drawer.sh  # active Hyprland session; restores the pointer
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
