# CPU, GPU, RAM and UI performance analysis — 2026-11-13

The live desktop's largest measured render-GPU owner was **Hyprland**, while
the browser was the largest measured CPU/RAM consumer. Zestify's wallpaper used
the hardware video engine. Controlled UI tests show backdrop blur over moving
video, rotating album art, party effects and animated popups are the main
continuous rendering workloads. Most settled settings/device panels are cheap.

Three further optimizations were implemented and verified during this analysis:
GPU telemetry is now consumer-owned, and resource labels reserve their width so
ordinary telemetry changes do not animate the pill's geometry. Notification
cards no longer repeatedly pause already-stopped expiry animations.

## Live desktop: who uses what

90.002 seconds, 45 approximately two-second intervals, 12 logical CPUs. This is
an **active-session capture**, with browser and coding tools running; it is not
a clean idle baseline. Means are duration-weighted. Process groups follow parent
trees, with nested Zestify/Codex/observer processes assigned separately. No PID
reuse or shared DRM-client ownership occurred. Raw readable-process results cover
337 observed process identities in the JSON, rather than only this top table.

| Process group | CPU, one core | GPU render | GPU video | Latest available PSS, MiB |
| --- | ---: | ---: | ---: | ---: |
| Zen browser | 56.02% | 3.46% | 3.36% | 2241.8 |
| Hyprland and child helpers | 13.64% | 35.16% | 0.00% | 167.0 |
| Codex and agent tooling | 13.63% | 0.00% | 0.00% | 804.2 |
| Zestify | 11.09% | 1.61% | 4.42% | 868.7 |
| Other system and user processes | 6.20% | 0.00% | 0.00% | 75.4 |
| Kitty and shell helpers | 2.86% | 2.76% | 0.00% | 113.7 |

System CPU averaged **9.04% of the whole 12-thread machine**, peak 12.07%.
Visible GPU clients together averaged **43.00% render** and **7.77% video**;
these are independent engine classes, not numbers to add. Hyprland accounted
for 81.8% of observed render-engine work. That is process attribution; the live
capture alone cannot identify how much was blur versus other composition.

The collector itself consumed **3.00% of one core** (about 0.25 machine CPU
percentage points), with mean scans of 61 ms. It is excluded from application
groups. Very short-lived/unreadable processes may be missed; full-capture CPU
contributions include only measured lifetime intervals. PSS is the latest
available 0/30/60/90-second snapshot, not an averaged or perfectly simultaneous
allocation measurement. Summed RSS would double-count shared pages.

### Zestify and its threads/helpers

Quickshell alone averaged 8.06% of one core, 1.61% render-engine busy and
4.42% video-engine busy. Its GUI thread averaged 2.24%, principal scene-graph
render thread 1.98%, second render thread 0.41%, and two Wayland event threads
0.52%/0.43%. FFmpeg stream/video-render/demux threads were each about 0.3–0.4%.
These thread figures are parts of the process total, not additional CPU.

The GPU telemetry helper averaged **2.94% of one core**, PSS **17.9 MiB**.
The logind watcher averaged **0.089%**, PSS **8.3 MiB**. Telemetry's all-process
fdinfo scan was measurable even with System closed; the new ownership gate
removes that work when no visible System surface requests it. The live capture
predates this change; no after-change whole-desktop percentage is claimed.

### RAM

Physical RAM: **15.34 GiB total, 9.71 GiB available, 5.63 GiB used by the
MemAvailable definition**, with no swap used. Reclaimable filesystem cache is
not equivalent to application memory. Memory pressure was zero across the
capture; CPU some-pressure averaged 0.60%, I/O some/full pressure 4.57%/4.05%.
The capture does not identify the source of I/O stalls.

Quickshell had about **837.6 MiB PSS** in the live capture. A separate mapping
inspection found **763.8 MiB anonymous PSS** in smaps_rollup. Grouping mappings
by type attributed 746.5 MiB PSS to anonymous mappings, 67.7 MiB to libraries
and 15.1 MiB to other mapped files; these overlapping views are not added.
This establishes private/anonymous
allocation as the dominant category; it does **not** prove a leak or assign it
to a particular component. The much smaller fresh-fixture process below shows
that active assets, workload/history and allocator/cache lifetime matter.

Quickshell DRM clients reported approximately **380.4 MiB render-buffer resident
memory** and **83.8 MiB video-client resident memory**. Intel unified graphics
memory can overlap CPU mappings and other clients: do not add these figures to
PSS, RSS, physical RAM, or one another as unique ownership.

