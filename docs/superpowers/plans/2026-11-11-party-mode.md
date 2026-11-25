# Party Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Smooth the album-cover edge and add a long-press party mode with a morphing pill, falling icons, four-edge visualiser bars, lyrics, and music-reactive shake.

**Architecture:** A new full-screen `PartyWindow` overlays the owning monitor while `ShellState` tracks the owner. `PartyStage` owns the entry/exit morph, icon particles, cover, lyrics, and shake; `VisualiserLevels` centralises cava acquisition so the four `EdgeVisualiser` instances share one stream. `AlbumCover` gains the long-press gesture and fixes its own anti-aliasing.

**Tech Stack:** Quickshell 0.3.1, Qt 6 Quick, QML, cava, qmltestrunner.

**Spec:** Chat-approved design, 2026-11-11 (long-press trigger, morphing pill, four-edge bars, lyrics, shake).

## Global Constraints

- Do not regress existing surfaces, hover card, lyrics, or visualiser behaviour.
- No new runtime dependencies.
- Keep animations disabled/calm when `motion.calm` is true.
- Party mode is per-monitor and never triggers while `Session.locked`.
- QML tests run with `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import shell`.

## Review Focus

- Long press must not swallow the existing short click that opens the media surface.
- Party overlay must not leave the pill reserved gap or block input after exit.
- Bars/cover must still render when cava exits or no player is present.
- Lyrics must disappear cleanly when unavailable and not request while inactive.
- Shake must not reveal wallpaper gaps at the screen edges.

---

### Task 1: Album cover smoothing and long-press gesture

**Files:**
- Modify: `shell/components/AlbumCover.qml`
- Modify: `shell/components/MediaCard.qml`
- Modify: `shell/components/Pill.qml`
- Modify: `shell/surfaces/MediaSurface.qml`
- Test: `tests/qml/tst_album_cover.qml`

**Interfaces:**
- Produces: `AlbumCover.longPressed()`, `AlbumCover.clicked()`, `AlbumCover.longPressDuration: int` (550), `AlbumCover.interactive: bool` (default true). `MediaCard` gains `coverActivated()` and forwards `longPressed()` as `partyRequested()`.

- [ ] Write failing tests for ring anti-aliasing, feathered mask, short click, and >550 ms hold.
- [ ] Run them and confirm they fail for the missing properties/signals.
- [ ] Add `antialiasing`, mask feathering, and a MouseArea + hold timer to `AlbumCover`.
- [ ] Forward click to `MediaCard.coverActivated` and hold to `partyRequested`; wire both in `Pill` and `MediaSurface`.
- [ ] Re-run tests.

### Task 2: Party ownership state

**Files:**
- Modify: `shell/singletons/ShellState.qml`
- Test: `tests/qml/tst_party_state.qml`

**Interfaces:**
- Produces: `ShellState.partyOwner: string`, `toggleParty(screenName)`, `closeParty(screenName?)`, `isPartyOn(screenName): bool`.
- Opening any normal surface, notification drawer, or power drawer closes party mode.

- [ ] Write failing tests for toggle, per-screen ownership, switching, and surface pre-emption.
- [ ] Implement the state functions.
- [ ] Re-run tests.

### Task 3: Shared visualiser source and edge bars

**Files:**
- Create: `shell/components/VisualiserLevels.qml`
- Create: `shell/components/EdgeVisualiser.qml`
- Modify: `shell/components/VisualiserBars.qml`
- Modify: `shell/components/qmldir`
- Test: `tests/qml/tst_visualiser.qml` (extend)

**Interfaces:**
- Produces: `VisualiserLevels.values: var` (32 smoothed 0-1 floats), `active`, `scriptsDir`, `python`.
- Produces: `EdgeVisualiser.edge` (`top|bottom|left|right`), `levels`, `barCount`, `theme`, `s`.

- [ ] Write failing tests for edge level sampling/mirroring helpers in `shell/lib/party.js`.
- [ ] Extract the cava/fallback/smoothing logic from `VisualiserBars` into `VisualiserLevels`; keep `VisualiserBars` behaviour identical.
- [ ] Implement `EdgeVisualiser` with rounded gradient bars growing inward.
- [ ] Re-run visualiser tests.

### Task 4: Party window and stage

**Files:**
- Create: `shell/components/PartyWindow.qml`
- Create: `shell/components/PartyStage.qml`
- Create: `shell/lib/party.js`
- Modify: `shell/MonitorShell.qml`
- Modify: `shell/components/Pill.qml`
- Modify: `shell/components/PillWindow.qml`
- Modify: `shell/components/qmldir`
- Test: `tests/qml/tst_party.qml`

**Interfaces:**
- Produces: `PartyStage.active`, `entry: real` (0-1), `coverRect()`, `exitRequested()`; `PartyWindow` binds `ShellState.isPartyOn(screenName)`, handles Escape, and closes on lock.
- Pure helpers in `party.js`: `lerp`, `clamp01`, `bass(levels)`, `sampleLevel(levels, index, count)`, `shake(energy, time, seed)`.

- [ ] Write failing tests for `bass`, `sampleLevel`, `shake` bounds, and `PartyStage` long-press exit.
- [ ] Implement helpers and `PartyStage` morph/particles/lyrics/shake.
- [ ] Implement `PartyWindow` overlay + Escape + lock handling and add it to `MonitorShell`.
- [ ] Hide the normal pill, drop its exclusive zone, and re-show on exit.
- [ ] Re-run tests.

### Task 5: Visual verification and full regression

**Files:**
- Create: `tests/quickshell/party-ui.qml`
- Create: `tests/quickshell/run-party-ui.py`

- [ ] Capture offscreen frames for entry, settled, and exit states with a fixture cover and lyrics.
- [ ] Inspect frames for smooth cover edges, four edge bar sets, legible lyrics, and no layout overflow.
- [ ] Run `scripts/test.sh`, `qmllint`, and fix regressions.
