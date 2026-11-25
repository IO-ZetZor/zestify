# Zestify

A minimal, hand-built Quickshell shell for Hyprland: a centered pill on the
primary monitor, focus cards on secondary displays, a wallpaper-derived palette,
native animated wallpaper backgrounds,
and compact surfaces for the things you reach for most.

The pill uses a monochrome Rem launcher icon and omits window titles and resource
readings. A pulsing CPU icon appears only above 90% usage; click it to open System.
While media is playing, small visualiser bars fill the gap beside the clock and fade
out when the hover panel opens. Workspace numbers use the configured mono font.

Zestify is a standalone shell. It runs as a single Quickshell process and
does not depend on any external shell UI, QML modules, or CLI.

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
- Quickshell (`qs`, 0.3.1+) with Wayland session-lock and PAM support, and Qt 6
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
- migrates wallpaper state from a previous installation once (copy-only; the
  old files are never modified or deleted)
- starts Zestify via `zesti shell start`, replacing a running legacy shell

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
Lua include, and removes only the marked Hyprland blocks. Configuration, state,
and cache are kept unless you pass `--purge`:

```sh
./uninstall.sh --purge
```

The previous shell is not restored or restarted by the uninstaller; Zestify
is the owned installation.

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
the drag controls fade into the native password form as the curtain blends into
each monitor's blurred wallpaper. The same QML face and tint continue on the
secure Wayland lock surface.
After authentication, the lock screen fades smoothly into the desktop over
700 ms. Each output's exit frame is ready before the native lock is released,
so the transition keeps the wallpaper visible throughout.

Zestify uses each monitor's current wallpaper and palette. The active monitor
shows the password card; the other screens show their own blurred wallpaper,
clock and date. The lock screen includes battery status, a clickable keyboard
layout, an amber password outline when Caps Lock is on, authentication feedback,
and a Sleep button. Click another monitor to move the password form there.
Passwords are checked by Quickshell's PAM conversation using the system's
`/etc/pam.d/login` policy, including additional authentication prompts. Escape
clears the input or cancels an authentication attempt while the session stays locked.

`zesti lock` returns after the compositor confirms every output is covered;
`zesti lock --wait` also waits for unlock. `zesti sleep` waits for that confirmation
before suspending. A running Zestify shell is required. The old generated-lock-config
options (`--config-only`, `--out`) have been removed.

The compositor keeps the session locked if the shell crashes or stops while
locked. QML reloads retain the lock. To recover after a crash on Hyprland, use
another TTY to run `zesti shell start` with the graphical session's environment,
then `zesti lock`; authenticate on the replacement lock screen.
The installed Lua integration enables `misc.allow_session_lock_restore` for this
recovery. Existing installations should rerun `./install.sh --no-start` and reload
Hyprland; development sessions should enable that option themselves.

Idle suspend and critical-battery hibernation also wait for lock confirmation when
`session.lockBeforeSleep` is enabled. The logind watcher uses `systemd-inhibit` to
delay externally requested sleep until locking finishes. This requires access to
logind; its configured maximum delay still applies if locking fails.

Choose Wallpaper from the right-edge shortcut drawer, press `Super + W`, or run
`zesti shell open wallpaper`. The picker opens over a blurred backdrop, with a
large circular preview and up to nine smaller choices along a curved orbit.
Click a circle, drag the orbit, use the wheel, or press an arrow key to choose.
The applied wallpaper opens selected; images and videos share the collection.
Selected videos play muted inside the circular preview while the picker is open.
Click **Apply** or press Enter for this display; **All displays** or Shift+Enter
applies everywhere. Clicking the large preview also applies to this display.
Apply fades the picker away in 140 ms. Failed applications bring it back with
the selected wallpaper and an error message. Thumbnails fade in as they enter
the carousel and as their images load.
Escape or a click outside cancels; R rescans the wallpaper folder.