## Every surface: controlled native measurements

50 six-second samples across 36 cases, fresh Quickshell processes, one isolated
1920×1200@60 headless output using the native Intel ADL GT2 OpenGL renderer.
Each run recorded a two-second collapsed baseline, 2.5-second opening settle,
six approximately one-second counter intervals, then PSS two seconds after
closing. These trials used the source before the new optimizations.

The harness uses actual production components and the portrait GIF, with
representative synthetic player/art/lyrics, 16 gallery images, 18 Wi-Fi rows,
12 Bluetooth rows, 12 audio nodes and a 76% battery. It disables session D-Bus,
PipeWire connection, logind/power timers and actual actions, uses isolated XDG
state and an inert wallpaper CLI. Lock measurement preserves the visual tree
but substitutes an Item for the secure protocol surface. Party input is fallback
or synthetic spectrum, not live audio capture. These are **UI/effect measurements**,
not physical radio scans, actual audio-device operation or secure-lock/PAM tests.

GPU render combines Quickshell and isolated Hyprland for the same engine; CPU
below is Quickshell alone. Persistent GPU-helper CPU adds roughly 2.5–3.3% of
one core to these pre-optimization cases. RAM is whole-Quickshell PSS, not a
component allocation. Deltas compare each fresh process before opening and after
closure. Negative deltas reflect settling/reclamation. Values are medians where
two runs exist; single-run rows are screening results.

| Surface / workload | Runs | Qs CPU | Combined render GPU | Qs PSS MiB | Open PSS Δ MiB | Closed PSS Δ MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Collapsed pill | 2 | 0.66% | 5.14% | 233.5 | -3.3 | -3.3 |
| Hover card, paused player / fallback bars | 1 | 7.56% | 17.71% | 240.2 | +5.9 | +4.6 |
| Hover card, playing player / fallback bars | 1 | 11.87% | 21.06% | 240.1 | +3.9 | +3.9 |
| Launcher | 1 | 0.49% | 0.98% | 258.2 | +17.8 | +14.2 |
| Wallpaper Studio | 1 | 0.66% | 0.14% | 240.4 | +5.9 | +5.5 |
| System | 1 | 3.77% | 6.17% | 248.0 | +9.7 | +8.5 |
| Media, paused | 1 | 0.66% | 0.26% | 241.7 | +3.3 | +3.3 |
| Media, playing / rotating art | 1 | 5.93% | 17.85% | 237.7 | +2.1 | +1.9 |
| Audio | 1 | 0.33% | 0.21% | 239.3 | +1.8 | +1.1 |
| Calendar | 1 | 0.49% | 0.21% | 235.4 | -3.0 | -4.6 |
| Network | 1 | 0.65% | 0.31% | 232.3 | -1.9 | -2.4 |
| Bluetooth | 1 | 0.49% | 0.34% | 236.0 | -2.5 | -2.7 |
| Battery | 1 | 0.66% | 0.20% | 235.7 | -2.9 | -3.1 |
| Settings | 1 | 0.82% | 0.39% | 249.6 | +11.0 | +8.4 |
| Notification drawer + 100-entry burst | 1 | 0.66% | 0.21% | 340.2 | +101.1 | +75.1 |
| Five animated notification popups | 1 | 11.83% | 13.27% | 246.7 | +12.4 | +6.3 |
| Power drawer + actual portrait GIF | 2 | 11.35% | 7.20% | 251.5 | +10.3 | +10.2 |
| Focus, idle | 1 | 0.49% | 0.26% | 232.5 | -4.0 | -4.0 |
| Focus, running | 1 | 2.63% | 5.74% | 233.5 | -4.7 | -4.7 |
| Party, fallback animation | 1 | 24.72% | 26.86% | 264.7 | +28.5 | +8.9 |
| Party, 60 Hz synthetic spectrum | 2 | 32.23% | 31.28% | 263.1 | +26.0 | +8.1 |
| Lock curtain, fully pulled / settled | 1 | 0.49% | 0.34% | 238.1 | +1.8 | +1.6 |
| Lock visuals, settled | 1 | 0.33% | 0.28% | 226.4 | -12.7 | -2.0 |
| Authentication dialog visuals | 1 | 1.65% | 3.15% | 243.3 | +7.3 | +0.5 |
| OSD, held visible | 1 | 0.82% | 2.35% | 244.0 | +5.4 | +0.3 |
| Four two-series Canvas charts, 1 Hz | 2 | 2.05% | 2.30% | 257.7 | +16.4 | +10.9 |
| Four two-series Canvas charts, 4 Hz | 2 | 6.15% | 3.78% | 254.6 | +16.4 | +10.7 |

