# Zestify — a minimal Hyprland shell

Status: draft for review  
Date: 2026-11-01  
Author: zetzor + agent  
License: GPL-3.0-only (see License and attribution)

## 1. Intent

Replace the legacy shell with a single, hand-owned Quickshell shell that does three things well:

1. A minimal, always-visible pill on every monitor.
2. A wallpaper manager with per-monitor stills and live videos.
3. A resource/status bar with the everyday controls and surfaces needed to avoid a second bar.

The pill's shape, motion, and one-shape-morphs-into-everything interaction come from the reference UI. Its colors, typography, and material treatment do **not**: every color is derived from the current wallpaper. The legacy shell is no longer used, but its palette engine and wallpaper state remain the backend in v1.

The result should feel like one deliberate object, not a collection of widgets. It should be quiet at rest, expand fluidly under the pointer, and stay out of the way.

## 2. Goals

- One floating pill, centered at the top of each monitor, with no separate bar.
- At rest: workspaces, active-window title, clock, CPU/RAM, Wi-Fi/Bluetooth/battery, tray, power.
- On hover: the same pill grows downward to show media and quick toggles.
- Clicking a module morphs the pill into a focused surface: wallpaper studio, system monitor, media, audio, calendar, launcher, network, Bluetooth, battery, notifications, power.
- Per-monitor wallpapers and per-monitor shell palettes.
- System applications (GTK, terminal, Discord, Spotify, etc.) always follow the **primary** monitor's palette.
- Native still/video wallpaper rendering with sensible pause rules and monitor-resolution video proxies; no awww/mpvpaper dependency.
- Preserve the legacy shell's idle/session behavior (lock, DPMS, suspend, lock-before-sleep, audio inhibit, battery warnings) inside Zestify; no second shell and no hypridle dependency.
- Install and uninstall cleanly alongside the legacy shell, with rollback.
- Stay within a measured performance budget.
- Keep the user's hand-written Hyprland Lua config intact apart from small, marked, reversible edits.

## 3. Non-goals (v1)

- Clipboard history.
- Screen recording.
- Weather.
- A custom lock-screen UI. Lock is delegated to `hyprlock`.
- In-shell settings pages (appearance, animation, display, input, fonts, idle, keybinds, updates).
- Workspace management beyond clicking/scrolling workspaces.
- Game mode, music visualizer, lyrics, desktop clock, visualizer.
- Per-app volume, microphone denoise, equalizer, AutoEQ.
- Night light, keep-awake, DND inbox (a DND toggle inside notifications is allowed).
- Random-wallpaper configuration UI beyond a "random" action.
- Manual light/dark theme editor or theme export beyond the legacy shell's templates.
- Custom lock-screen wallpaper handling.
- Hyprland window-border recoloring. This can be added later by including the legacy shell's generated Lua file; it is not part of v1.
- Ricemod. The abandoned `~/zesty/ricemod` project is not used, imported, or modified.

## 4. Anti-goals

- A second bar, a dock, or a separate widget layer that makes the shell feel assembled.
- A second shell process kept alive only for session management. Port the behavior into Zestify instead.
- Warm vermilion/brown colors, regardless of wallpaper.
- A static theme that ignores the wallpaper.
- Constant animations, shaders, or polling that keep the CPU awake.
- Duplicating the same tray/status modules on both monitors just because there are two screens.
- Editing the user's Hyprland config without a backup and a clean reverse path.
- Making the legacy shell a runtime requirement for the **shell UI**. The CLI backend is a v1 dependency; the shell itself must be our code and our process.

## 5. Constraints and environment

- Arch Linux, Hyprland 0.56.2 with a hand-written Lua config.
- Entry point `~/.config/hypr/hyprland.lua`; includes `conf/const.lua`, `monitor.lua`, `env.lua`, `config.lua`, `anim.lua`, `input.lua`, `rules.lua`, `binds.lua`, `autostart.lua`.
- Primary monitor `eDP-1`: 1920×1200, position 0,0, scale 1.
- Secondary monitor `HDMI-A-1`: 1366×768 with `transform=1`; Quickshell reports it as **768×1366** at x=-768, y=0. It is portrait and must be treated as such for scale and width calculations.
- The legacy shell 2.5.0 and CLI 1.1.3 are installed. The legacy shell is currently running; the installer stops it and starts Zestify.
- Quickshell 0.3.1, `qs` at `/usr/bin/qs`.
- `hyprlock` 0.9.6 is installed but has no config. Current `SUPER + Escape` calls the legacy shell's IPC lock.
- Wallpapers live in `~/Pictures/Wallpapers` (39 files: 18 images, 21 videos). The folder is the default, not a hard requirement.
- GPU is Intel UHD (Alder Lake-P). No discrete GPU. `lm_sensors` is installed.
- PipeWire/WirePlumber, NetworkManager, BlueZ, playerctl, ffmpeg, ImageMagick, jq, Python 3.14 are installed.
- Fonts: SF Pro / SF Mono and CaskaydiaCove Nerd Font are available and match the current reference look. JetBrains Mono is available if a mono look is preferred later.
- The legacy shell is GPL-3.0; the reference UI is MIT. Copying from both makes this project GPL-3.0.

