# Video wallpaper GPU measurements — 2026-11-13

Measured on the installed Intel integrated GPU (ADL GT2, PCI device `0x46a3`)
using the first eight seconds of the active 3840×2160, 30 FPS H.264 wallpaper.
The production `VideoWallpaper.qml` component rendered into an isolated
1920×1200, 60 Hz Hyprland output with native Intel OpenGL and hardware video
decoding. No wallpaper or user configuration was changed.

## Results

Each value is the median of three eight-second samples after two seconds of
warm-up. GPU render and CPU columns combine the wallpaper renderer and its
isolated compositor. Video decoding belongs to the wallpaper process.

| Setting | Decoded size | GPU render busy | GPU video busy | CPU, % of one core | Sampled RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| Previous 30 FPS | 1920×1200 | 8.00% | 4.84% | 10.62% | 454.4 MiB |
| Default 24 FPS | 1920×1200 | 7.35% | 4.36% | 8.62% | 454.8 MiB |
| 24 FPS, `1080p` | 1728×1080 | 6.88% | 3.49% | 8.37% | 445.9 MiB |
| 15 FPS, `720p` | 1152×720 | 4.42% | 0.99% | 5.25% | 411.3 MiB |
| Paused after first frame | 1920×1200 | 0.00% | 0.00% | 0.00% | 440.1 MiB |

Relative to the previous 30 FPS setting:

- Default 24 FPS: **9.9% less video-engine busy time**, **8.2% less render-engine busy time**, and **18.8% less CPU time**.
- 24 FPS at `1080p`: **27.9% less video-engine busy time**, **14.0% less render-engine busy time**.
- 15 FPS at `720p`: **79.6% less video-engine busy time**, **44.7% less render-engine busy time**, and **50.6% less CPU time**.

The measured delivered frame rates were approximately 30.10, 24.10, 24.10,
15.11, and 0 FPS respectively. IPC timing adds a small offset to these observations.

## Method and limits

Generated each proxy from the same source excerpt before sampling. The 30 FPS
case used the saved helper from before the GPU changes; the other cases used the
updated helper. The source was already 8-bit 4:2:0, so these results do not measure
the separate High 10 hardware-compatibility improvement.

Used an isolated nested Hyprland compositor, then disabled its parent Wayland
window and measured a headless output. Blur and compositor animations were off.
The native Qt renderer identified itself as `Mesa Intel(R) Graphics (ADL GT2)`;
nonzero DRM video-engine counters confirm hardware decoder activity.

Read cumulative per-process GPU engine nanoseconds from `/proc/PID/fdinfo`,
deduplicating duplicated descriptors by DRM device and client ID. Read CPU user
and system ticks from `/proc/PID/stat`, and resident memory from process status.
Ran settings in forward, reverse, then forward order. GPU clocks were not fixed
or sampled, and other GPU clients can influence scheduling and frequency.

Render readings varied more than decoder readings. Across the three samples,
the previous 30 FPS case ranged from **7.44–14.21% render busy**, while default
24 FPS ranged from **6.85–9.17%**. Video busy ranges were **4.81–4.96%** and
**4.23–4.58%** respectively. Treat the render improvement as a short-run median,
not a guaranteed percentage for every desktop state.

These are engine measurements attributable to the test renderer and compositor,
not whole-desktop GPU utilization. Render and video engines run independently;
their percentages must not be added. This test excludes physical display scanout,
the production compositor's blur configuration, other applications, multiple
monitors, and a prolonged thermal soak. RSS is sampled memory, not peak memory.

Software: Hyprland 0.56.2, Quickshell 0.3.1, Qt 6.12.0, Mesa 26.2.4, FFmpeg 9.0.2.

[Raw trials, ranges, per-process results, and metadata](wallpaper-gpu-measurements-2026-11-13.json)
are retained. The executed benchmark script and detailed logs are under
`/tmp/zestify-wallpaper-gpu-bench.py` and
`/tmp/zestify-wallpaper-gpu-measurements/` for this session.