Most settled device/settings panels recorded around 0.3–0.8% Quickshell CPU and
0.1–0.4% combined render in the initial screening. Later static-state compositor
readings varied substantially, so the GPU figures are not universal panel costs.
Their largest QML costs are opening,
content/service changes and retained caches rather than continuous painting.
The graph comparison measured 2.05% versus 6.15% Qs CPU at 1 Hz versus 4 Hz;
the ordinary 1 Hz graphs are not a compelling first C++ rewrite target.

The paused hover card still animates fallback bars; pause does not make that
surface static. Party combines many bar/binding updates and full-screen effects;
the synthetic workload reached 32.23% Qs CPU and 31.28% combined render.
The real portrait GIF added continuous decode/texture work while Power was open.

The 100-notification case is a **burst plus populated drawer**: it allocates
about 101 MiB more PSS while open and retains about 75 MiB after two seconds.
Repeated popup/model churn and allocator/cache retention are included; this is
not evidence that a normal drawer intrinsically costs 101 MiB or leaks memory.
Launcher/settings/graph/party closure also retained several MiB in this short
test. A heap trace/long repeated-open soak is needed to split cache retention
from growing live allocations; no exact heap attribution is claimed.

Static lock/curtain blur settles and then mainly pays for clock updates.
Actual lock keyboard polling (`hyprctl devices` every 500 ms), PAM, native tray
menu populated by real services, optional standalone login greeter and physical
service actions are source-reviewed in the component catalogue, but their
end-to-end resource costs are not numerically benchmarked here.

## Transparency, blur and moving video

The actual 1920×1200, 24 FPS H.264 proxy plays underneath each state. Blur uses
size 8, two passes; theme opacity is 0.88. The opaque case disables blur through
the existing layer rules. Two samples per state, forward/reverse order:

| UI state | Appearance | Combined render, median (range) | Video engine | Qs CPU |
| --- | --- | ---: | ---: | ---: |
| Collapsed pill | 88% opacity, blur off | 11.15% (10.55–11.75) | 4.15% | 8.52% |
| Collapsed pill | 88% opacity, blur on | 35.70% (32.64–38.75) | 3.21% | 9.58% |
| Collapsed pill | Opaque, blur off | 10.59% (9.28–11.91) | 4.20% | 8.18% |
| System open | 88% opacity, blur off | 12.25% (10.87–13.63) | 3.37% | 10.84% |
| System open | 88% opacity, blur on | 38.99% (38.82–39.16) | 2.90% | 9.30% |
| System open | Opaque, blur off | 12.51% (12.22–12.79) | 3.48% | 10.84% |
| Power drawer open | 88% opacity, blur off | 14.76% (14.37–15.14) | 3.47% | 19.73% |
| Power drawer open | 88% opacity, blur on | 42.11% (39.77–44.44) | 2.90% | 16.95% |
| Power drawer open | Opaque, blur off | 16.45% (15.05–17.86) | 4.00% | 18.10% |

Collapsed render increased from **11.15% with blur off to 35.70% with blur on**.
System and Power show the same large effect. Removing backdrop blur or using
opaque surfaces is the strongest measured GPU tradeoff for a video wallpaper
in this workload. A smaller blur radius/pass count is another candidate, but
was not A/B measured. User appearance settings were not changed on the host.

Lower video busy in blur-on cases is **not an efficiency result**: presentation
FPS/decoded-frame counts were not captured in this surface harness, so it may
reflect throughput, scheduling or dropped-frame effects. Busy time is also
not electrical power, temperature or a frame-time measurement. General idle
compositor readings varied from near zero to about 10%, including a sample with
zero pill width changes; retain the ranges and do not blame all such work on
pill resizing.

The earlier isolated wallpaper-only benchmark independently measured changing
the cap from 30 to 24 FPS: median CPU 10.62→8.62%, video-engine busy 4.84→4.36%,
render 8.00→7.35%. 15 FPS/720p measured 5.25% CPU, 0.99% video and 4.42% render.
Pausing stopped measured steady decode/render work while retaining decoder RAM.
Those results have three samples per setting and frame counters; see the
[wallpaper report](wallpaper-gpu-measurements-2026-11-13.md) for variability and
quality tradeoffs. They are not whole-desktop improvement percentages.