## 6. Decisions made by the user

- Build our own minimal shell instead of continuing to use the legacy shell.
- One shell, not a bar plus a separate wallpaper daemon.
- Take the reference UI's shape, functionality, and fluidity; do not take its colors/theme.
- Derive colors from the wallpaper; no static palette.
- Use the legacy shell's theming/wallpaper system as the backend where it helps.
- Rip/adapt code freely from the legacy shell and the reference UI, accepting GPL-3.0.
- Include, alongside the original v1 scope:
  - per-monitor wallpapers and per-monitor palettes;
  - install/uninstall script;
  - portrait-panel layout tuning and multi-monitor pill behavior;
  - performance budget, idle CPU target, video-wallpaper pause rules;
  - active-window title;
  - system tray;
  - power/session menu (lock, sleep, logout, restart, shutdown).
- System applications use the **primary monitor's** palette; they do not follow focus.
- Keep the legacy shell's idle/session behavior by porting its logic into Zestify (same thresholds, lock before sleep, audio inhibit, battery warnings). The legacy shell process is not kept running for this.
- Use a monitor-resolution proxy cache for video wallpapers so 4K sources are decoded at the monitor's resolution; originals remain for palette extraction and thumbnails.

## 7. Decisions made by the builder (defaults, vetoable)

These are my calls. They are recorded here so they can be rejected before implementation.

- Working name: **Zestify**. Repo root `~/zestify`; config name `zestify`; command `zestify`.
- User config: `~/.config/zestify/config.json`.
- Runtime state: `~/.local/state/zestify/`.
- Cache: `~/.cache/zestify/`; prefer the legacy shell's wallpaper cache when a thumbnail already exists.
- Launch: `qs -c zestify`, symlinked from the repo's `shell/` directory into `~/.config/quickshell/zestify`.
- Backend: call the installed the legacy CLI for palette generation and system-app templating in v1. The shell does not import the legacy shell's QML modules. Vendoring the Python/templates is a later option.
- Wallpaper rendering: native QtMultimedia/Image inside Quickshell. Do not use awww or mpvpaper. Video playback uses a lazily generated monitor-sized H.264 proxy; if generation fails, fall back to the original file.
- Lock: `hyprlock` via a `zestify lock` wrapper; generate a minimal config from the current palette and wallpaper at lock time. No custom lock UI in v1. The wrapper returns after spawning hyprlock and resumes video when hyprlock exits; `--wait` is available for scripts.
- Session/idle: port the legacy shell's `IdleMonitors`/`BatteryMonitor` behavior rather than importing the legacy shell's services; use Quickshell `IdleMonitor`, UPower, a small logind DBus watcher, and systemd. Same thresholds as the current reference config.
- Default theme mode: dark, even if a wallpaper would make the legacy shell choose light. `theme.mode` can be set to `smart` later.
- Fonts: SF Pro for body/title/clock; SF Mono for numbers where it helps; CaskaydiaCove Nerd Font for icons.
- Tray: primary monitor only. Active-window title: focused monitor only. One surface open across all monitors at a time. Power menu opens on the monitor where it was invoked.
- Module order is fixed in v1. JSON can toggle visibility of tray/title, but not reorder every module.
- Hover opens the expanded pill; clicking a module opens a persistent surface; `Esc` or clicking outside closes it. Clicking the same module again closes it.
- Installer uses marked blocks and backups; it refuses to guess if the user's config has changed beyond the marked regions.
- The legacy CLI remains installed. Removing the legacy shell package is not part of the installer.

## 8. Architecture

### 8.1 Process and windows

One Quickshell process, config `zestify`:

- `ShellRoot` with a `Variants` over `Quickshell.screens`.
- Per monitor:
  - a bottom-layer full-screen background window for the wallpaper (images/video);
  - a top-layer panel window for the pill and its expanded surfaces;
  - overlay windows as needed for tray menus, notification popups, and OSD.