Browsing previews the shell palette without changing saved wallpaper paths or
application themes. As you browse, Zestify prepares cached transition maps.
Apply fades the picker immediately, waits for those maps before changing the
saved wallpaper, then runs the bundled transition shader: BiRefNet identifies
the subject, a thin line draws its silhouette,
the subject fills inward, and the background spreads outward. Images without
a clear subject use the shader's pixel-colony effect. Video maps come from a
cached frame; videos retain the existing proxy, mute and power-saving behavior.
One background worker prepares maps for all displays, and each transition keeps
the outgoing wallpaper until the new media and both maps are ready.

Install the isolated subject-segmentation runtime and model once:

```sh
zesti wallpaper effects setup
```

It uses `uv` when available to install a compatible Python and the CPU inference
dependencies under `$XDG_DATA_HOME/zestify/wallfx` (normally
`~/.local/share/zestify/wallfx`). Maps and subject masks live under
`$XDG_CACHE_HOME/zestify/wallfx`. Later changes reuse those cached masks.
Preparation never downloads dependencies or models implicitly. If the runtime
is unavailable, wallpapers use the colony effect; a map-loading/helper failure
uses a short fade so the requested wallpaper still applies.

Prepare an image or video's maps directly with
`zesti wallpaper effects prepare --source /path/to/wallpaper`. `--no-inference`
uses existing maps or the colony effect without running BiRefNet.

Other surfaces are available from the pill, or through the CLI, for example:

```sh
zesti shell open system
zesti shell open audio
zesti shell open calendar
```

Secondary displays show a compact focus card by default. Click it to enter one
task and start a 25-minute, 50-minute or custom countdown (1–240 minutes), or
choose Stopwatch for open-ended work. Hover to pause/resume, edit the task or end
the session. A countdown finishes with a notification; **Take a break** starts a
five-minute break and **Keep going** starts another focus interval. Neither starts
automatically. Fullscreen hides the card while its timer continues.

**Do not disturb during focus** temporarily pauses notification popups while
keeping history. Your saved DND setting remains intact and applies again when the
session ends or during a break. Continuing reuses the session's quiet choice.
The task is saved; the timer is shared across focus cards and survives display
mode changes and monitor disconnects, but ends when the shell restarts.

In Settings, **Display widgets** lets each secondary monitor use **Focus**,
**Full pill**, or **None**. **Monitor → Secondary mode** controls the default for
displays without an override; **Focus** controls the default timer mode, duration
and DND choice. The attached primary display keeps its full pill. If the configured
primary is disconnected, the first attached display takes over. Notification,
power, shortcut and lock edge gestures remain available in all display modes.

Pull right from the left edge of any display to open notification history.
The drawer follows your drag and settles with a small spring bounce when you
release. Pull its right-side handle left to close it, click outside, press
`Esc`, or use **Close**. **Do not disturb** pauses popups while keeping history;
**Clear all** dismisses the saved notifications. Popups pause their timeout
while hovered. Notification history lives in this drawer, separate from the pill.

Pull up from the bottom edge of any display to open the power menu. It follows
your drag and settles with the same spring bounce as notifications. Pull the
top handle down to close it, click outside, or press `Esc`. Lock and Sleep are
available alongside hold-to-confirm Log out, Restart, and Shut down actions.
The compact menu includes a sharpened 1280 × 716 Rem (Re:ZERO) GIF, upscaled from
the 640 × 358 source, that plays while visible. Drag the portrait left or right to
turn it like a thick coin; on release it flips to the closest face, original or
mirrored. Double-click or press `Home` to return to the original face. With the
portrait focused, the arrow keys flip between the two faces.
The power menu is separate from the pill; `zesti shell open power` opens it too.

