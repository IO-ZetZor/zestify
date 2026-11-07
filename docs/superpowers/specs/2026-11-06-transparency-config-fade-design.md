# Zestify Design: Transparency Layers, Config Module, Fullscreen Fade

**Date:** 2026-11-06  
**Branch:** feat/zestify  
**Status:** Proposed — awaiting human approval

## Intent

Add three related polish features to Zestify, inspired by Caelestia shell:
1. **Transparency layers** — backdrop blur and translucent backgrounds on the pill and surfaces, like Caelestia.
2. **Configuration module** — an in-shell UI surface to view and toggle all `Config.qml` options (not just editing `config.json` by hand).
3. **Fullscreen fade** — when a window goes fullscreen and the pill hides/shows, animate opacity instead of an instant snap.

## Goals

- Pill and open surfaces look like Caelestia: semi-transparent card with backdrop blur behind it.
- User can open a "Settings" surface from the pill to see and toggle every `Config.qml` option with live preview.
- Hiding/showing the pill on fullscreen is a smooth opacity fade, not a snap.
- All existing tests keep passing; no new QML errors.

## Non-Goals

- Not rewriting the entire shell theme system.
- Not adding new config keys beyond what `Config.qml` already exposes.
- Not importing Caelestia QML modules or code.

## Constraints

- One Quickshell process (existing constraint).
- No Caelestia QML module imports.
- Keep `session-3aaf49e8-ec47-4e47-865d-e71533db6ec9.md` untracked and uncommitted.
- Must run on both eDP-1 (1920x1200 landscape) and HDMI-A-1 (768x1366 portrait logical).
- All existing `Config.qml` sections remain: bar, theme, wallpaper, system, notifications, osd, power, session.

## Design

### Part 1: Transparency Layers

**Pill background (`PillBody.qml`):**
- Currently: gradient (`cardTop`/`cardBot`) + `border.width: 1` (recently set to 0).
- Change: keep gradient but add per-section alpha so the pill is translucent. Use `theme.transparency` (0.88 default) from `Config.qml` as the base opacity. The gradient stops get `withAlpha(cardTop, theme.transparency)` and `withAlpha(cardBot, theme.transparency)`.
- Add `layer.enabled: true` + `MultiEffect` blur when `theme.transparency < 1.0`, matching Caelestia's `CoverArt.qml` pattern (`layer.effect: MultiEffect { blurMax: ... }`). Blur strength scales with transparency: lower transparency = stronger blur.

**SurfaceFrame (`shell/surfaces/SurfaceFrame.qml`):**
- Currently: `surfaceLow` color at alpha 0.45, border width 0.
- Change: keep the translucent background but add optional `MultiEffect` blur behind the surface content when transparency is enabled, same pattern as pill.

**Hyprland blur rule (optional):**
- Caelestia sends `Hypr.extras.batchMessage([rule.arg("blur").arg(trEnabled), ...])` to enable Hyprland's native window blur. Zestify's `PanelWindow` could issue a blur rule on the pill window when transparency < 1.0. This is QML-side via `Hyprland.extras` if available; verify API exists in the installed Quickshell. If not available, rely on QML `MultiEffect` blur only.

### Part 2: Configuration Module

**New surface: `shell/surfaces/ConfigSurface.qml`**
- Registered in `Pill.qml`'s `surfaceRegistry` as `"config"`.
- Opens from the pill via a new toggle (gear icon) in `PillModules.qml` or `QuickToggles.qml`.
- Layout: scrollable list grouped by Config.qml section:
  - **Bar:** height, topGap, opacity, scale, showTray, showTitle, trayOn, titleOn
  - **Theme:** mode, transparency, fontFamily, monoFont, iconFont
  - **Wallpaper:** dir, pauseOnFullscreen, pauseWhenObscured, pauseOnBatteryBelow, pauseOnPowerSaver, muted, proxy (enabled/resolution/codec/crf)
  - **System:** pollInterval, graphSeconds
  - **Notifications:** dnd, timeout
  - **OSD:** enabled, position, timeout
  - **Power:** confirmHoldMs
  - **Session:** lockAfter, dpmsOffAfter, suspendAfter, suspendCommand, lockBeforeSleep, inhibitWhenAudio, inhibitWhenCharging, batteryWarnings, criticalBattery
- Each row shows current value and a control appropriate to the type:
  - bool → TapHandler toggle (writes to config.json via Config.setValue)
  - int/real → numeric input or slider
  - string → text input
  - enum/choice (mode, trayOn, titleOn, position) → segmented control or dropdown
- `Config.qml` needs a `setValue(path, value)` function that mutates `root.data`, writes `config.json`, and triggers `revision++` so bindings re-evaluate.
- Changes apply live (QML bindings on `Config.value(...)` re-evaluate automatically on `revision` change).
- Surface dimensions from existing registry pattern: width 760, height 600 (like wallpaper).

**Pill integration:**
- Add gear glyph to `PillModules.qml` (or status area) with `onConfigRequested`.
- `Pill.qml` gets `onConfigRequested: root.openSurface("config")`.

### Part 3: Fullscreen Fade

**Current behavior:**
- `Pill.qml`: `visible: !fullscreen` — instant hide/show.
- `hovering` requires `!fullscreen`.

**Change:**
- Replace instant `visible` toggle with an opacity `Behavior` on the root `Item`.
- When `fullscreen` becomes true: fade pill opacity to 0 over `motion.fast` duration, then set `visible: false` after fade completes (via a Timer or `onOpacityChanged`).
- When `fullscreen` becomes false: set `visible: true`, fade opacity back to 1.
- The pill remains interactive during fade (opacity only, not `visible`, until fully hidden).
- Use existing `root.motion.fast` (or 140ms default) with `Easing.OutCubic`.

## Files to Change

| File | Change |
|------|--------|
| `shell/components/PillBody.qml` | Translucent gradient alpha + conditional MultiEffect blur |
| `shell/surfaces/SurfaceFrame.qml` | Optional MultiEffect blur behind surface content |
| `shell/components/Pill.qml` | Fullscreen fade (opacity Behavior + visible gating), config surface registry entry |
| `shell/components/PillModules.qml` | Add gear/config toggle glyph |
| `shell/singletons/Config.qml` | Add `setValue(path, value)` to write config.json live |
| `shell/surfaces/ConfigSurface.qml` | New settings surface (new file) |
| `shell/components/qmldir` | Register ConfigSurface if needed |
| `tests/qml/tst_config.qml` | New QML tests for Config.setValue |
| `docs/acceptance.md` | Update if QA adds results |

## Tests

- QML test for `Config.setValue(path, value)` mutating data and triggering revision bump.
- QML test for boolean/int/string round-trip through `setValue` + `value()`.
- No UI test for ConfigSurface (visual QA only).
- Full `./scripts/test.sh` must remain green.

## Open Questions for You

1. **ConfigSurface trigger:** gear icon in the resting pill's module row (next to power/launcher), or only accessible via hover menu? I'm guessing resting pill row, right side near power.
2. **Hyprland native blur:** should I attempt `Hyprland.extras` batchMessage for window-level blur, or stick to QML `MultiEffect` blur only? I'm guessing QML-only to avoid API uncertainty.
3. **Fade duration:** use `motion.fast` (existing themed value) or a fixed 140ms? I'm guessing `motion.fast`.

What's wrong or missing?