- The pill window uses a region mask so only the pill/surface area accepts input. The rest of the top layer is click-through.
- Exclusive zone: only the pill height at rest; expanded surfaces must not reserve layout space.
- Fullscreen windows on a monitor retract the pill on that monitor (the reference UI behavior). Other monitors keep their pill.
- One expanded surface globally. Opening a surface on one monitor closes the other.
- The legacy shell is stopped by the installer. The legacy CLI remains available for palette/wallpaper work.

IPC target `zestify`, with at least:

- `open(surface)`, `toggle(surface)`, `close()`
- `wallpaper(monitor, file)` / `wallpaperAll(file)` / `random(monitor|all)`
- `lockState(bool)` — pauses/resumes video wallpapers
- `osd(kind, value)` — volume/brightness overlay
- `reload()`, `ping()`, `quit()`

The `zestify` CLI wraps `qs -c zestify` and IPC. It also provides `start`, `stop`, `restart`, `status`, `lock`, `sleep`, `wallpaper`, `random`, `brightness`, `volume`, `cache`, `logs`.

### 8.2 Repo layout

```
~/zestify/
  shell/                      # Quickshell config (symlinked to ~/.config/quickshell/zestify)
    shell.qml
    components/
    services/
    singletons/
    surfaces/
    backgrounds/
  bin/zestify                 # CLI wrapper (shell script)
  scripts/
    install.sh
    uninstall.sh
    wallpaper-backend.py      # optional thin wrapper around the legacy CLI for primary/secondary restore
    wallpaper-proxy.py        # monitor-sized H.264 proxy cache
    perf-sample.sh
  config/default.json
  hypr/zestify.lua            # generated include for autostart/keybinds
  docs/
  LICENSE
  NOTICE
  README.md
```

### 8.3 Config and state

`~/.config/zestify/config.json` is the only user-editable file. It is merged over defaults; missing keys keep defaults. Invalid JSON falls back to defaults and logs a warning; the shell does not crash.

Initial schema:

```json
{
  "monitor": {
    "primary": "eDP-1"
  },
  "bar": {
    "height": 34,
    "topGap": 8,
    "opacity": 1.0,
    "scale": 1.0,
    "showTray": true,
    "showTitle": true,
    "trayOn": "primary",
    "titleOn": "focused"
  },
  "theme": {
    "mode": "dark",
    "transparency": 0.88,
    "font": "SF Pro",
    "mono": "SF Mono",
    "iconFont": "CaskaydiaCove Nerd Font"
  },
  "wallpaper": {
    "dir": "~/Pictures/Wallpapers",
    "pauseOnFullscreen": true,
    "pauseWhenObscured": "fullscreen",
    "pauseOnBatteryBelow": 20,
    "pauseOnPowerSaver": true,
    "pauseUnfocusedAfter": 0,
    "muted": true,
    "proxy": {
      "enabled": true,
      "resolution": "monitor",
      "codec": "h264",
      "crf": 20
    }
  },
  "system": {
    "pollInterval": 1000,
    "graphSeconds": 60
  },
  "notifications": {
    "dnd": false,
    "timeout": 5000
  },
  "osd": {
    "enabled": true,
    "position": "bottom-center",
    "timeout": 1500
  },
  "power": {
    "confirmHoldMs": 700
  },
  "session": {
    "lockAfter": 180,
    "dpmsOffAfter": 300,
    "suspendAfter": 600,
    "suspendCommand": ["systemctl", "suspend-then-hibernate"],
    "lockBeforeSleep": true,
    "inhibitWhenAudio": true,
    "inhibitWhenCharging": false,
    "batteryWarnings": [20, 10, 5],
    "criticalBattery": 3
  }
}
```

Runtime state in `~/.local/state/zestify/`: last opened surface, lock flag, notification DND override, notification history if Quickshell does not persist it, and installer backups. Wallpaper and palette state remain in the legacy shell's state directory and are treated as the source of truth.

### 8.4 Per-monitor palettes

The legacy shell already generates:

- global `~/.local/state/<previous-shell>/scheme.json` (primary wallpaper);
- per-monitor `~/.local/state/<previous-shell>/wallpaper/monitors/<connector>-scheme.json`;
- per-monitor wallpaper path files next to them.

Zestify watches those files and builds a `Colours` singleton with the same idea as the legacy shell's `Colours.qml`:

