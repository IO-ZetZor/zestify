# Code review and performance work — 2026-11-13

Reviewed the Python CLI and helpers, QML shell components and services, standalone
C++ authentication service, installation scripts, and their tests. Implemented
confirmed fixes and measured the main optimizations. Existing uncommitted changes
were preserved; performance comparisons use the working tree captured before this
review, rather than Git HEAD.

## Fixed findings

| Priority | Finding and resulting behavior | Main files |
| --- | --- | --- |
| High | Greeter destruction could invoke socket callbacks after member state had been destroyed. Disconnect and abort while state is alive; the reproducer now passes ASan/UBSan. | `auth/greeter.cpp`, `auth/greeter.hpp` |
| High | Oversized or heavily escaped responses could throw out of the UI; character limits also disagreed with PAM's UTF-8 byte limit. Validate both encoded frame and response bytes, retain the prompt on rejection, and erase rejected serialized buffers. | `auth/greeter.cpp`, `auth/protocol.cpp` |
| High | Recording did not track its process reliably, used unsupported command options, and could signal other recordings or return an empty file as success. Persist PID/start time/boot identity, signal through pidfds, and wait for finalization before reporting success. Failed startup cleans up its child; interrupted recordings preserve partial output. | `zesti/capture.py` |
| High | Wallpaper writes could leave paths and palettes inconsistent after a later write failed. Selecting the existing thumbnail could destroy it. Serialize set/refresh operations, restore prior files after caught write failures, and publish thumbnail/frame copies through unique temporary files. | `zesti/wallpaper.py` |
| Medium | Authentication supervisor and child used the same shutdown deadline, risking forced termination before PAM cleanup. Give the supervisor a longer grace period. | `auth/daemon.cpp` |
| Medium | Service packaging did not create the greeter's home. Install a tmpfiles rule and create it before starting the daemon. | `auth/Makefile`, `auth/integration/` |
| Medium | Volume, microphone, brightness, and capture CLI handlers supplied incompatible subprocess runner contracts. Dispatch now reaches the real backend and preserves its result. | `zesti/cli.py`, `zesti/controls.py`, `zesti/capture.py` |
| Medium | Screenshots ignored selected geometry and copied a filename instead of image data. Pass validated geometry to the backend, verify PNG output, and copy binary image bytes. Preserve saved images if clipboard publication fails. | `zesti/capture.py` |
| Medium | Clipboard picking copied history preview text instead of decoded contents. Decode through `cliphist`, preserve binary data, and propagate failures. Canonical `pick`/`delete` and the legacy flag now parse. | `zesti/desktop.py`, `zesti/cli.py` |
| Medium | Doctor launched tools to check availability and always returned success. Resolve executable paths without launching programs, check writable Zestify directories, and return failure when required checks fail. | `zesti/operations.py`, `zesti/cli.py` |
| Medium | Update used hard-coded Git state, ignored installation failure, and did not restart correctly. Inspect the actual worktree, refuse dirty/detached/no-upstream updates, install with `--no-start`, and restart only a previously running shell. | `zesti/operations.py`, `zesti/cli.py` |
| Medium | Window resize/PiP/watch were success-returning stubs. Dispatch validated window actions to Hyprland and stream bounded lifecycle events from its event socket. Moves accept negative and zero coordinates. | `zesti/desktop.py` |
| Medium | Emoji refresh fetched no usable data. Fetch bounded Unicode data with a timeout, validate and convert picker rows, publish atomically, and use the saved cache. Failed refreshes retain prior data. | `zesti/desktop.py`, `zesti/cli.py` |
| Medium | Wi-Fi/Bluetooth scanning cleanup followed the current adapter rather than the one whose scan was started. Transfer scan ownership on adapter replacement and retain borrowed scans on teardown. Clear stale Wi-Fi password prompts. | `shell/surfaces/NetworkSurface.qml`, `shell/surfaces/BluetoothSurface.qml` |
| Medium | Disabled secondary notification windows could expire shared popups. Create cards only for enabled popup windows and pause expiration when hidden. | `shell/components/NotificationPopups.qml`, `shell/components/NotificationCard.qml` |
| Medium | Wallpaper filenames containing URL delimiters failed to load; failed proxies could become permanently stuck. Encode local paths and retry failed proxies with bounded 5–60 second exponential backoff. Source/configuration changes reset backoff. | `shell/lib/wallpapers.js`, `shell/backgrounds/`, `shell/surfaces/WallpaperStudio.qml` |
| Medium | Launcher commands dropped metadata substitutions, literal percent signs, and quoted empty arguments. Expand desktop-entry metadata while preserving argument boundaries. | `shell/lib/desktop.js`, `shell/singletons/Apps.qml` |
| Medium | Configuration paths could traverse unsafe object keys or fail on null intermediates. Reject unsafe/empty paths and construct valid intermediate objects. | `shell/lib/config.js` |
| Low | Empty XDG variables and injected HOME were handled incorrectly; failed migrations could be permanently marked done. Honor supplied environment fallbacks and only skip completed migrations. | `zesti/paths.py`, `zesti/migrate.py` |
| Low | Cache pruning lost repeated `--keep` flags; editors with arguments failed and editor errors appeared successful. Preserve each flag, parse editor arguments, and return editor failure. | `zesti/cli.py`, `zesti/controls.py` |
| Low | Tray primary selection disagreed with attached-monitor fallback; a surface callback dereferenced a missing screen. Use active-primary selection and guard the screen. | `shell/components/Pill.qml`, `shell/MonitorShell.qml` |
| Low | Very short videos could produce no preview frame, and malformed average FPS prevented use of a valid reported rate. Retry extraction from zero and try both finite positive rate fields. | `scripts/lock.py`, `scripts/wallpaper-proxy.py`, `zesti/wallpaper.py` |