## Optimizations implemented in this analysis

1. **Consumer-owned GPU collection.** `Stats.setGpuConsumer()` deduplicates
   owners; System registers only while visible/sampling, releases on stats
   replacement, hiding and destruction. Lock/DPMS disable its sampling. With
   no consumers, the Python helper stops, pending history clears and late
   responses cannot restore stale data. CPU/RAM/network polling continues.
   Reopening starts fresh GPU history; no idle five-second samples are falsely
   plotted as one-second history. Crash backoff and borrowed consumers remain
   supported. Native closed-panel samples measured zero helper CPU/PSS; visible
   System resumed about 3.3% one-core helper CPU / 16.9 MiB PSS on this desktop.

2. **Stable telemetry-label geometry.** TextMetrics reserves CPU width through
   100% and RAM width through physical capacity in the actual font/scale. Ordinary
   values no longer change Resources implicit width and trigger Pill's 420 ms
   width animation. The Wayland PillWindow itself is full-screen-sized; the
   affected geometry is the painted pill, centering and input mask. The pill is
   slightly wider at rest to reserve the digits.

3. **Avoid invalid animation pause work.** Notification cards pause expiry only
   while the expiry animation is running. The earlier 100-notification burst and
   popup runs logged 787 stopped-animation pause warnings; corrected runs logged
   none. Existing hover/hidden-card timeout semantics remain verified. This is
   a lifecycle/logging fix, not a measured reduction in expiry-progress CPU.

The deterministic native test stops unrelated Stats polling, alternates CPU
9%/10% once per second and keeps RAM fixed. Two samples per source version:

| Same synthetic label workload | Before | After |
| --- | ---: | ---: |
| Pill widthChanged callbacks in ~6 s | 156, 156 | 0, 0 |
| Qs CPU, one core | 4.93% | 0.25% |
| Qs + compositor CPU, one core | 8.80% | 0.41% |
| Combined render GPU | 11.35% | 0.42% |

This confirms the geometry/repaint mechanism and eliminates its unnecessary
animation. It is a synthetic digit-boundary test, not a claim that every idle
desktop will save the same amount. Uncontrolled collapsed render medians were
5.14% before and 4.96% after, with wide
ranges; they do not establish a general idle GPU improvement.

Five affected surfaces were checked again with corrected service metadata and
the final source. Network fixtures now supply QObject signals, lock fixtures
supply the full auth interface, and wallpaper entries supply `isVideo`. No QML
scene/type/reference/binding-loop warning was found in these follow-up logs.
GPU telemetry remained stopped because none of these states subscribes to it.

| Corrected follow-up, one run each | Qs CPU | Combined render | Qs PSS MiB | Open PSS Δ MiB | Closed PSS Δ MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wallpaper Studio | 0.33% | 10.91% | 237.8 | -2.2 | -3.1 |
| Network | 0.49% | 0.40% | 225.8 | -1.8 | -1.2 |
| Notification drawer + 100-entry burst | 0.50% | 0.39% | 384.2 | +155.3 | +81.2 |
| Five animated notification popups | 12.14% | 11.73% | 244.2 | +13.4 | +7.4 |
| Lock visuals, settled | 0.82% | 0.28% | 220.1 | -12.5 | -2.7 |

The static Wallpaper run again illustrates compositor variation: Quickshell
render/CPU remained small, but combined render rose to 10.91%. This does not
establish an expensive gallery renderer. The notification burst's open delta
varied 101–155 MiB and retained delta 75–81 MiB across versions/fixtures; allocation
and cache/churn investigation remains more useful than a language rewrite.

## Rendering work after this baseline

The five additional rendering techniques are implemented and measured in
[render-optimizations-2026-11-14.md](render-optimizations-2026-11-14.md): static
lock blur caching, retained graph grids, partial chart updates, direct album
shader sampling, and bounded native pill windows. The numbers above describe
this report's earlier baseline and should not be treated as the final rendering
implementation.

## All existing methods and whether C++ helps

The [complete component and optimization catalogue](performance-components-2026-11-13.md)
lists every UI surface, transparency/shader layer, service/helper and existing
method, with source references. It separates implemented methods from remaining
proposals and identifies which methods were already architectural choices.
Prior measured CLI/image/scan/proxy/socket gains remain in the
[code review report](code-review-2026-11-13.md).

