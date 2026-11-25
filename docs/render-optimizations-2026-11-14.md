# Rendering optimizations, 14 November 2026

The requested techniques are applied in the relevant rendering paths.
They have different scopes: Qt caches the static lock wallpaper; the graphs
track their own dirty regions; the pill keeps its native Wayland canvas stable.
Hyprland still controls backdrop blur and compositor damage.

The bounded pill-window optimization was removed after the supplied recording
revealed a resizing regression. The original before/after tables below describe
the earlier bounded-window implementation, not the current stable canvas.

## Implementation

| Technique | Implementation | Limits |
| --- | --- | --- |
| Blur caching | `CachedBlur.qml` freezes the completed static wallpaper blur. It explicitly refreshes the input, waits for capture completion, then captures the output. Generation checks reject obsolete completions. | Refreshes for source readiness/revision, size, DPR and blur parameters. Moving desktop video is not static cache content. |
| Partial updates | `UsageChart.qml` compares projected samples, includes adjacent segments and endpoint dots, clears/clips only the dirty span, and suppresses identical-data repaints. | Rolling histories shift old points; that legitimately dirties most or all of the dynamic plot. Qt/Wayland damage is a separate layer. |
| Static content caching | Graph grids are retained Rectangle nodes behind the dynamic Canvas. Artwork uses its cached Image texture directly. Static blurred output is an explicit texture cache. | Ordinary Qt static text/geometry already has retained scene-graph nodes; adding offscreen textures to every UI item would increase memory and draw work. |
| Avoid nested opacity/effect layers | AlbumCover replaces its outer disc layer, mask texture and rotating source capture/MultiEffect with one shader sampling the Image. Crop, rotation, circular/capsule coverage and premultiplied alpha are handled together. Curtain translation/opacity stay outside the blur cache. | Necessary Party camera and portrait effects remain. Plain QSG opacity nodes do not necessarily create an offscreen texture. |
| Damage tracking | Graph invalidation follows changed samples. PillWindow keeps a screen-sized native canvas and animates only its child, with input masks following the pill. | The bounded native pill optimization was removed to fix stale-buffer rescaling. Input Region masks do not restrict drawing. Installed Hyprland damages the entire layer rectangle on commit. |

The curtain unloads both wallpaper and blur-cache objects when inactive.
Full-output blur disables automatic padding beyond the window. A temporary input
capture driver uses opacity 0.0015: above Qt 6.12's preprocessing cutoff (0.001),
below half an RGBA8 channel step. It is drawable only during refresh, and native
pixel comparisons verify the completed output. Zero-opacity/hidden capture
drivers cannot supply reliable completion signals on this backend.

Album artwork retains the previous square source geometry, decode requests,
asynchronous loading, image cache and mipmaps. Native checks cover landscape
and portrait artwork, rotation, circle/capsule edges and click/hold input.
Qt's SVG aspect-preserving decoder may exceed the requested sourceSize rectangle;
that request is not a strict memory cap. The original decoder policy already
has this behavior. Exact size probing without decoding would require an API
such as C++ QImageReader::size(), not another full-size QML Image.

## Measurement method

The baseline is a snapshot of the shell immediately before this rendering work;
it already includes the earlier video-proxy and telemetry optimizations.
An isolated nested Hyprland compositor uses one 1920×1200, 60 Hz headless output,
Qt 6.12 OpenGL on Intel ADL GT2/Mesa, and safe synthetic service data. No host
blur/theme settings, lock operation, power action or radio scan is used.

Each trial starts a fresh shell, warms it for 2 seconds, opens the state, waits
2.5 seconds, and samples six 1-second intervals. Two rounds reverse the case
order. CPU is a percentage of one core. GPU percentages come from DRM fdinfo
engine-time deltas with duplicate clients removed. Render and video engines
remain separate. RAM uses process PSS; unified-memory GPU allocations are not
added to it. Video-sink counts measure delivered decoded frames, not display presentation.
These short controlled samples are not a physical-display,
multi-monitor or long-running leak test.

The accompanying JSON retains the raw samples and summaries. Absolute idle
compositor GPU and process PSS vary between runs; source changes do not establish
that every difference was caused by an individual optimization.

Historical two-run medians before the pill animation correction (CPU and GPU in percent):