- `Colours.p(screenName)` returns the screen's M3 palette, falling back to the global palette.
- `Colours.isLight(screenName)` returns the screen's mode.
- A `Theme` object per screen maps M3 names to the token names the reference UI components already use.

Mapping (kept deliberately small):

| Reference token | M3 source |
|---|---|
| `cream` / text | `onSurface` |
| `bright` | `onSurface` |
| `dim` | `onSurfaceVariant` |
| `faint` / `iconDim` | `onSurfaceVariant` with alpha |
| `cardTop` | `surfaceContainerHigh` |
| `cardBot` | `surfaceContainer` |
| `border` | `outlineVariant` with alpha |
| `tileBg` | `surfaceContainerHighest` |
| `accentFill` | `primary` |
| `onAccent` | `onPrimary` |
| `danger` | `error` |
| `onGlow` | `onPrimary` |
| `vermLit` / `vermLit` names | `primary` (rename in code; no warm semantic) |

The shell uses `surfaceContainerHigh` at `theme.transparency` alpha for glass, `outlineVariant` at ~25% for the hairline, and `primary` for active states. It must not keep the reference UI's vermilion/brown tokens.

Each pill and surface receives its monitor's `Theme` object; no global mutable "current screen" is used for rendering both monitors at once.

### 8.5 Wallpaper and palette pipeline

**Reading state.** `Wallpapers` reads:
- global path `~/.local/state/<previous-shell>/wallpaper/path.txt`;
- per-monitor paths `~/.local/state/<previous-shell>/wallpaper/monitors/<connector>.txt`;
- `wallpaper/current` symlink only as a convenience.

Effective wallpaper for a monitor = per-monitor path if present, else global path.

**Applying a wallpaper.**

