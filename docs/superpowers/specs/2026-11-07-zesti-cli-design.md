# Zesti CLI Replacement Design

**Date:** 2026-11-07

## Intent

Replace the installed Caelestia CLI runtime dependency with a Zestify-owned
CLI named `zesti`. Zesti must own wallpaper state, palette generation,
application theme generation, desktop utility commands, and shell control.
The existing Zestify Quickshell process must continue to start, stop, receive
IPC calls, render its surfaces, and handle the session exactly as it does now.

`zesti` is the primary public command. The existing `zestify` command remains
as a silent compatibility entry point for current shell code, keybindings, and
user scripts. Zesti does not install a command named `caelestia` and does not
shadow or modify an installed Caelestia package.

## Goals

- Remove all runtime calls to the `caelestia` executable and all reads from
  Caelestia-owned state after the installation handoff.
- Cover the useful capabilities of Caelestia's `shell`, `toggle`, `scheme`,
  `screenshot`, `record`, `clipboard`, `emoji`, `wallpaper`, `resizer`,
  `install`, and `update` commands with Zesti-owned behavior.
- Preserve every command currently used by the Zestify shell and Hyprland
  integration through the `zestify` compatibility entry point.
- Keep the Quickshell configuration and IPC identity `zestify`; changing the
  executable must not create a second shell process or rename shell IPC.
- Generate dynamic Material palettes with Zesti-owned adaptations of
  Caelestia's GPL palette-selection/generation algorithms, backed directly by
  `materialyoucolor` and Pillow, plus repository-owned templates.
- Store configuration, state, data, and cache only in Zestify XDG paths.
- Provide clear non-zero exits and actionable errors when optional desktop
  tools are missing.

## Non-goals and Anti-goals

- Do not install a fake `caelestia` compatibility executable.
- Do not manage or reinstall the broader Caelestia dotfiles distribution.
- Do not import Caelestia Python modules or QML modules at runtime.
- Do not delegate palette generation to `matugen` or another CLI backend.
- Do not change the visible shell design, IPC target, surface names, session
  timeouts, or startup semantics as part of this project.
- Do not silently fall back to Caelestia if Zesti fails. That would hide an
  incomplete replacement.
- Do not delete the user's Caelestia package, state, configuration, or themes.

## Naming and Compatibility

The installer creates both links:

```text
~/.local/bin/zesti    -> <repo>/bin/zesti
~/.local/bin/zestify  -> <repo>/bin/zestify
```

`bin/zesti` is the canonical Python entry point. Implementation lives in a
small importable `zesti/` package so parsing, services, and desktop backends
can be tested separately. `bin/zestify` is a thin compatibility launcher. It
translates the existing flat interface and then executes the same Zesti
implementation; it does not contain a second implementation.

Compatibility output must remain machine-safe. In particular, the launcher
must not print deprecation warnings before JSON used by QML.

The compatibility mappings are:

| Existing command | Canonical command |
| --- | --- |
| `zestify start` | `zesti shell start` |
| `zestify stop` | `zesti shell stop` |
| `zestify restart` | `zesti shell restart` |
| `zestify status` | `zesti shell status` |
| `zestify logs` | `zesti shell logs` |
| `zestify ipc SURFACE` | `zesti shell open SURFACE` |
| `zestify wallpaper FILE [--monitor/--all]` | `zesti wallpaper set FILE ...` |
| `zestify random`, `list`, `thumb` | corresponding `zesti wallpaper` action |
| `zestify proxy`, `cache` | corresponding canonical action |
| `zestify lock`, `sleep`, `volume`, `brightness`, `mic` | same Zesti action |

The shell will be updated to invoke `zesti` by default while still honoring
`ZESTI_BIN`, then the old `ZESTIFY_BIN` test/development override.

## Public Command Model

### Shell and surfaces