| State | Shell CPU before → after | Shell render GPU before → after | Hyprland render GPU before → after | Shell PSS MiB before → after |
| --- | ---: | ---: | ---: | ---: |
| media_paused | 0.66 → 0.66 | 0.021 → 0.009 | 6.06 → 0.14 | 210.2 → 184.4 |
| media_playing | 12.64 → 11.72 | 1.773 → 1.036 | 19.64 → 15.57 | 206.0 → 174.9 |
| power | 14.37 → 13.53 | 1.158 → 0.895 | 5.80 → 4.12 | 210.8 → 187.4 |
| party_synthetic | 43.31 → 44.25 | 11.181 → 6.946 | 19.23 → 16.19 | 224.2 → 189.7 |
| curtain | 0.49 → 0.49 | 0.002 → 0.001 | 0.08 → 0.01 | 201.8 → 172.8 |
| lock_visual | 0.49 → 0.57 | 0.002 → 0.002 | 0.05 → 0.03 | 187.8 → 155.2 |
| graphs_1hz | 2.79 → 1.97 | 0.095 → 0.033 | 1.60 → 0.47 | 219.2 → 172.2 |
| graphs_4hz | 6.39 → 6.32 | 0.201 → 0.123 | 1.95 → 1.31 | 210.8 → 168.9 |
| collapsed_video_blur_on | 8.35 → 8.84 | 1.197 → 1.118 | 27.68 → 20.69 | 268.8 → 232.1 |

| State | Hyprland CPU before → after | Hyprland PSS MiB before → after |
| --- | ---: | ---: |
| media_paused | 2.78 → 0.08 | 91.0 → 90.8 |
| media_playing | 6.40 → 6.47 | 91.0 → 90.8 |
| power | 1.15 → 0.90 | 91.0 → 90.8 |
| party_synthetic | 6.64 → 6.31 | 91.0 → 90.9 |
| curtain | 0.08 → 0.00 | 91.0 → 90.9 |
| lock_visual | 0.00 → 0.08 | 91.0 → 90.9 |
| graphs_1hz | 0.41 → 0.16 | 91.0 → 90.9 |
| graphs_4hz | 0.41 → 0.41 | 91.0 → 90.8 |
| collapsed_video_blur_on | 4.17 → 5.07 | 91.1 → 90.9 |

Per-run CPU/render/PSS values, ranges, helper work, open/close deltas and
native layer geometry are retained in [the raw JSON](render-optimizations-2026-11-14.json).
Helper CPU and PSS are zero in these steady samples; transient frame extraction
is outside the warmed sampling interval.
Before video engine: 3.11%; video-sink delivery: 24.06 frames/s.
After video engine: 2.91%; video-sink delivery: 24.05 frames/s.

The earlier collapsed pill measured **503×46** instead of 1920×1200,
**99.0% less native rectangle area per commit**. That optimization is no longer
enabled: the current native canvas remains **1920×1200** in this fixture.
The original measurements used disabled compositor animations and missed the
rendered-buffer regression.


The two after-run PSS readings vary as follows:

| State | After PSS range, MiB |
| --- | ---: |
| media_paused | 160.4–208.3 |
| media_playing | 162.9–186.8 |
| power | 175.9–199.0 |
| party_synthetic | 182.6–196.9 |
| curtain | 164.1–181.5 |
| lock_visual | 146.5–163.8 |
| graphs_1hz | 165.2–179.2 |
| graphs_4hz | 161.8–176.1 |
| collapsed_video_blur_on | 228.7–235.5 |

The output blur cache adds one RGBA8 texture, about **8.8 MiB at 1920×1200, DPR 1**,
or 35.2 MiB at DPR 2, before allocator/driver overhead. It is released when the
curtain is inactive or the session-lock surface is destroyed. Overall shell PSS
fell in these runs, but fluctuated substantially; this is not proof of an equally
large private-heap reduction in every desktop state.

The ordinary 1 Hz graph CPU reduction is measurable; the 4 Hz CPU result is
essentially unchanged. Party render GPU fell, while its CPU remained high. Static
lock/curtain GPU work was already tiny; caching makes reuse explicit but does not
produce a meaningful whole-desktop GPU gain in those settled states. Video backdrop
blur remains the largest measured compositor cost. No wallpaper-only xray rule
was enabled, because it would change what is blurred over application windows.

## Pill animation correction