Pull left from the right edge of any display to open the shortcut drawer.
Its five icons are stacked vertically: Screenshot, Screen recording, Wallpaper,
Settings, and System. Screenshot captures the focused display; Screen recording starts
or stops recording that display, including system audio by default. Use
`zesti capture record start --no-sound` for a silent recording; `--sound` remains
available. Custom `record.extraArgs` can still add microphone audio.
The drawer closes before capture begins.
Notifications confirm screenshots, recording starts, and saved recordings.
While recording, the film camera icon turns red with a status dot; a red dot
also remains at the right edge when the drawer is closed. Recording status
follows the owned recorder, including recordings started through the CLI.
Settings has moved here from the pill, and System is always available here.
Pull the left handle right to close it, click outside, or press `Esc`.
The drawer uses the same spring motion as the power menu and can also be opened
with `zesti shell open shortcuts`.

Now playing uses a rotating circular album cover with a border that follows
the current monitor's wallpaper accent color. Rotation pauses with playback
and when the view is hidden.
The expanded player shows lyrics from player metadata or LRCLIB, highlights
synchronized lines, and lets you click a timed line to seek. Online lookups
send the track title, artist, album, and duration to `lrclib.net` only while a
media view is visible; missing lyrics and connection failures have explicit states.

Hold an album cover to enter party mode on that monitor. The pill unfolds into
a large cover as its icons fall away, with visualiser bars on all four screen
edges and lyrics below the cover when available. Bass hits drive a quick zoom,
brief shake and directional motion blur, scaled by the hit's level and rise
above the surrounding bass. Softer accents stay subtle; rising kicks gain
punch as they reach their peak. Fast beat runs shorten and soften the motion
and blend camera movement from the first quick follow-up, with limited zoom
speed and eased shake direction. Crescendos gently build zoom before a drop.
Held notes, pitch movement without added bass energy, and small bass ripples
do not keep retriggering impacts. Rhythm confidence follows recurring salient
attacks separately from transient spacing; uncertain rhythm reduces recoil.
The background tint rises and fades gradually through rapid beat runs.
On exit, the elements return to their live slots and rebuild the pill before
its controls become visible. Transition blur stays short and uses a fixed-size
cover texture so the falling and returning elements stay crisp.
Hold the large cover again or press `Esc` to exit. Pause, muted or zero-volume
output, fallback animation and stale audio stop impacts; changing tracks clears
the motion history. Party capture uses fixed-gain 16-bit frequency magnitudes
for impact strength and normalizes the displayed bars separately. Magnitudes
are not calibrated loudness; dense mixes can still obscure individual kicks.