```text
zesti shell start [--foreground] [--log-rules RULES]
zesti shell stop
zesti shell restart
zesti shell status [--json]
zesti shell logs [--follow] [--log-rules RULES]
zesti shell show
zesti shell call TARGET FUNCTION [ARG ...]
zesti shell open SURFACE
```

Start remains detached by default, matching today's installed `zestify
start`. `--foreground` is the explicit development mode. All commands use the
existing Quickshell config and IPC target `zestify`. Stop and restart enumerate
and wait for matching Quickshell instances before escalating, avoiding a race
where `qs -n` skips relaunch.

Valid surfaces remain `launcher`, `wallpaper`, `system`, `media`, `audio`,
`calendar`, `power`, `network`, `bluetooth`, and `battery`. `call` provides a
raw escape hatch equivalent to Caelestia's positional shell messages.

### Wallpaper and palette

```text
zesti wallpaper get [--monitor NAME] [--json]
zesti wallpaper set FILE [--monitor NAME | --all] [--no-smart]
zesti wallpaper random [DIR] [--monitor NAME | --all] [--no-filter]
                         [--threshold FLOAT] [--no-smart]
zesti wallpaper list [DIR] [--json]
zesti wallpaper print [FILE] [--mode dark|light|smart]
zesti wallpaper thumb FILE

zesti scheme list [--names|--flavours|--modes|--variants]
zesti scheme get [--name|--flavour|--mode|--variant|--json]
zesti scheme set [--name NAME] [--flavour NAME]
                 [--mode dark|light|smart] [--variant NAME|--random]
zesti scheme apply
```

The command names are Zesti's own action-oriented interface. They cover
Caelestia's wallpaper and scheme capabilities without preserving every old
flag spelling. Current Zestify wallpaper commands remain accepted only through
the compatibility launcher.

For a global or primary wallpaper, Zesti atomically writes the global path,
generates the global scheme, applies configured application themes, and
truncates per-monitor overrides so existing QML file watches remain attached.
For a secondary monitor it writes only that monitor's path and scheme; it does
not retheme global applications. `--all` deliberately applies one global
wallpaper and clears overrides.

Video wallpaper palette generation uses a cached `ffmpeg` frame. Images and
frames are opened with Pillow, quantized through `materialyoucolor`, and scored
with an adapted copy of Caelestia's GPL source-colour selection. An adapted
palette generator creates the selected Material variant and harmonizes the
terminal and named accent roles expected by the shell. Zesti owns this code in
its package: it neither imports Caelestia nor invokes a palette CLI.

The generator selects the effective light/dark mode, emits the camelCase roles
consumed by the shell without leading `#`, derives `term0` through `term15`,
adds Zesti metadata, and atomically writes `scheme.json`. Invalid images or
missing Material roles leave the prior valid scheme untouched; a first-run
failure uses the built-in dark fallback rather than crashing the shell.

Static schemes and application templates are repository data under `data/`.
Any adapted GPL material retains attribution in `NOTICE`; runtime imports from
Caelestia are forbidden. Zesti owns template rendering and can apply terminal
sequences, Hyprland colors, Fuzzel, GTK, Qt, btop, cava, and the other shipped
templates enabled in configuration. A failure in one optional application
adapter is reported but does not prevent state and the shell palette from
updating. Theme application is serialized by a state lock.

### Desktop utilities

```text
zesti screenshot [--region [GEOMETRY]] [--freeze]
zesti record start [--region [GEOMETRY]] [--sound]
zesti record stop [--clipboard]
zesti record toggle [--region [GEOMETRY]] [--sound] [--clipboard]
zesti record pause
zesti clipboard pick|delete
zesti emoji list|pick|fetch
zesti workspace toggle NAME
zesti window resize PATTERN MATCH WIDTH HEIGHT ACTIONS
zesti window pip
zesti window watch
```