The supplied recording showed the pill shifting and scaling during rest, hover
and expanded transitions. Hyprland animates native layer position and size while
QML independently animates the child. Disabling compositor animation alone was
insufficient: the previous buffer can briefly be scaled into new native bounds
before Qt commits its resized buffer. A native pixel-marker test caught a
306-pixel horizontal jump with bounded width, and a 15.5-pixel vertical jump
with bounded height only.

`PillWindow.qml` now keeps a screen-sized native canvas and animates only the
QML child. Its masks still follow the interactive pill; expanded outside clicks,
keyboard focus, edge gestures and hidden-mode closing are preserved.
`Appearance.qml` applies `no_anim=true` only to the pill and restores runtime
rules on compositor reload. A managed Process records settings as applied only
after successful command completion; a reload invalidates in-flight generations.

With compositor animations enabled, all **72 rendered-marker samples** remained
at the expected center with **zero horizontal or vertical deviation** in the
isolated 1920×1200 fixture. Checks cover hover open/close, expanded open/close
and hover after reload. The test also verifies a successful rule application
after the reload event. Hyprland's layer query does not expose applied `no_anim`,
so that check verifies the event/command integration rather than introspecting
the effect. Screenshots use logical scale 1 to accommodate scaled outputs;
the native run itself used one scale-1 output.

Early short-startup trials varied substantially. The isolated compositor's
startup warning lasts 15 seconds and schedules redraws while visible, so the
final measurements wait **20 seconds before starting the shell trials**.
Two current trials and two controls using the original full-size native canvas
produced these values with the same video wallpaper and blur settings:

| Version / trial | Shell CPU % | Shell render GPU % | Hyprland CPU % | Hyprland render GPU % | Shell PSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline 1 | 101.11 | 0.788 | 36.83 | 19.80 | 271.3 |
| Baseline 2 | 78.86 | 0.868 | 28.42 | 23.31 | 239.6 |
| Corrected 1 | 103.89 | 0.736 | 38.36 | 17.85 | 236.1 |
| Corrected 2 | 104.57 | 0.806 | 37.43 | 19.56 | 243.7 |

Video-engine busy time was about 2.90% in all four trials, with decoded delivery
near 24 frames/s. The pill's native canvas was 1920×1200 in all four trials.
No project test suite ran alongside them. High CPU persisted in both the
baseline and corrected code; its cause has not been established. These short
nested-compositor measurements are **inconclusive for a causal performance gain
or CPU regression**. They do not support carrying forward the historical
bounded-window GPU reduction or the 99% area claim. The JSON retains final
measurements, baseline controls and earlier exploratory trials.

## Verification

- Final `./scripts/test.sh`: **337 Python tests passed; 342 QML tests passed,
  6 shader-dependent cases skipped by the software backend; qmllint passed**.
- Native Wayland/OpenGL: **35 QML cases passed with zero skips/failures**, including
  the shader cases. Cached output matches live blur within two channel values;
  partial graph painting matches a full repaint pixel for pixel.
- Native drawer/pill tests passed with compositor animations enabled: rendered
  pill centering, constant native canvas during UI-scale changes, initial
  expanded creation, hidden-mode closing,
  keyboard focus, notification/power/top-edge gestures, outside dismissal,
  ownership transfer and DPMS transitions. The fixture's lock handoff is harmless.
- The album shader bundle regenerated with `qsb --qt6 --qsbversion 64` matches
  the shipped bundle byte for byte. Final `git diff --check` passed.
- Independent read-only review covered the stable canvas, focus/input masks,
  closing hold, cache completion guards and Loader teardown.

The full suite initially required execution outside the filesystem sandbox
because its local DBus, Wayland and test HTTP sockets were blocked. The final
run with the required runtime access passed. These checks verify rendering and
input paths; they do not claim a production secure-lock/PAM handoff test.

The broader process/surface analysis, existing optimization list and C++
assessment remain in [performance-analysis-2026-11-13.md](performance-analysis-2026-11-13.md)
and [performance-components-2026-11-13.md](performance-components-2026-11-13.md).
These changes remove render passes and repeated work.
Rewriting orchestration in C++ would not remove Hyprland's blur pixels or video
frames. A native bulk-update scene-graph path is a reasonable future candidate
for the still costly Party visualizer; it needs its own profile and integration.