The methods include reducing FPS/pixels and hardware-compatible video formats;
pause policies; lazy imports; resize-before-RGB allocation; source/probe/proxy
caching; surface unloading and visibility gates; bounded histories and virtualized
lists; native/event-driven services; stopped settled timers; minute-boundary
clocks; linear visualiser smoothing; final-size image/text work; bounded/debounced
workers; ownership-aware radio cleanup; disabled secondary popup work; batched
deduplicated compositor rules; reused network connections/bounded transfers;
and chunked IPC with fewer syscalls/copies. Atomic image/frame publication,
serialized wallpaper writes and disk-backed rollback also preserve correctness
and avoid unsafe duplicate work; they have no standalone speedup claim.

**C++ is useful selectively, but a wholesale rewrite is not justified by these
measurements.** Qt rendering/video decode, Hyprland blur, ffmpeg encoding,
image kernels and cava FFT already execute native code. Moving their Python/QML
orchestration to C++ does not remove pixels, blur passes or texture samples.
The first measurable telemetry cost has now been removed from idle operation
without a rewrite.

| Remaining candidate | Best next step / native-code judgment |
| --- | --- |
| Video + backdrop blur | Reduce/disable blur, lower wallpaper FPS/resolution, or pause under suitable conditions. C++ orchestration will not fix the measured compositor GPU work. |
| Party | First reduce effect area/resolution/texture samples and bar update work; consider a QQuickItem/QSG geometry implementation if item/binding costs remain hot. Measure frame time and quality. |
| Multiple visualisers | Share capture/subscriber ownership before optimizing serialization. Each instance currently owns Python+cava. A native binary audio bridge is plausible if forwarding remains hot; FFT is already native. |
| GPU telemetry while System open | C++ could reduce parser/path/string allocations, but proc enumeration syscalls remain. Profile after the new ownership gate before adding native integration. |
| Retained memory | Right-size images/GIF textures, batch notification churn, and conditionally load heavy bodies after measuring heap lifetime. C++ does not automatically reduce retained caches. |
| Popup expiry bars | Five continuously animated popup bars measured about 12% Qs CPU. Test a coarser progress-update cadence with deadline/hover semantics intact; this was not implemented or A/B measured. |
| Lock keyboard/focus clock | Replace repeated process polling with compositor events; align second-resolution clock updates while preserving deadlines. These are scheduling changes first. |
| Settings/calendar/battery/ordinary 1 Hz graphs | Current settled work is small. No measured basis for a C++ rewrite. |
| Logind watcher | Native D-Bus/inhibitor ownership could reduce several helper processes/PSS, but measured watcher CPU is tiny. Preserve lock-before-sleep behavior. |

The repository's existing C++17 auth protocol improved 1000 local socket
messages from 782.618 ms to 4.770 ms through syscall/buffer changes **within
C++**. That is evidence for fixing access patterns, not a Python→C++ speedup.
No language-rewrite A/B measurement was performed. A new native shell extension
would also need build/install integration, object ownership and shutdown tests.

## Verification, evidence and limits

- Final `./scripts/test.sh`: **337 Python tests, 335 QML cases, qmllint passed**.
- Focused GPU tests: 17 passed; System UI lifecycle test passed; resource width
  regression passed across scales/digit boundaries.
- Independent review exercised Loader unload, inherited visibility, sampling
  changes and swapping injected Stats objects; no actionable defect found.
- Native fixture screenshots checked actual Power/portrait and party/bar/lyric
  rendering; logs checked for QML type/reference/binding-loop errors.
- `git diff --check` passed. Existing user changes were preserved. No host lock,
  radio/audio action, theme change, power operation or native rewrite was made.

Source coverage is broad; runtime coverage is bounded by the described fixtures
and samples. Opening/closing transitions were allowed to settle, not timed;
peak heap, exact component allocation, frame deadlines, real-audio party load,
physical multi-monitor behavior and long-run leakage/power remain unmeasured.
Initial Network/lock/wallpaper fixtures lacked signals/interface metadata and
emitted assignment warnings; their rendered rows are screening evidence. Follow-up
fixtures corrected these and repeated the affected measurements. The new
notification pause guard removed the real stopped-animation warnings.

[Durable raw counters, weighted process/thread results, surface trials and ranges](performance-analysis-2026-11-13.json).
The profiling/harness scripts and screenshots remain in `/tmp/zestify-*` for
this session; the JSON retains the sampled counters and methodology metadata.