These are Zesti-owned implementations around standard Wayland/Hyprland tools.
Screenshot uses `grim`, `slurp`, `swappy`, and `wl-copy`; freeze selection uses
the available Hyprland-compatible freeze backend and fails clearly rather than
silently taking a live capture when unavailable. Recording uses
`gpu-screen-recorder`; its state and notification ID live under Zestify state.
Clipboard uses `cliphist`, `fuzzel`, and `wl-copy`. Emoji data is shipped under
`data/`, and `fetch` refreshes it atomically. Workspace/window commands use a
small native Hyprland socket adapter and Zestify configuration, not Caelestia.

The old Caelestia-style verbs `toggle` and `resizer` may be accepted as hidden
aliases by `zesti`, but documentation and new code use `workspace` and
`window`.

### Existing Zestify controls and new operational commands

The following remain first-class because the shell and keybindings use them:

```text
zesti lock [--wait] [--config-only] [--out PATH]
zesti sleep
zesti volume up|down|mute|set VALUE
zesti mic up|down|mute
zesti brightness up|down|set VALUE
zesti proxy ensure ...
zesti cache status|prune
```

Zesti adds:

```text
zesti config path|show|validate|edit
zesti doctor [--json]
zesti install [installer options]
zesti update [--check]
zesti version
```

`doctor` distinguishes required dependencies from feature-specific optional
ones and checks writable XDG paths, shell IPC, required Python palette
libraries, and wallpaper state. `install` invokes this repository's installer. `update --check` reports
whether the checked-out branch is behind its upstream; plain `update` refuses
a dirty tree, performs a fast-forward-only Git update, reruns installation,
and restarts the shell only if it was running. It never updates Caelestia.

## Configuration and State

Canonical paths honor their XDG environment variables:

```text
~/.config/zestify/config.json
~/.config/zestify/templates/
~/.local/share/zestify/
~/.local/state/zestify/scheme.json
~/.local/state/zestify/wallpaper/path.txt
~/.local/state/zestify/wallpaper/current
~/.local/state/zestify/wallpaper/thumbnail.jpg
~/.local/state/zestify/wallpaper/monitors/<connector>.txt
~/.local/state/zestify/wallpaper/monitors/<connector>-scheme.json
~/.local/state/zestify/record/
~/.cache/zestify/
```

The current `config/default.json` remains the base. It gains CLI sections for
theme application, recording, workspace toggles, window rules, screenshot and
optional post-hooks. Existing partial user files continue to deep-merge over
defaults; no existing key changes meaning.

All generated state is written atomically. Monitor names are converted to a
safe filename slug. JSON command output has stable fields including `ok` and,
on failure, `error`; human-readable mode sends diagnostics to stderr and uses
standard exit codes (`0` success, `1` runtime failure, `2` usage error).

## Migration

Installation runs `zesti migrate` before switching QML state paths. Migration
is idempotent and recorded with a schema version in
`~/.local/state/zestify/migration.json`.

On the first run it copies, never moves or deletes:

- Caelestia's current global and per-monitor wallpaper paths;
- the current scheme metadata as an immediate fallback;
- user CLI preferences that map cleanly to Zesti configuration;
- no dotfiles deployment state.

Zesti then regenerates the current palette with Matugen when the source file is
available. If regeneration fails, the copied valid scheme keeps the shell
usable and migration reports the failure. Re-running without `--force` is a
no-op. `--force` re-imports user-editable source state but still never deletes
Caelestia data.

QML palette/wallpaper watchers, the lock script, and the wallpaper backend are
changed together from `.../caelestia/...` to `.../zestify/...`; there must be no
release state where writes and watches point to different roots.

## Installer and Uninstaller

The installer:

- requires `zesti` core dependencies, including `matugen`, instead of
  `caelestia`;
- reports optional dependencies by feature rather than failing installation;
- links both CLI names;
- changes managed autostart to `zesti shell start`;
- detects and stops a running Caelestia shell only during the one-time handoff;
- does not call Caelestia for migration or wallpaper generation;
- starts Zestify and verifies `zesti shell status`.