The README now documents the actual cache command and uninstall behavior, and
provides the standalone authentication test command. The formerly incomplete
native test target now has protocol, configuration, PAM, greeter, and preview tests.

## Performance measurements

Measurements below are local elapsed times, not whole-desktop benchmarks.

| Workload | Before | After | Basis |
| --- | ---: | ---: | --- |
| Fresh Python CLI `version` invocation | 102.88 ms | 82.81 ms | Median of 10 processes; about 20% faster |
| Decode and make a 128px RGB thumbnail from an 8K JPEG | 252.09 ms | 210.81 ms | Median of 3 processes; about 16% faster |
| Peak RSS for that thumbnail process | 283,656 KiB | 183,016 KiB | About 35% lower; output pixel SHA-256 identical |
| Launcher desktop-entry scan | 149.30 ms | 107.95 ms | Same local XDG directories; duplicate scan output removed |
| Warm video-proxy `ensure` helper | 32.245 ms | 0.05594 ms | Median of 10 calls after priming; excludes Python startup |
| Send/receive 1,000 protocol messages with 2,048-character values | 782.618 ms | 5.497 ms | Optimized C++ local socket-pair sample; exact message equality checked |

The final protocol implementation also completed the same workload in 4.770 ms
after removing an extra encoder-buffer copy. These socket timings do not measure
end-to-end login or PAM latency.

Changes responsible for the measured gains:

- Load palette scheme dependencies on demand, reducing imports for unrelated CLI commands.
- Resize images before allocating their RGB copy; retain the original nearest-neighbour samples without JPEG draft/reduction shortcuts.
- Deduplicate XDG application directories and honor the configured directory list; include symlink desktop entries.
- Cache probed video FPS by resolved source path, size, and nanosecond modification time. Warm proxy requests avoid `ffprobe`; source changes invalidate metadata.
- Read protocol chunks with delimiter-aware peeking, leaving subsequent frames in the socket across `Channel` lifetimes instead of receiving one byte per syscall.

Other redundant work removed and checked behaviorally:

- Settled visualisers stop their 16ms interpolation timer and resume when input changes.
- Hidden power portraits release their animated-image source.
- The idle lock curtain does not instantiate its wallpaper or enable its effect layer.
- The clock updates at minute boundaries and stops when hidden.
- Poll intervals are constrained to 250–60,000 ms.
- Layer rules are applied through one `hyprctl` invocation and only when relevant settings change.

No numerical whole-shell CPU/GPU improvement is claimed for these changes.

## Verification completed