- Secondary monitor: `legacy-cli wallpaper -f <file> -m HDMI-A-1`. This writes the per-monitor path and `HDMI-A-1-scheme.json`; it does not touch global app templates. The shell's secondary palette updates from the file watcher.
- Primary monitor: `legacy-cli wallpaper -f <file>`. This writes the global path, regenerates `scheme.json`, and applies system-app templates. It also clears per-monitor overrides, so the wrapper must save and re-apply the current secondary wallpaper(s) afterward with `-m`.
- Apply-to-all: global call; no overrides to restore.
- Random: choose from the configured folder (or the legacy shell's wallpaper list), apply with the same primary/secondary rules.
- The wrapper is `scripts/wallpaper-backend.py` (or a POSIX wrapper): it stores secondary paths in Zestify state, invokes the CLI, restores secondary overrides after a primary/global change, and prints a JSON result for the QML side.

**System apps.** Always use the global `scheme.json`, which is generated from the primary wallpaper. Moving focus between monitors never re-templates apps. This is a user decision.

**Dark mode.** Default `theme.mode: "dark"`. When applying a wallpaper, force the legacy shell's scheme mode to dark (or use `-N` with a dark scheme) unless the user sets `smart`. The exact CLI call is an implementation detail, but the default visual result must be dark surfaces with wallpaper-derived accents.

**Thumbnails.** For videos, grab a frame at ~2 seconds with ffmpeg and cache by content hash. For images, use a downscaled copy. Reuse the legacy shell's `~/.cache/<previous-shell>/wallpapers/<hash>/thumbnail.jpg` when present. The wallpaper studio shows aspect-correct thumbnails with a play badge for videos.

**Video proxies.** When a video is applied, Zestify computes the target size from the monitor's current pixel size and generates a monitor-sized H.264 proxy at `~/.cache/zestify/wallpapers/<hash>/<WxH>.mp4` with ffmpeg. The scale/crop matches `PreserveAspectCrop`; the cache key includes source path, size, mtime, target size, codec, and CRF. Generation is lazy and background: show the extracted still while the proxy is built, then cross-fade to the proxy. The original file stays authoritative for palette extraction, thumbnails, and the wallpaper studio. If generation fails or is disabled, play the original and record the fallback. A proxy is never used for a different monitor geometry. `zestify cache prune` removes proxies not referenced by current or recent wallpapers.

### 8.6 Background renderer

Adapt the legacy shell's `Wallpaper.qml` and `VideoWallpaper.qml`:

- `Image` for stills, `MediaPlayer` + `VideoOutput` for videos.
- `MediaPlayer.source` points to the monitor-sized proxy when available; otherwise the original. The decoder therefore receives frames at monitor resolution, not 4K. The proxy is generated while the still frame is shown; the original is never decoded in steady state when proxying succeeds.
- `PreserveAspectCrop`, full-screen, bottom layer.
- Cross-fade between old and new wallpaper over ~300ms; retire the old surface after the new one is ready (with a hard timeout).
- First video frame is shown even when playback is paused.
- Muted audio.
- Loop indefinitely.
- `shouldDecode` gates playback:
  - false when the monitor is locked;
  - false when the monitor's DPMS is off;
  - false when a fullscreen window is on the monitor (default `pauseWhenObscured: "fullscreen"`);
  - optional `"any-window"` mode pauses when any tiled window is on the active workspace;
  - false when on battery below `pauseOnBatteryBelow`;
  - false when the power profile is `power-saver` and `pauseOnPowerSaver` is true;
  - optional pause on unfocused monitor after N seconds (`pauseUnfocusedAfter`, default 0 = never).
- When paused, keep the last frame; do not destroy the decoder unless the source changes.
- Lock state comes from the `zestify lock` wrapper via IPC. DPMS comes from Hyprland's monitor IPC object. Fullscreen comes from Hyprland toplevels.

### 8.7 Pill UI

**Rest state (per monitor):**

```
[ 1 2 3 4 5 6 7 8 9 ]  [ active window title ]      [ 14:32 ]      [ CPU 12%  RAM 5.1G ]  [ wifi  bt  87% ]  [ tray ]  [ power ]
```

- Workspaces: all 1–9, active filled, occupied dot, click to switch, scroll to cycle. Workspace homes remain 1–6 primary and 7–9 secondary, but the pill does not hide the other monitor's numbers; it only marks which are active/occupied.
- Active window title: only on the focused monitor. Ellipsis; tooltip/full title on hover. Hidden when empty or when the pill is retracted.
- Clock: centered, 24-hour by default; date on hover; click opens calendar.
- Resources: compact CPU percentage and RAM used; click opens system monitor. Temperature can appear in the system surface, not the rest pill.
- Status: Wi-Fi, Bluetooth, battery percentage; click opens the matching surface.
- Tray: primary only; 16px icons; right-click menu in an overlay; tooltip; scroll passthrough.
- Power: glyph; click opens the power surface.

**Hover state:** after ~120ms, the pill grows downward to reveal:
- media card: album art, title/artist, previous/play/next, progress;
- quick toggles: Wi-Fi, Bluetooth, DND, volume, brightness;
- notification bell with unread count;
- a thin CPU/RAM sparkline (optional; keep only if it stays quiet).

Hover collapses ~350ms after the pointer leaves unless a surface is pinned open. Hover expansion is a preview; clicking a module opens the persistent surface.

**Width and portrait behavior:**
- Rest scale `s = (portrait ? width : height) / 1080`, clamped to 0.7–1.25, multiplied by `bar.scale`.
- Pill width is content-driven with a minimum and a maximum of `screen.width - 2 * 16`.
- On narrow/portrait screens, hide in this order: tray, active title, resource text, then BT/Wi-Fi labels (keep icons). Never hide the clock, workspaces, battery, or power.
- Surfaces are capped at `screen.width - 2 * 16` and `screen.height - pillTop - 16`; content scrolls when needed.
- The wallpaper grid chooses 2–4 columns based on available width.
- Text uses ellipsis; never clip glyphs or let a module push the pill off-screen.

**Surfaces:**
- **Wallpaper studio:** folder label/edit, grid of still/video thumbnails, monitor selector defaulting to the monitor it was opened on, "apply to all", random, current-wallpaper marker, play badge, trash? No delete in v1 (too risky); just show. Maybe a "reveal folder" action.
- **System monitor:** CPU, RAM, swap, disk, network, temperatures, battery; sparkline history; update at 1s.
- **Media:** current player, album art, title/artist/album, controls, seek, player selector if multiple.
- **Audio:** output volume, mute, input volume, mute, output/input device lists. No per-app mixer.
- **Calendar:** month grid, today, previous/next month; no event backend.
- **Launcher:** search field, fuzzy app results, keyboard navigation, Enter to launch, Esc to close; reads `.desktop` files from XDG data dirs.
- **Network:** Wi-Fi toggle, scan/list, connect, signal, security; current connection.
- **Bluetooth:** adapter toggle, paired/devices list, connect/disconnect, pairing mode.
- **Battery:** percentage, state, time remaining, health if available.
- **Notifications:** history, clear, DND toggle; click a notification to focus? v1 can just show text and dismiss.
- **Power:** lock, sleep, logout, restart, shutdown; hold-to-confirm for logout/restart/shutdown; keyboard support.

**Notifications and OSD:**
- Quickshell `NotificationServer` owns `org.freedesktop.Notifications` when the legacy shell is stopped.
- Popups appear at the top-right of the focused monitor, stacked, auto-dismiss after `notifications.timeout`, click to dismiss, hover to pause timeout.
- DND suppresses popups but keeps history.
- Volume OSD observes PipeWire default sink changes and appears bottom-center for ~1.5s. Brightness OSD is driven by `zestify brightness up/down`, which calls `brightnessctl` and the IPC OSD.
- OSD uses the focused monitor's palette and the same glass shape as the pill.

### 8.8 Services

- **System monitor:** `/proc/stat`, `/proc/meminfo`, `/proc/net/dev`, `/sys/class/power_supply`, `sensors`. 1s poll, 60 samples. No GPU graph (Intel UHD only); temperature is enough.
- **Media:** Quickshell.Services.Mpris.
- **Audio:** Quickshell.Services.Pipewire.
- **Network:** Quickshell.Networking.
- **Bluetooth:** Quickshell.Bluetooth.
- **Battery:** Quickshell.Services.UPower.
- **Tray:** Quickshell.Services.SystemTray + `QsMenuOpener`.
- **Notifications:** Quickshell.Services.Notifications.
- **Launcher:** custom `.desktop` parser in QML/JS. Read `$XDG_DATA_DIRS/applications` and `~/.local/share/applications`; parse Name, Exec, Icon, Terminal, Categories, NoDisplay, Hidden, OnlyShowIn; resolve icons through Quickshell's icon lookup. Do not depend on the legacy shell's `the legacy shell's models` module.
- **Hyprland:** Quickshell.Hyprland for workspaces, toplevels, active window, monitors, fullscreen/DPMS state.
- **Lock:** external hyprlock; state via IPC.

### 8.9 Lock

- `zestify lock`:
  1. sends `lockState(true)` to the shell (pause videos);
  2. generates `~/.cache/zestify/hyprlock.conf` from the current primary palette and wallpaper;
  3. spawns `hyprlock --config ~/.cache/zestify/hyprlock.conf` detached and starts a watcher process;
  4. when hyprlock exits, the watcher sends `lockState(false)` (resume videos where allowed).
- The wrapper returns immediately by default so it is safe from idle and sleep paths; `--wait` waits for hyprlock to exit for scripts that need it.
- Generated hyprlock config: wallpaper background, dark overlay, clock, username, password field, error color, accent from `primary`, font SF Pro/SF Mono. No custom shaders.
- `SUPER + Escape` changes from the legacy shell's IPC lock to `zestify lock`.
- Power menu's Lock action calls the same wrapper.
- If hyprlock fails, `zestify lock` logs and leaves the session unlocked rather than trapping the user.

### 8.10 Idle and session

Zestify takes over the behavior the legacy shell currently provides; the legacy shell process is not kept running for it. The thresholds mirror the current `~/.config/<previous-shell>/shell.json`:

- idle 180s -> `zestify lock`;
- idle 300s -> DPMS off (`hyprctl dispatch dpms off`); return action DPMS on;
- idle 600s -> `systemctl suspend-then-hibernate`;
- all respect inhibitors; `inhibitWhenAudio` pauses idle when any MPRIS player is playing; charging inhibit optional and off by default;
- logind `PrepareForSleep(true)` -> lock before sleep; `PrepareForSleep(false)` -> normal resume;
- UPower battery warnings at 20/10/5%; critical at 3% -> hibernate after a 5s toast;
- battery warnings only while on battery; charger plug/unplug toasts.

Implementation: Quickshell `IdleMonitor` + UPower + a small logind DBus watcher. Do not import the legacy shell's services (compiled and coupled). `zestify lock` is safe to call from the idle service and from logind's sleep path because it returns after spawning hyprlock. `zestify sleep` locks first, then runs `systemctl suspend-then-hibernate`; the power menu's Sleep action uses it.

### 8.11 Installer and uninstaller

`scripts/install.sh` is idempotent, supports `--dry-run`, `--no-start`, and `--purge` only on uninstall. It must:

1. Check required commands: `qs`, the legacy CLI, `hyprlock`, `brightnessctl`, `wpctl`, `jq`, `ffmpeg`, `magick`, `python`.
2. Back up every file it will edit to `~/.local/state/zestify/backups/<timestamp>/`.
3. Symlink `~/zestify/shell` to `~/.config/quickshell/zestify` (replace an existing symlink only after backup; refuse to overwrite a real directory without `--force`).
4. Install `bin/zestify` as a symlink in `~/.local/bin/zestify` (or print PATH instructions if `~/.local/bin` is not on PATH).
5. Write `~/.config/zestify/config.json` from defaults if missing; never overwrite an existing config.
6. Write `~/.config/hypr/conf/zestify.lua` with autostart/keybind additions, and patch the existing files with clearly marked blocks:
   - in `conf/autostart.lua`, replace the exact legacy autostart line with `hl.exec_cmd("zestify start")` inside `-- >>> zestify` / `-- <<< zestify` markers;
   - in `conf/binds.lua`, replace `SUPER + Escape` lock with `zestify lock`;
   - replace the two brightness binds with `zestify brightness up/down`;
   - add `SUPER + D` launcher and `SUPER + W` wallpaper if those keys are free.
7. Stop the legacy shell (`legacy-cli shell -k`), start Zestify (`zestify start`), wait for `zestify ping`, and verify the process is alive.
8. On failure: restore the backups, restart the legacy shell, and print the log path.

`scripts/uninstall.sh`:

- Stops Zestify.
- Removes the `~/.config/quickshell/zestify` symlink and the `~/.local/bin/zestify` symlink.
- Reverses the marked blocks in `autostart.lua` and `binds.lua` **only if the current content still matches what the installer wrote**; otherwise leaves them and prints manual instructions.
- Removes `~/.config/hypr/conf/zestify.lua`.
- Keeps `~/.config/zestify/config.json` unless `--purge`.
- Restarts the legacy shell if it was running before install.
- Never removes the legacy shell packages, wallpapers, or state.

## 9. Multi-monitor behavior

- Pill exists on both monitors. Each pill is independently hoverable/clickable.
- Each pill uses its monitor's palette.
- Exactly one expanded surface across all monitors; opening on one closes the other.
- Active-window title only on the focused monitor (Hyprland has one focused window globally).
- Tray only on the primary monitor.
- Power menu opens on the monitor whose pill was clicked.
- Wallpaper studio defaults to the monitor it was opened on; "apply to all" applies the same file to both.
- Fullscreen on one monitor retracts only that monitor's pill.
- Secondary wallpaper changes never recolor system apps; primary wallpaper changes do.
- On focus change, no palette re-templating of apps occurs.

## 10. Performance budget

Measured on this machine, both monitors connected, 60-second sample after a 5-second warm-up:

- **Idle shell:** ≤1.5% average CPU across the Quickshell process; ≤250 MB RSS.
- **One monitor-resolution video proxy:** ≤5% average CPU; two videos ≤9% average CPU. On this machine the proxy target is 1920×1200 on the primary and 768×1366 on the secondary; 4K sources are not decoded in steady state when proxying succeeds. Hardware decode where QtMultimedia provides it.
- **Proxy generation:** one-time background ffmpeg; not part of the steady-state budget; paused or cancelled on battery below threshold or power-saver; `zestify cache status` reports cache size.
- **Paused video:** decode stops; CPU returns to the idle target within 1s; last frame remains.
- **Animations:** 60fps during transitions only. No continuous shader, visualizer, or music bars by default.
- **Polling:** system stats 1s; battery 30s; clock updates on minute (or second if configured); network/Bluetooth event-driven; no timer faster than 250ms except active animations/OSD.
- **Startup:** pill visible within 2s of `zestify start` on a warm session.
- **Stability:** no monotonic RSS growth over a 1-hour idle soak; no QML binding-loop warnings in the log.

`scripts/perf-sample.sh` records PID, CPU%, RSS, and video decode state over a configurable duration and writes a small report. The budget is a target; if QtMultimedia cannot meet it with two monitor-sized proxies, the first fallback is `pauseUnfocusedAfter` and the second is a still-frame fallback, not a return to mpvpaper or 4K decode.

**Measured deviation (2026-11-04).** On the reference machine (Quickshell
0.3.1, QtMultimedia FFmpeg n9.0.2), the idle still-wallpaper case measured
0.0-2.0% CPU and 425-470 MB RSS; two 30 fps proxies measured 6.9-10.8% CPU
(about 7.9% average) and 497-512 MB RSS. The CPU targets were met on average,
with one two-video sample above 9%. The 250 MB RSS target is **not met**: the
Qt Quick/QtMultimedia baseline for two monitor backgrounds is roughly 425 MB
before video decoding. This miss is recorded in `docs/acceptance.md` rather
than silently relaxed here.

## 11. Testing and acceptance

**Static/unit:**
- `qmllint` on all QML; `qmlformat` check.
- Python helper tests for primary/secondary wallpaper restore logic.
- Proxy cache tests: target sizing, cache key stability, crop math, cleanup, and fallback when ffmpeg is unavailable.
- Installer/uninstaller round-trip in a temporary HOME with fixture Hyprland files; verify markers, backups, and rollback.
- Config merge tests: missing keys, invalid JSON, unknown keys.

**Manual/session:**
- Shell starts on both monitors with no duplicate legacy bar.
- Pill at rest and hover match the intended shape; no clipped content on the portrait panel.
- Per-monitor wallpapers: set different stills/videos; verify each monitor's palette and the primary-only app theming.
- Primary wallpaper change recolors GTK/terminal templates; secondary change does not.
- Video proxy: `ffprobe` reports the proxy dimensions equal to the monitor target; the original is untouched and remains the palette/thumbnail source; disabling the proxy or making ffmpeg fail falls back to the original.
- Video pause: fullscreen, lock, DPMS off, battery threshold, power-saver.
- Idle/session: 180s lock, 300s DPMS off, 600s suspend-then-hibernate; audio inhibit; lock before sleep; battery warnings at 20/10/5 and critical hibernate; no legacy shell process.
- Lock: `SUPER + Escape`, power menu, and idle all launch hyprlock; videos pause/resume.
- Active-window title updates on focus/title changes and hides on the unfocused monitor.
- Tray icons appear on primary; right-click menu works; no duplicate tray on secondary.
- Power menu: lock, sleep (cancelable), logout, restart, shutdown; hold-to-confirm.
- Notifications: send with `notify-send`; popup, history, DND, clear.
- OSD: volume keys and `zestify brightness up/down`.
- Launcher: search, keyboard navigation, launch, Esc.
- Network/Bluetooth/battery surfaces reflect real state and can change it.
- Installer rollback: break the start step deliberately; verify the legacy shell is restored.
- Uninstall: round-trip leaves the Hyprland config and the legacy shell autostart as before.
- Performance sample within budget.
- GPL notices and source links present.

## 12. Milestones

1. **Skeleton:** repo, config, IPC, CLI, per-monitor pill with idle modules, palette watcher, native background renderer, proxy cache pipeline, dev symlink. Test with the legacy shell stopped manually.
2. **Core surfaces:** wallpaper studio, system monitor, media, audio, calendar, hover expansion.
3. **System:** notifications, tray, network, Bluetooth, battery, power, lock, idle/session takeover, OSD, launcher.
4. **Installer/uninstaller:** marked edits, backups, rollback, autostart switch, uninstall round-trip.
5. **Performance and polish:** portrait tuning, multi-monitor behavior, monitor-sized proxy tuning, video pause rules, docs, license, final QA.

## 13. License and attribution

- Project license: **GPL-3.0-only**.
- `LICENSE`: GPL-3.0 text.
- `NOTICE`:
  - Portions adapted from the legacy shell (GPL-3.0), , copyright their contributors.
  - Portions adapted from the reference UI (MIT), , copyright the reference author; include the MIT license text.
  - Zestify changes copyright 2026 zetzor.
- Preserve copyright headers in copied files where they exist.
- Because the shell is distributed as source (QML), the source itself satisfies GPL. If binaries are ever distributed, provide the corresponding source.
- The legacy CLI remains a separate installed program; the shell calls it as a backend. This does not remove the GPL obligations for copied QML/Python code.

## 14. What is deliberately left to the builder

- Exact pixel values, spacing, corner radii, shadow strength, icon choices, and typography fine-tuning within the stated visual direction.
- Exact QML component decomposition and file names inside `shell/`.
- The precise legacy CLI invocation used to force dark mode (as long as the default result is dark and wallpaper-derived).
- The `.desktop` parser details and icon fallback behavior.
- The exact hyprlock config template, as long as it is palette-driven and minimal.
- The exact logind DBus watcher implementation and sleep/lock ordering details.
- Proxy CRF/codec tuning, cache pruning policy, and whether to precompute on idle, as long as steady-state decode stays monitor-sized.
- The installer's shell implementation (POSIX sh vs bash), provided it is idempotent and has the stated backup/rollback behavior.
- Whether to vendor the legacy shell's Python modules in a later version; v1 uses the installed CLI.
- Additional polish that does not expand the v1 scope.