The uninstaller removes both CLI links and its managed blocks. It no longer
restores `caelestia shell` or starts Caelestia, because Zesti is now the owned
installation rather than a temporary overlay. It still preserves Zestify
configuration/state unless `--purge` is explicit.

## Internal Structure

```text
bin/zesti                  canonical executable
bin/zestify                compatibility executable
zesti/cli.py               parser, dispatch, output policy
zesti/paths.py             XDG paths and atomic writes
zesti/config.py            default/user config loading and validation
zesti/shell.py             Quickshell lifecycle and IPC
zesti/wallpaper.py         wallpaper state, listing, thumbnails
zesti/palette.py           Matugen adapter and role normalization
zesti/theme.py             template/application adapters
zesti/hypr.py              Hyprland socket messages and dispatch
zesti/capture.py           screenshot and recording
zesti/desktop.py           clipboard, emoji, workspace/window tools
zesti/doctor.py            diagnostics
zesti/migrate.py           one-time Caelestia import
data/schemes/              repository-owned static palettes
data/templates/            repository-owned application templates
data/emojis.txt            built-in picker data
```

The existing wallpaper proxy and lock implementations may initially be called
through narrow adapters, then moved behind package functions when touched.
There is one parser and one implementation for both executable names.

## Failure Handling

- A palette failure never overwrites the last valid `scheme.json`.
- A global wallpaper change commits the new path only after its palette is
  valid; monitor-specific failure leaves that monitor's prior state intact.
- Shell start reports an already-running instance as success; restart waits for
  teardown before launch.
- Missing optional tools fail only the requested feature and identify the
  package/executable needed.
- Cancellation from `slurp`/`fuzzel` is a clean no-op, not a traceback.
- Interrupted migration remains safe to rerun because each destination is
  atomically written and the version marker is written last.
- Update refuses dirty or detached worktrees and never resets user changes.

## Testing and Acceptance

Tests are written before each behavior change. Unit tests use temporary XDG
homes and fake executables/sockets; they do not touch the live desktop.

Required automated coverage includes:

- parser/help/version and every primary command family;
- exact legacy `zestify` translation for all commands used by QML and Hyprland;
- shell start/stop/status/restart race handling;
- Matugen JSON normalization, missing roles, videos, static schemes, and no
  overwrite after generation failure;
- global, monitor, all-monitor, random, and migration wallpaper state;
- application adapter isolation and atomic writes;
- screenshot/record/clipboard cancellation and missing dependencies;
- Hyprland workspace and window dispatch using fake sockets;
- installer dry-run/idempotency and uninstaller round-trip;
- proof that no runtime code invokes/imports Caelestia;
- QML tests updated to Zestify state and `zesti` command paths;
- the complete Python, QML, and `qmllint` suite.

Manual acceptance on the live desktop checks:

1. `zesti migrate`, then remove `caelestia` from `PATH`.
2. Start, status, open every surface, restart, and stop the shell.
3. Apply image and video wallpapers globally and per monitor; verify shell and
   configured application palettes update.
4. Lock/unlock, idle handling, volume/brightness OSD, and sleep behavior.
5. Screenshot, recording, clipboard, emoji, workspace toggle, and window PiP.
6. Reboot/login autostart with no Caelestia shell or CLI process involved.
7. Run `zestify` legacy commands and verify identical shell-visible behavior.

The replacement is complete when the test suite passes, manual shell behavior
is unchanged, `grep` finds no runtime Caelestia invocation or state read
outside migration/attribution, and installation no longer requires the
Caelestia CLI.

## Builder-owned Calls

- Exact Python class/function boundaries inside the modules above.
- Which application adapters are direct renderers versus Matugen template
  invocations, provided all shipped templates are Zesti-owned and isolated.
- Exact wording and color of human-facing diagnostics.
- Whether hidden `toggle`/`resizer` aliases are implemented in the parser or
  compatibility normalization layer.
- Internal cache keys and thumbnail dimensions, provided existing UI quality
  does not regress.
