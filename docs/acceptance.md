# Zestify acceptance checklist

Measured on 2026-11-04 (IST) on the reference machine; the hover redesign was
re-verified on 2026-11-05.

- Hyprland 0.56.2 (Lua configuration).
- Quickshell 0.3.1 (`2d3b3e9c70ef380dff751b61d334dc88df016c29`).
- QtMultimedia FFmpeg backend, FFmpeg n9.0.2.
- eDP-1: 1920x1200 landscape, scale 1, primary.
- HDMI-A-1: 1366x768 rotated `transform = 1` -> logical 768x1366 portrait.

Status meanings: `[x]` verified, `[ ]` not verified, `[!]` verified but outside the
target. Commands below assume the repository is at `~/zestify` and the shell was
started with `zesti shell start`.

## Rendering and layout

- [x] Both monitors render a pill at the top center and a full-screen background.
  Verified with the still wallpaper and with `10006.mp4` on both monitors.
- [x] The pill is not clipped on the portrait monitor. All ten surfaces
  (`launcher`, `wallpaper`, `system`, `media`, `audio`, `calendar`, `network`,
  `bluetooth`, `battery`, `power`) fit inside the 768 px logical width. Opened
  each surface by IPC against a temporary primary-monitor override and inspected
  the captures (`/tmp/opencode/surface-*.png`, 1366x768 each).
- [x] Hover works. Moving the real cursor over the eDP-1 pill expands it into a
  1000x320 (scaled) dashboard-sized card with a 200 px circular cover and the
  media controls beneath it; the title/artist block sits above a wide 32-band
  cava visualizer; moving the cursor away collapses it again. The card also
  fits the 768 px logical portrait panel. Captures:
  `/tmp/opencode/pill-v3-edp.png`, `/tmp/opencode/pill-v3-portrait.png`.
- [x] The resting pill shows an icon-only battery that adapts to charge level,
  switches to a charging glyph on AC, and keeps opening the battery surface on
  click.
- [x] A single expanded surface exists globally. Opening a surface on one monitor
  closes the surface on the other (enforced by `ShellState`; covered by the
  desktop-state QML tests).
- [x] Launcher, wallpaper studio, and power surface open, render, and close.
  The remaining surfaces were opened through IPC and visually checked in
  portrait.
- [x] The tray opens a native Quickshell platform menu on the primary monitor.
- [x] The power menu offers lock, sleep, logout, restart, and shutdown. The
  non-destructive entries are exercised by the session tests; shutdown/restart
  were not executed during QA.

## Rotation, hotplug, and resolution changes

- [x] Rotating HDMI-A-1 from portrait to landscape updates the background proxy
  from `768x1366` to `1366x768` without restarting Quickshell, and rotating back
  restores `768x1366`.
- [x] Disabling HDMI-A-1 and re-enabling it keeps the shell alive and restores
  the correct proxy and pill. The re-enable call must include `disabled = false`.
- [x] Changing HDMI-A-1 to 1280x720 `transform = 1` produces a logical 720x1280
  output, a `720x1280` proxy, and matching background/pill layer sizes.
- [x] A null-screen QML error during hotplug was found and fixed by guarding
  `root.screen` in `MonitorShell.qml`; the hotplug cycle above is clean.

## Wallpapers, palettes, and proxies

- [ ] Per-monitor still wallpapers and per-monitor palettes; changing a
  secondary wallpaper does not recolor system applications, changing the
  primary does, and focus changes do not re-template applications.
- [x] Video wallpapers use a monitor-sized proxy. With `10006.mp4` applied to
  both monitors, `lsof` showed only
  `cc19091b.../1920x1200.mp4` and `cf8106d0.../768x1366.mp4` open; the source
  `10006.mp4` was not open by the shell.
- [x] Proxies are capped at 30 fps and preserve lower source frame rates
  (`tests/python/test_wallpaper_proxy.py`, 7 tests).