The System surface shows a card for each GPU, including integrated and discrete
adapters on hybrid systems. Cards show usage history, GPU temperature, and GPU
memory when the driver provides them. AMD uses sysfs; Intel and other DRM drivers
use readable process `fdinfo` counters for usage (labelled “Visible clients”, since
other users' processes may be inaccessible). Proprietary NVIDIA telemetry uses
optional `nvidia-smi`. Missing readings are shown as unavailable, and runtime
suspended GPUs show “Sleeping” without being woken to collect telemetry.
GPU cards shrink when temperature and memory telemetry are unavailable.
GPU collection runs only while the System surface is visible and sampling is
enabled. Closing it, locking, or turning displays off stops the GPU helper and
clears its history; CPU/RAM sampling continues. Reopening starts fresh GPU
history at the configured polling interval.

See the [full CPU, GPU, RAM and UI performance analysis](docs/performance-analysis-2026-11-13.md)
for live process measurements, controlled surface/effect comparisons, applied
optimizations, and the assessment of C++ for remaining hot paths.
The [rendering optimization report](docs/render-optimizations-2026-11-14.md)
covers blur caching, partial graph updates, static content, album-cover layers
and graph damage tracking, including measurements and the pill animation fix.

The Battery surface includes Power saver, Balanced, and Performance profile
controls, with the active profile updated live. Performance is disabled when
unsupported, and thermal or lap-detection limits are shown below the controls.
Profile switching requires a running `power-profiles-daemon` service (or a
compatible provider such as `tuned-ppd`).
Run `python3 tests/quickshell/run-battery-ui.py` to exercise the controls with
a mock service and save a preview to `/tmp/zestify-battery-preview.png`.

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
screenshot|record start|stop|toggle|pause|status`, `zesti clipboard pick|delete`,
`zesti emoji list|pick|fetch`, `zesti workspace toggle`, `zesti window
resize`, `zesti lock|sleep|volume|mic|brightness`, `zesti config
path|show|validate|edit`, `zesti cache status|prune`, and `zesti
doctor|version|install|update` cover the remaining capabilities.
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

Video wallpaper proxies default to a maximum of **24 FPS** to reduce continuous
decoding and rendering. Settings → Wallpaper → Proxy → **Max fps** accepts 1–60;
set 30 to restore the previous limit, or 15 for less GPU work with less smooth
motion. Videos below the selected frame rate retain their original rate. The
shell displays a paused frame while preparing a proxy and resumes when it is ready.

For larger displays, set `wallpaper.proxy.resolution` to `"1080p"` or `"720p"`
to lower decoded resolution. These presets preserve display orientation and
aspect ratio, avoid upscaling, and use even dimensions. `"monitor"` retains full
display resolution; explicit values such as `"1280x720"` remain supported.
For example, `"1080p"` on a 1920×1200 display produces 1728×1080 video, while
`"720p"` produces 1152×720. Lower resolution trades some sharpness for lower load.

`wallpaper.pauseWhenObscured: "any-window"` pauses video whenever that workspace
has a window; the default `"fullscreen"` pauses when covered by fullscreen.
Proxy settings apply to video wallpapers when `wallpaper.proxy.enabled` is true.
Changing frame rate or resolution selects a matching cached proxy or generates
a new one. The direct CLI also accepts `zesti proxy ensure ... --max-fps 24`.
H.264 proxies use 8-bit 4:2:0 pixels for common hardware-decoder compatibility;
this reduces color precision for higher-depth sources. H.265 retains source depth.
See [measured GPU and CPU results](docs/wallpaper-gpu-measurements-2026-11-13.md)
for comparisons using a video wallpaper on the installed Intel GPU.

Settings → Theme → **Smart scheme** automatically selects a neutral, content,
or tonal-spot palette according to the wallpaper's colourfulness.
It is on by default (`theme.smartScheme: true`). Turn it off to use tonal-spot
for every wallpaper; `zesti wallpaper set|random --no-smart` overrides it for
one change. The Dark/Light setting continues to control appearance. Palettes
use source-colour scoring, hard surfaces, and harmonized terminal colours. Changing the toggle or starting the shell refreshes current global
and monitor palettes. To regenerate them manually, run `zesti wallpaper refresh`.

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

An optional Dolphin profile adds rounded controls, removes the toolbar separator,
and installs minimal outline folder/file icons that follow the Qt palette. Enable
it with `"dolphin": {"enabled": true}` in `theme.apply`, then run `zesti theme apply`.
It requires KDE's Qt 6 Breeze style and `qdbus6`. Breeze provides translucent,
rounded folder selections that keep palette-coloured icons visible. The launcher
applies the control stylesheet only to Dolphin's main window, so its graphics
items retain native Breeze selection painting.
The desktop launcher and FileManager1 service use the profile automatically.
An existing `conf/const.lua` file-manager command set to `dolphin` is updated to
the profile's absolute path, so the shortcut also works with a minimal `PATH`.
The installed profile stays enabled when `theme.apply` is `true`; disable its
automatic updates explicitly with `"dolphin": {"enabled": false}`. For terminal launches, link `~/.local/bin/dolphin` to
`~/.config/zestify/theme/dolphin-launch` and keep `~/.local/bin` in `PATH`.
Restart Dolphin once to load the stylesheet. File previews remain enabled;
folder collages are disabled so folders keep their outline icons. The installed
Zestify Lua integration loads the generated Dolphin rule for 18-pixel window
corners; reload Hyprland after the first apply. Other Qt apps also use the
palette-aware icon theme.

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

The standalone C++ login manager has a live theme editor (`--preview`),
configurable fonts/icons/layouts, and image, animated-image and video wallpapers.
See [login manager customization](docs/login-manager.md) for presets, theme
settings, dependencies and installation. Test it separately:

```sh
make -C auth -j2 test
```

This builds the daemon and greeter, checks protocol and PAM cleanup with a
test-only module and temporary policies, and renders an offscreen greeter preview.
It also checks theme reload/save, rendered layout and authentication controls;
with FFmpeg installed it exercises live wallpaper playback and fallback.
It does not install or enable the display-manager service.

See [the code review and performance report](docs/code-review-2026-11-13.md)
for measured improvements and verification limits.

Focused native media/notification checks and rendered previews:

```sh
python3 tests/quickshell/run-media-ui.py
python3 tests/quickshell/run-party-ui.py  # animation frames and bass impact previews
python3 tests/quickshell/run-party-ui.py --profile-formation  # entry frame intervals without screenshots
python3 tests/quickshell/run-party-audio.py /path/to/music.mp3  # full-track cavacore/motion replay
python3 tests/quickshell/run-party-audio.py /path/to/music.mp3 --realtime  # actual cava at playback speed
python3 tests/quickshell/run-party-ui.py --audio-trace /tmp/zestify-party-audio/spectrum.json
python3 tests/quickshell/run-party-latency.py  # FIFO kicks through detection and offscreen rendering
sh tests/quickshell/run-drawer.sh  # active Hyprland session; restores the pointer
python3 tests/quickshell/run-shortcuts.py  # isolated headless drawer gestures and shortcuts
python3 tests/quickshell/run-session-lock.py  # isolated nested compositor and temporary PAM policy
```

The party-mode shader ships precompiled. After editing its GLSL source,
regenerate the Qt 6 shader bundle with Qt Shader Tools:

```sh
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o shell/shaders/party-motion.frag.qsb shell/shaders/party-motion.frag
```

The optional audio replay check uses the installed `libcava` and `node`. It
decodes locally without playing audio, checks motion across the full track,
and writes onset timings and strengths under `/tmp/zestify-party-audio`.
The rendered check samples quiet, dense and transition passages from that trace.
Party capture preserves input/routing settings, fixes analysis gain and disables
Cava's temporal filter in a temporary config; displayed bars keep their QML
smoothing. Sequenced packets carry an estimated 60Hz analysis clock and emission
timestamps; duplicate, reordered and stale deliveries are ignored. The clock
handles batched pipe reads and re-anchors after stalls; it is not a PCM timestamp.
The optional latency check measures eight known FIFO kick writes through the
production monitor, scene detection and Qt offscreen frame swaps. Its results
exclude speaker and compositor/display latency.

The album cover samples its cached artwork directly through a circular/capsule
shader. After editing its GLSL source, regenerate the bundle:

```sh
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o shell/shaders/album-cover.frag.qsb shell/shaders/album-cover.frag
```

The power portrait uses a precompiled shader for its smooth circular edge.
After editing that shader, regenerate its bundle too:

```sh
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o shell/shaders/power-portrait.frag.qsb shell/shaders/power-portrait.frag
```

Wallpaper thumbnails use a rounded mask for the image and selection caption. After
editing that shader, regenerate its bundle:

```sh
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o shell/shaders/rounded-card.frag.qsb shell/shaders/rounded-card.frag
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
generated at the selected resolution and capped at 24 fps by default (configurable); the original is used
for palette extraction and thumbnails, not steady-state decoding.

## License

GPL-3.0-only. See `LICENSE` and `NOTICE` for credits.

The wallpaper transition shader can be regenerated with:

```sh
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o shell/shaders/wallpaper-transition-v15.frag.qsb shell/shaders/wallpaper-transition.frag
```