- `./scripts/test.sh`: **331 Python tests passed; 331 QML cases passed; qmllint passed**. The suite ran outside the execution sandbox because its local Unix sockets and D-Bus services require that access.
- `make -C auth BUILD=/tmp/zestify-auth-tests -j2 test`: daemon and greeter build, protocol/configuration/PAM checks, configuration syntax check, and three greeter/preview tests passed.
- `make -C auth BUILD=/tmp/zestify-auth-tests DESTDIR=/tmp/zestify-auth-install-check install`: staged installation passed; binary modes and service/sysusers/tmpfiles contents and modes were checked.
- ASan + UBSan scratch builds of `test-auth` and `test-greeter-client`: both passed after the final native change, without sanitizer findings. Builds used `-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer` at compilation and sanitizer flags at linking.
- Regression coverage includes actual temporary Git repositories, real subprocess binary clipboard pipelines, cross-process recorder lifecycle with a test recorder, short-video extraction, cache invalidation, thumbnail sample equality, and injected wallpaper write failures.
- Independent wallpaper checks passed for existing/missing-file rollback, symlink restoration, global and refresh failures, and concurrent refresh/set serialization.
- The Quickshell offscreen harness exercised adapter replacement/scan ownership, special-character wallpaper loading, visualiser quiescence/restart, and actual delayed proxy retry/backoff. It substitutes an Item for the background PanelWindow and an inert video decoder; this verifies proxy logic rather than compositor rendering.
- `bash -n install.sh uninstall.sh scripts/perf-sample.sh`, `sh -n scripts/test.sh`, and `git diff --check` passed. The final changes were reviewed against the initial working-tree snapshot.

## Runtime limits and remaining validation

Live GPU recording, actual desktop clipboard/window actions, online emoji fetching,
physical monitor hotplug, secure Wayland login/VT handoff, and a whole-desktop
CPU/RSS soak were not exercised. The authentication tests use a test-only PAM
module and temporary policies; production PAM policy, logind session teardown,
and supervisor shutdown timing still need integration testing on a disposable
login environment. No production display-manager service was installed or enabled.

Wallpaper rollback handles caught failures and serializes cooperating set/refresh
writers. It does not provide crash-recovery journaling or an atomic multi-file
snapshot to readers. Source-cache invalidation relies on file metadata, not a
content hash. Performance figures describe the recorded workloads and host; they
do not establish that every desktop scenario is faster.

## Follow-up: idle video wallpaper GPU work

- Proxy frame rate is now configurable through `wallpaper.proxy.maxFps` and
  `--max-fps`. The default is 24 instead of 30 FPS: 20% fewer frames per second
  for sources that previously reached the cap. Lower-rate sources retain their rate;
  setting 30 restores the previous cap, while 15 trades smoothness for less work.
- `1080p` and `720p` resolution presets preserve landscape/portrait orientation,
  use even dimensions, and avoid upscaling normal display sizes. On a 1920×1200
  display, `1080p` produces 1728×1080 video, 19% fewer decoded pixels per frame.
  Full monitor resolution remains the default.
- The original video pauses after an initial frame while its proxy is pending.
  Playback resumes on proxy readiness; failed preparation retains the original
  fallback. The first-frame timeout waits for loaded/buffering media so a slow
  load does not pause before it can display a frame.
- H.264 proxies now use 8-bit `yuv420p`, avoiding inherited High 10/4:4:4 formats
  that many hardware decoders do not support. The format cache key changed so
  older proxies are regenerated. Higher-depth sources lose precision in H.264
  proxies; H.265 retains source depth.

The final suite passed **337 Python tests, 332 QML cases, and qmllint**. Added
checks exercise actual player pause/resume, delayed loopback video loading, FPS
selection/cache reuse, legacy format invalidation, 10-bit conversion, preset
dimensions, live settings, and background proxy transitions.

A generated 1920×1200, 24 FPS H.264 proxy was also decoded using the installed
Intel iHD VAAPI driver: the decoder used VAAPI surfaces and reported zero decode
errors. This confirms hardware compatibility for that sample. Total desktop GPU
utilization and Quickshell's selected decoder backend were not measured; the
frame/pixel reductions above are workload calculations, not GPU percentage gains.

Subsequent [controlled GPU measurements](wallpaper-gpu-measurements-2026-11-13.md)
compare the previous cap, new default, lower-resolution presets, and paused
playback, with raw per-process counters retained.