- [x] No 4K decoder is running. `ffprobe` reports the active proxies at
  `1920x1200` and `768x1366`, and there are no `ffmpeg` child processes in
  steady state.
- [x] Stills no longer load a `MediaPlayer`; only videos bind a source to
  `VideoWallpaper` (`tst_wallpapers.qml`).

## Session behavior

- [x] Manual lock and DPMS-off stop video decode and return the shell to roughly
  0-1% CPU. Unlocking/DPMS-on resumes playback without a stalled frame.
- [x] A fullscreen window pauses only that monitor's video. CPU fell from
  ~7-8% to ~3-4% with a fullscreen kitty on eDP-1 and resumed when it closed.
- [ ] Lock-before-sleep via `aboutToSleep` actually launches the lock wrapper.
- [x] Battery warning thresholds and the audio inhibit policy are covered by
  `tests/qml/tst_session.qml` (4 passed).
- [x] The low-battery video pause path is covered by `tst_session.qml`.

## Installer and uninstaller

- [x] Installer/uninstaller round trip in a temporary HOME passes, including
  idempotent re-install, marker cleanup, backups, and rollback
  (`tests/python/test_installer.py`).
- [x] The installer does not disturb unmarked user Hyprland Lua lines.
- [x] The installer links both `zesti` and `zestify`, runs copy-only migration,
  and starts the shell via `zesti shell start`.
- [x] The uninstaller removes both CLI links, does not restore or restart
  Caelestia, and preserves config/state unless `--purge`.

## Performance

Method: `scripts/perf-sample.sh PID DURATION` samples the Quickshell process
once per second and reports CPU%, RSS, and child-process count. All samples are
after the shell had settled. The shell PID during these runs was 14117.

| Scenario | Duration | CPU (average / range) | RSS | Target | Result |
| --- | ---: | --- | --- | --- | --- |
| Idle, still wallpaper, no surface | 60 s | ~0.6% / 0.0-2.0% | 424.8 -> 469.9 MB | <=1.5% CPU, <=250 MB | CPU pass; RSS [!] |
| Two 30 fps video proxies | 60 s | ~7.9% / 6.9-10.8% | 497-512 MB | <=9% CPU, <=250 MB | average pass, one spike [!]; RSS [!] |
| Fullscreen on eDP-1 | spot checks | 3.0-4.0% | - | paused decode | pass |
| Locked / DPMS off | spot checks | 0.0-1.0% | - | return to idle | pass |
| Unlocked / DPMS on | spot checks | 7.0-9.0% | - | resume | pass |

The 250 MB RSS target is **not met** on this build. The shell idles around
425-470 MB after a still wallpaper and around 500-550 MB with two video
decoders. This is recorded as a measured miss rather than a pass; the Qt Quick
and QtMultimedia baseline on this machine dominates the number. The two-video
CPU average is within 9%, but one 10.8% sample exceeded it and is recorded as a
transient miss.

The cava visualizer is started only while the hover card is open. With the pill
at rest, no `cava` or `cava-monitor.py` processes remain.

### 1-hour soak

- [ ] Full one-hour soak not completed (interrupted at ~17 min for lock/DPMS
  testing). Observed 13:59→13:16: RSS climbed 554→647 MB over ~4 min then
  plateaued at ~644-650 MB with **no monotonic growth** for the remainder of
  the observed window; exactly one ffmpeg-adjacent child (logind-watch) and no
  ffmpeg processes in steady state. Lock/DPMS/fullscreen pause-resume were
  verified separately (CPU drops to 0-4% and resumes ~7-9% with no stalled
  video; `/tmp/opencode/video-edp-recovered.png` shows video still advancing
  on eDP-1 after recovery).

The raw soak log is `/tmp/opencode/zestify-soak.log`; do not claim the full
one-hour soak unless it is run to completion.

## Automated verification

Last run: 2026-11-07, `./scripts/test.sh`.

- Python: 179 tests, all passed.
- QML: 116 tests, all passed.
- `qmllint`: passed.
