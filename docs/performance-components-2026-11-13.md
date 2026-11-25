# Zestify component resource catalogue — 2026-11-13

This section maps source work to CPU, GPU and RAM ownership in `/home/zetzor/zestify`. It records the current working tree, including existing uncommitted work. The catalogue is source analysis; it does not assign newly measured percentages to individual QML components. Live process and controlled surface measurements accompany it in [the full analysis](performance-analysis-2026-11-13.md). GPU ownership and stable label widths below include the final edits.

## Ownership and attribution

`shell/shell.qml:66` creates one `MonitorShell` for each attached screen. `shell/MonitorShell.qml:38` constructs the background, pill, focus window, notification popups, notification drawer, power drawer, lock curtain and party window on each screen. Stats, Players, Notifications, ShellState, Focus and configuration are shared singletons; adding screens does not create another Stats polling loop.

| Work | Process/resource owner | Attribution limit |
| --- | --- | --- |
| QML bindings, JavaScript, layouts, Canvas painting, image decode, Qt shaders and scene graph | Quickshell | A single PID combines many components. Per-component attribution requires controlled gates or tracing. |
| Qt MediaPlayer video decoding and decoded surfaces | Quickshell decoder threads / DRM client | Separate video-engine busy from render-engine busy. A native decoder does not imply zero CPU. |
| Wayland composition, shell backdrop blur and output presentation | Hyprland | Transparent shell damage can increase compositor work; it is not all charged to Quickshell. |
| Python telemetry and audio frame forwarding | `gpu-monitor.py`, `cava-monitor.py`, `logind-watch.py` | Group children with the requesting service, without charging their work again to the parent. |
| Audio FFT/input | Native `cava`, PipeWire / audio server | The Python cava wrapper forwards data; the FFT is already native. |
| Proxy creation and video frame extraction | Native ffmpeg / ffprobe, requested by Python | Transient cache-generation work, distinct from cached steady playback. |
| Desktop applications and their GPU processes | Browser, media player and other app process trees | They are outside the shell even when shell labels, lyrics or album art reflect their state. |

Report CPU as percent of one logical core for process totals. Sum PSS for process-group RAM where readable: summed RSS double-counts shared mappings. Intel graphics uses unified memory, so GPU allocation figures must not simply be added to system RAM. DRM engine percentages are independent and must not be added into a single percentage. The fallback GPU monitor labels its result “Visible clients” because other users' or restricted processes may be inaccessible.

## Pill and its ten expanded surfaces

The registry is `shell/components/Pill.qml:70`. All ten expanded surfaces use the Loader at `Pill.qml:408`: it is active only when `currentSurface !== null && surfaceHeight > 0`; clearing or changing the selected surface unloads the previous objects. ShellState supplies one expanded owner at a time. Component declarations do not themselves instantiate these surfaces.

| UI surface | Exact workload/activation gate | CPU, GPU and RAM work | References |
| --- | --- | --- | --- |
| Collapsed pill | PillWindow visible if `showRest || pill.expanded`; child pill invisible after its opacity reaches zero during fullscreen/party. | Small text/icons, event-driven workspace/title/service bindings, global CPU/RAM labels; per-screen retained QML objects and window buffers. Clock updates at the next minute boundary and runs only while visible. | `PillWindow.qml:24`; `Pill.qml:91`; `PillModules.qml:45`; `Clock.qml:25`; `Resources.qml:15` |
| Hover card and quick toggles | `!locked && !fullscreen && !partyOn && (hovered || pinned || expanded)`, and empty surface for the hover row; MediaCard active only for hover with no expanded surface. | MediaCard/QuickToggles objects remain constructed even outside hover. Active card adds rotating masked art, lyrics, position updates and an audio visualiser. Hidden art source and layer objects can remain retained; exact resident GPU texture lifetime needs measurement. | `Pill.qml:45,362,381`; `MediaCard.qml:25,47,176,194` |
| Launcher | Selected pill surface; calls `Apps.refresh()` on construction. Query changes filter the app array. | Transient shell/find/cat desktop scan, JS parse/filter work, virtualized ListView and small icon textures. Its 80 ms focus timer is one-shot. | `shell/surfaces/Launcher.qml:16,68,74,121`; `shell/singletons/Apps.qml:13,85` |
| Wallpaper Studio | Selected pill surface; calls Wallpapers refresh on construction and user refresh. | Virtualized GridView; cached asynchronous thumbnail/preview decode at twice displayed dimensions, mipmaps and textures. Missing video thumbs trigger bounded concurrent ffmpeg work in the Python CLI. Applying wallpaper triggers palette/state/theme work and possibly proxy creation. | `shell/surfaces/WallpaperStudio.qml:116,263,536`; `zesti/wallpaper.py:88,128` |
| System | Selected pill surface. Local refresh timer runs only when `sampling && visible`, every 3000 ms. | CPU/RAM/network and per-GPU Canvas charts, per-core and process meters, graph history bindings. A transient `ps` scans and sorts all processes; only six rows are retained. Global CPU/RAM/network Stats continues after closure; this surface subscribes/releases GPU collection with visibility/sampling and teardown. | `shell/surfaces/SystemSurface.qml:20,52,496,637`; `shell/components/UsageChart.qml:34,59` |
| Media | Selected pill surface. Lyrics active when `active && visible`; position timer runs when also player is playing, at 500 ms. | AlbumCover mask/layers/mipmaps and rotation; virtualized lyric list, controls, seek progress and metadata bindings. It does not instantiate VisualiserBars. | `shell/surfaces/MediaSurface.qml:29,31,95`; `shell/components/LyricsView.qml:41` |
| Audio | Selected pill surface; PipeWire model changes and explicit volume/device actions. | Native service tracking, JS node filters, sliders, fixed device Repeaters and virtualized stream ListView. No extra polling process. Global PwObjectTracker remains in the shell regardless of this surface. | `shell/surfaces/AudioSurface.qml:14,314,368`; `shell/shell.qml:22` |
| Calendar | Selected pill surface. Events FileView watches changes; clock updates each 60000 ms while instantiated. | Small month grid, JS date/event filtering, virtualized event list and file parsing. | `shell/surfaces/CalendarSurface.qml:22,170,262,302,322` |
| Network | Selected pill surface. Scanner enabled on construction/adapter change, released on destruction if this surface owns the scan. | Native network service and device work, JS sort/filter and virtualized rows. Connection spinner runs only while its glyph is visible. Borrowed pre-existing scans are preserved. | `shell/surfaces/NetworkSurface.qml:18,54,119,205,318` |
| Bluetooth | Selected pill surface. Discovery enabled on construction/adapter change, released on destruction if owned. | Native Bluetooth daemon/service work, JS sorting and virtualized device rows. Spinner runs during pairing/connection changes only. Borrowed discovery is preserved. | `shell/surfaces/BluetoothSurface.qml:16,38,104,219,316` |
| Battery | Selected pill surface; native UPower/power-profile events. | Small fixed set of labels/profile choices and short changing-fill animation. No surface-specific polling process. | `shell/surfaces/BatterySurface.qml:18,193,261` |
| Settings | Selected pill surface; bindings recalculate on configuration changes and edits publish configuration. | Nested Repeaters construct all sections/settings controls. RAM scales with settings, not a virtualized model; no recurring surface polling process. | `shell/surfaces/ConfigSurface.qml:79,387,417,446` |

Paths without a directory in the first two rows are under `shell/components/`.

The System surface's `ps -eo comm=,%cpu=,%mem=` at `SystemSurface.qml:647` reports **lifetime-average process CPU**, not interval CPU consumption. It must not be compared directly with the fresh `/proc/PID/stat` deltas from profiling. Its `%mem` is RSS relative to physical RAM, not PSS or private memory.

## Other windows and persistent UI objects

| Window/component | Exact gate and retained state | Work to attribute | References |
| --- | --- | --- | --- |
| Video wallpaper | One MediaPlayer per monitor. `shouldDecode` requires unlocked, DPMS on, acceptable battery, no configured power saver/obscuration/unfocused pause, and proxy ready or failed fallback. `sync()` deliberately allows initial-frame playback before pausing. | Continuous native decode, video surfaces, texture/render work and compositor presentation while playing. Paused player retains substantial RAM; pause is not unload. | `shell/backgrounds/BackgroundWindow.qml:43,189`; `VideoWallpaper.qml:23,53` |
| Static wallpaper | Source only for non-video path, asynchronous and cached; per-monitor Image remains constructed. | Full source decode/texture may exceed display dimensions because there is no `sourceSize` limit. Updates only on source/render changes, not a continuous timer. | `shell/backgrounds/WallpaperImage.qml:10` |
| Focus card/editor | Available only when enabled, not fullscreen, unlocked, DPMS on, and without competing surface/party/drawer on that screen. Card/editor objects stay constructed. | Native text/layout and short transitions. Shared FocusSession runs its 200 ms ticker only with status `running`; it continues when cards are hidden and uses elapsed wall time rather than callback counts. | `FocusWindow.qml:20,75`; `FocusSession.qml:15,118`; `shell/singletons/Focus.qml` |
| Notification popups | Window enabled only on active primary monitor; card Repeater model empty on other monitors. Visible with nonempty popup list. Expiration animation pauses on hover or invisibility. | Card text/icons/images, progress animation, popup rectangle composition and Hyprland blur. Maximum five live popups. | `shell/MonitorShell.qml:75`; `NotificationPopups.qml:26,57`; `NotificationCard.qml:195`; `Notifications.qml:19` |
| Notification drawer | Full-screen transparent PanelWindow stays mapped while unlocked; gesture enabled only with DPMS on. Active while dragging/opened/spring-running/pull > 0.1. Body stays constructed when inactive. | Active drawer painting and blur, full-screen scrim, virtualized notification history; 16 ms spring only while settling. History/model and potential item textures remain retained while closed. Input mask limits hit-testing, not the window's dimensions. | `NotificationDrawerWindow.qml:22,31,65`; `NotificationDrawer.qml:24,100,144`; `shell/surfaces/NotificationsSurface.qml:68` |
| Power drawer | Same mapped/DPMS/gesture pattern; body stays constructed. Actions enabled only after fully opened and not dragged/settling. | Active panel/scrim composition and blur, fixed action tiles, portrait GIF/shader, temporary hold timers. Hidden portrait clears its image source. | `PowerDrawerWindow.qml:22,65`; `PowerDrawer.qml:25,103,157`; `shell/surfaces/Power.qml:91`; `PowerAction.qml:132`; `PowerPortrait.qml:149` |
| Lock curtain | Full-screen transparent gesture window mapped while unlocked; enabled only while DPMS on. Active while dragging, requesting lock, positive pull or transition. | Clock at 1000 ms only while active; active wallpaper Loader and Qt blur; transient cached still extraction. Idle curtain does not instantiate wallpaper/effect. | `LockPullWindow.qml:22`; `LockPull.qml:28,108,130`; `LockWallpaper.qml:11` |
| Secure session lock | WlSessionLock-managed per-output surfaces for active lock. Global SessionLock keyboard sampling runs only while active. | Static extracted wallpaper with full-output Qt blur, one-second face clock, PAM only during authentication, repeated `hyprctl devices` every 500 ms while locked. | `SessionLock.qml:119,138,149`; `LockSurface.qml:32,76`; `LockAuth.qml` |
| Party | One global partyOwner. PartyWindow visible during active ownership, entry/exit animation or positive entry. PartyStage/scene objects exist even while inactive on every monitor. | Active capture/interpolation/motion, 208 edge bars, large rotating art, lyrics, transition particles and conditional motion shader. Inactive scenes can retain objects/image sources; physical resident allocations require measurement. | `PartyWindow.qml:22,29,76`; `PartyStage.qml:84`; `PartyScene.qml:266,290,355`; `ShellState.qml:17` |
| OSD | One primary-screen PanelWindow; visible only when showing and enabled. Timeout and 120 ms value transition are request-driven. | Small text/progress rectangle plus compositor blur. Retained objects when hidden; no repeating idle timer. | `Osd.qml:29,58,148` |
| Tray/menu | Per-screen tray visibility set by configuration/primary selection. Native menu requested on interaction. | Tray icon updates/textures and native menu render work. Icons use final-size source dimensions; menu anchor itself has no polling loop. | `Tray.qml:31,41`; `TrayMenu.qml`; `Pill.qml:340` |
| Polkit authentication | Persistent native agent; LazyLoader active only during incomplete auth request, unlocked and with a target screen. | Transient full-output translucent scrim/dialog, text input and service calls. Not included in configured backdrop-blur namespaces. | `PolkitAuth.qml:16,35` |
| Standalone login greeter | Separate optional native `zestify-greeter` application, fullscreen outside preview mode. Login window has a one-second clock while running. It is not a component in the Quickshell process. | Static gradient/text/controls and login-service events; no GIF, shader or repeating animation found in this QML. Do not add greeter resource assumptions to an already logged-in desktop. | `auth/qml/Login.qml:8,31`; `auth/greeter_main.cpp`; `auth/Makefile:13` |

Unqualified component paths in this table are under `shell/components/`; singleton names are under `shell/singletons/`.

Party gates merit care: capture runs while `active || entry > 0.05`; lyrics while `active && entry > 0.25`; lyric position ticks at 500 ms while visible/playing; motion ticks at 16 ms while `entry > 0.001 && !calm`. Audio impact additionally requires live audible playing output and entry > 0.65. Reduced motion disables party motion and art rotation, but **does not itself stop cava capture or ordinary visualiser interpolation**. See `PartyStage.qml:84,96,104`, `PartyScene.qml:114,266`, `MediaCard.qml:176` and `VisualiserLevels.qml:58,94`.

## Transparency, effects, charts and texture work

| Mechanism | Process and workload | Existing gate/limit | References |
| --- | --- | --- | --- |
| Translucent PillBody gradient | Quickshell paints alpha gradient; Hyprland composes underlying pixels. Parent PanelWindow can be much larger than painted pill. | Alpha is `theme.transparency * backgroundOpacity`; static fill does not imply continuous shell repaint. | `shell/components/PillBody.qml:8,23`; `PillWindow.qml:60` |
| Backdrop blur | Hyprland blur for pill, focus, notification popups/drawer, power drawer and OSD; special rule for lock curtain. Video damage behind these regions can increase composition cost. | Normal blur enabled when Config.theme.transparency < 1; curtain uses transparency × bar opacity. Relevant settings deduplicated and rules sent in one `hyprctl eval`. | `shell/singletons/Appearance.qml:15,24` |
| AlbumCover circular mask | Quickshell offscreen disc/mask layers, 4-sample mask layer, mipmapped artwork and MultiEffect mask. Per-instance texture resources can exceed the small visible art. | Default art decode/layer dimensions twice displayed size; party supplies fixed `artSize` to avoid repeated resize allocations. Spin pauses when not playing, inactive or hidden. Layers remain enabled. | `shell/components/AlbumCover.qml:18,52,63,87,98` |
| Party motion blur | Conditional full-output camera layer and shader with nine texture reads per fragment. | Layer disabled in calm mode or settled no-motion state; enabled through transitions. Edge bars are outside camera layer. | `PartyScene.qml:340,355`; `shell/shaders/party-motion.frag:19` |
| PowerPortrait | Full GIF decode, mipmapped texture, live ShaderEffectSource and circular portrait shader; 13 rim rectangles. | Source cleared when hidden; playing gated by visible and !calm; capture live only while visible. Texture dimension is width × max(4,devicePixelRatio), not merely displayed size. | `shell/components/PowerPortrait.qml:21,95,149,167,178` |
| Lock wallpaper blur | Quickshell MultiEffect blurMax 64 at full surface size; extracted static frame. | Curtain layer/Loader exists only while active; secure lock layer always enabled while lock surface exists. Static source may let Qt reuse layer contents; layer presence alone does not prove recomputation each frame. | `LockPull.qml:130`; `LockSurface.qml:36` |
| Usage graphs | Qt Canvas CPU painting/texture updates plus compositor presentation; bounded sample histories. | Paint requested on values/theme/size changes. Surface unloading removes chart instances; no chart-specific 60 Hz timer. Pointer inspection changes tooltip/line objects. | `shell/components/UsageChart.qml:34,59,124`; `Stats.qml:67` |
| Visualiser bars | JS smoothing/property updates and 32 ordinary / 208 party rectangle items. | 16 ms interpolation stops when settled; active-no-data fallback deliberately changes values every 100 ms. Hidden media card deactivates its stream. | `VisualiserBars.qml:16`; `VisualiserLevels.qml:54,70`; `EdgeVisualiser.qml:34`; `PartyScene.qml:290` |

Input masks are not render-size controls. Empty/edge masks on mapped full-screen gesture windows do not establish that window buffers are small. Conversely, large dimensions or enabled layers do not establish continuous GPU usage: damage, visibility, source changes and animations decide whether work happens. Controlled measurements should distinguish cold construction, active steady work, settled idle and retained memory after closure.

## Helper processes and service activity

| Process/service | Exact trigger / cadence | Relevant CPU or RAM work | References |
| --- | --- | --- | --- |
| Global Stats | Started idempotently from MonitorShell; timer runs whenever Stats.running, normally every 1000 ms. Not gated by System-surface visibility, lock or DPMS. | Reloads `/proc/stat`, meminfo, netdev and optional CPU temperature; creates bounded history copies. CPU/RAM labels need samples; GPU labels exist only in System. | `shell/MonitorShell.qml:19`; `shell/singletons/Stats.qml:46,58,67,236`; `Resources.qml:15` |
| `gpu-monitor.py` | One process while Stats.running, requested and at least one visible System consumer is registered; one outstanding sample at a time. Blocks on stdin between samples. | GPU enumeration/sysfs reads; on Intel/fallback drivers every requested sample scans all readable `/proc/PID/fdinfo` files and parses/deduplicates DRM clients. NVIDIA query only for active NVIDIA GPU; does not wake sleeping dGPU. | `Stats.qml:135,216`; `scripts/gpu-monitor.py:120,140,257,305` |
| `cava-monitor.py` and native `cava` | Every active VisualiserLevels **instance** starts its own pair. Default ordinary and party configuration are 60 Hz; party format uses 32 uint16 bins. | Native FFT/audio capture, Python frame handling/serialization, pipe wakeups, QML parsing and interpolation. One owner within an instance is not a global shared stream. SIGTERM unwinds/reaps child. | `VisualiserLevels.qml:90`; `scripts/cava-monitor.py:48,124,132`; `config/cava.conf:3` |
| `logind-watch.py` and `dbus-monitor` | One persistent global watcher; select timeout 0.5 s, 2-second restart only after exit. Checks lock-before-sleep setting between events. | Mostly blocked event loop plus periodic small config parse; D-Bus parsing. With lock-before-sleep enabled, also holds `systemd-inhibit` and a Python stdin waiter. | `Session.qml:193,240`; `scripts/logind-watch.py:47,123,139` |
| `zesti proxy ensure`, ffprobe, ffmpeg | Source/size/codec/CRF/FPS change or cache miss; one globally serialized proxy worker. | Native transcode CPU/RAM; cached probe avoids ffprobe. Generated proxies remove audio, cap FPS and dimensions; H.264 forces hardware-friendly 8-bit 4:2:0. | `Proxy.qml:22,47`; `BackgroundWindow.qml:69`; `scripts/wallpaper-proxy.py:80,107,130` |
| `zesti wallpaper list` | Wallpaper Studio construction/refresh or relevant directory changes. | Directory enumeration, JSON; missing video thumbnails generated with ThreadPoolExecutor max four. Cached frames avoid repeat extraction. | `Wallpapers.qml:128`; `zesti/wallpaper.py:88,128` |
| Wallpaper set/refresh and theme apply | Explicit change, palette settings change or startup/relevant theme settings change. Debounced 200 ms, serialized/busy gates. | Python palette work, full source decode then 128px thumbnail/scoring, file updates and native app reload helpers. Transient CPU/RAM peaks rather than idle services. | `Wallpapers.qml:69,151`; `shell/shell.qml:16,45,56`; `zesti/palette.py:251` |
| `lock.py --frame` → ffmpeg | Active lock wallpaper construction or source change; cached per-source still. | Transient frame extraction and JPEG decode; active source changes retried coherently. | `LockWallpaper.qml:11,25`; `scripts/lock.py:24` |
| `lock.py --status user` | One-shot shell startup/global session lock and each per-monitor lock curtain construction. | Small Python startup/user lookup; not a recurring idle process. | `SessionLock.qml:82`; `LockPullWindow.qml:54` |
| `hyprctl -j devices` | Every 500 ms only while session lock active, with no overlapping query. | Repeated process creation, compositor IPC and JSON parse for keymap/caps lock. | `SessionLock.qml:138,149` |
| System `ps` | Every 3 seconds while visible, plus construction/sort changes. | Whole process-list scan/sort, JSON-like JS parsing; reports lifetime CPU average and RSS percentage. | `shell/surfaces/SystemSurface.qml:62,645` |
| CPU temp finder | One-shot shell startup. | `sh`/`cat` find coretemp path; periodic temp reads afterward happen in Stats. | `Stats.qml:207` |
| `speed-test.py` | Explicit start; singleton continues until finish/cancel even if surface unloads. | One reused HTTPS/TLS connection, streaming 64 KiB reads, ramped bounded traffic; upload allocates at most 16 MiB payload. Python deadline 45 s, shell fallback 60 s. No GPU computation of its own. | `SpeedTest.qml:27,73,88`; `scripts/speed-test.py:18,34,84` |
| Native PipeWire/MPRIS/network/Bluetooth/UPower/notification/Polkit/PAM services | Event models and explicit UI actions; global PipeWire object tracker tracks all nodes. | External daemon work and Quickshell native binding updates. Shell service imports do not mean each UI owns another native daemon. | `shell/shell.qml:22`; `shell/singletons/Players.qml`; surface service imports |
| Session idle/battery monitoring | Native IdleMonitor for configured lock/DPMS/sleep thresholds; battery safety check every 30 seconds. | Native idle events and small QML checks; occasional notify-send/systemctl/lock actions. | `shell/singletons/Session.qml:164,199` |
| Explicit capture commands | Screenshot on request; native `gpu-screen-recorder` remains running after an explicit record start until stop. | Screenshot/region selection uses grim or configured freeze backend and slurp, with binary wl-copy publication. Recording is separate native capture/encode GPU/CPU work, at monitor refresh rate or 60 FPS for region capture. | `zesti/capture.py:129,170,270`; `hypr/zestify.lua:25` |
| Explicit clipboard/emoji/desktop commands | User command or binding; no always-on watcher installed by the shown Hyprland binding file. | Native cliphist/fuzzel/wl-copy and compositor IPC; any lingering clipboard-owner process belongs to the action, not a shell polling loop. | `zesti/desktop.py:45,93`; `hypr/zestify.lua:16` |
| Compatibility/migration launchers | Legacy wallpaper entry point or explicit migration/install/update command. | Delegate to the zesti package; they do not implement another resident wallpaper engine. | `scripts/wallpaper-backend.py:16`; `scripts/migrate-state.py` |
| Optional standalone display manager | Separate `zestify-dm` native daemon, PAM worker/session children and greeter if the optional service is installed/enabled. | Process supervision, logind/PAM and protocol I/O; no direct recurring desktop GPU renderer in the supervisor. Prior review did not install or enable this service. | `auth/daemon.cpp:140,213,306`; `auth/Makefile:13`; `docs/code-review-2026-11-13.md:94` |

Unqualified QML paths in this section are components or singletons as named above. Capture/clipboard/desktop CLI commands are explicit user-action work, not periodic desktop services.

## Optimizations already present

These are implemented methods, distinct from the proposals below. “Source verified” describes the actual mechanism; existing report benchmarks apply only to their recorded workloads.

| Implemented method | Mechanism and evidence |
| --- | --- |
| Lazy palette dependencies | Unrelated CLI commands avoid importing palette scheme machinery; prior fresh-CLI benchmark improved 102.88 → 82.81 ms. `zesti/palette.py:129,179,199`; `docs/code-review-2026-11-13.md:46,59`. |
| Resize before RGB allocation | Shrinks source first, preserving nearest-neighbour thumbnail samples; prior 8K-JPEG benchmark 252.09 → 210.81 ms, peak RSS 283656 → 183016 KiB. `zesti/palette.py:279`; report lines 47–48. |
| Deduplicated app scan | Honors configured XDG paths, suppresses repeated dirs, includes symlinks; prior scan 149.30 → 107.95 ms. `Apps.qml:13`; report line 49. |
| Cached source FPS probe | Key includes resolved path, source metadata; warm cache avoids ffprobe. Prior ensure helper 32.245 → 0.05594 ms, excluding Python startup. `scripts/wallpaper-proxy.py:80`; report line 50. |
| Proxy caching / serialized creation | Reuses source/settings-matching proxy, one worker, bounded retries after failure. Source/settings changes invalidate matching state. `Proxy.qml:22`; `BackgroundWindow.qml:69,164`. |
| Lower configurable video frame rate | Default max24 instead of30, preserves lower-rate sources; optional 15 FPS. Actual decoder work reduced in controlled measurements below. `scripts/wallpaper-proxy.py:107`; `Config.qml:126`. |
| Resolution and decoder-compatible format | Monitor/1080p/720p even-sized no-upscale presets; H.264 `yuv420p`; audio removed; original pauses while proxy pending after first frame. `BackgroundWindow.qml:43,78`; `scripts/wallpaper-proxy.py:130`; `VideoWallpaper.qml:53`. |
| Wallpaper pause policy | Lock/DPMS, configured obscuration/unfocused/battery/power-profile gates stop continuous playback after first frame. `BackgroundWindow.qml:43`. |
| Unloaded closed expanded surfaces | Conditional Loader, single ShellState surface owner; network/Bluetooth ownership-aware cleanup. `Pill.qml:408`; surface cleanup functions. |
| Virtualized lists/grids | App, wallpaper, notification history, lyrics, event, network, Bluetooth and stream models use ListView/GridView. Settings intentionally use Repeaters. |
| Bounded histories/caches | Configured Stats graph capacity; 100 notifications, five popups, 32 lyric cache entries. `Stats.qml:34,67`; `Notifications.qml:19`; `shell/lib/lyrics.js:7`. |
| Event-based small services | Native workspace/title/device/MPRIS/PipeWire/UPower model updates; file watches for state/config/schemes. Stats and special position/keyboard cases still poll. |
| Quiescent visualiser interpolation | 16 ms timer stops when settled, restarts on changed input; Monstercat smoothing is two linear passes rather than all-pairs work. `VisualiserLevels.qml:32,54`; `shell/lib/visualiser.js:70`. |
| Visibility-gated media updates | Hidden hover stops lyrics requests, position updates, art rotation and its capture process. `MediaCard.qml:25,47,194`; `Pill.qml:390`. |
| Hidden portrait source release | Stops GIF playback and clears source; effect source no longer live. `PowerPortrait.qml:149,167`. |
| Idle curtain unloading | Wallpaper Loader/effect inactive while curtain idle. `LockPull.qml:130`. |
| Minute-boundary visible clock | Updates exactly at next minute boundary, pauses hidden. `Clock.qml:25`. |
| Bounded Stats cadence / pending work | Poll clamped 250–60000 ms; Stats starts once; one pending GPU request; restart backoff. `Config.qml:134`; `Stats.qml:46,135,230`. |
| Batched deduplicated blur rules | Single hyprctl invocation only for changed relevant settings. `Appearance.qml:24`. |
| Conditional party effects | Single global party owner, calm gate, stopped inactive motion/capture, motion layer disabled when settled, fixed album-art texture size during geometry changes. `ShellState.qml:17`; `PartyStage.qml:84`; `PartyScene.qml:355,395`. |
| Smaller/async cached image work | Size limits for art/thumb/tray/notification pictures, asynchronous image loading and source caching. Mipmaps improve scaled quality but themselves add allocations/work. `AlbumCover.qml:81`; `WallpaperStudio.qml:116`; `Tray.qml:48`; `NotificationCard.qml:168`. |
| Native final-size text | NativeTextRendering pragma for small labels/icons rather than distance fields. `shell/shell.qml:1`. |
| Debounced transient work | Theme/palette changes debounce 200 ms and avoid overlap; lyrics debounce 350 ms, cancel stale work and use a 10 s deadline. `shell/shell.qml:45`; `Wallpapers.qml:69`; `LyricsProvider.qml:32,92`. |
| Bounded parallel thumbnail creation | At most four independent video-thumbnail workers; cached extracted frames reused. `zesti/wallpaper.py:128`. |
| Reused TLS / streaming speed test | One TLS connection; 64 KiB download buffers, bounded transfer ladder and deadlines. `scripts/speed-test.py:24,59,84`. |
| Native protocol syscall/buffer optimization | Chunked delimiter-aware socket reads and fewer encoder copies; prior 1000-message benchmark 782.618 → 4.770 ms. This was optimization within C++, not a language rewrite. `auth/protocol.cpp`; report lines 51–63. |

Three additional methods were implemented during the full analysis:

| Method | Mechanism and scope |
| --- | --- |
| Consumer-owned GPU telemetry | Visible/sampling System surfaces register with Stats; last release stops the helper and clears history. CPU/RAM/network sampling continues. Lock/DPMS disable the System consumer; re-opening starts fresh history. |
| Stable resource label geometry | TextMetrics reserves CPU and total-RAM digit widths at the actual font/scale. Values no longer resize/animate the painted pill or mask. Deterministic native width-change/GPU measurements are in the full report. |
| Running-only expiry pause | Notification cards pause only a running expiry animation; repeated stopped-animation warnings disappear while hover/visibility semantics remain verified. |

Ownership-aware Wi-Fi/Bluetooth teardown and empty secondary popup models also remove redundant scans/card work. Atomic frame/image publication, serialized wallpaper writes and disk-backed rollback were correctness fixes with no standalone numerical speedup claim.

## Prior measurements and their limits

The controlled wallpaper report used the first eight seconds of the active 3840×2160, 30 FPS H.264 source and the production video component on an isolated 1920×1200 60 Hz native Intel output. Figures are medians of three eight-second samples after two-second warmup. Render and CPU combine the renderer and isolated compositor; video belongs to the renderer.

| Workload | Render engine | Video engine | CPU, % of one core | Sampled combined RSS |
| --- | ---: | ---: | ---: | ---: |
| Previous 30 FPS, 1920×1200 | 8.00% | 4.84% | 10.62% | 454.4 MiB |
| Default 24 FPS, 1920×1200 | 7.35% | 4.36% | 8.62% | 454.8 MiB |
| 24 FPS, 1728×1080 | 6.88% | 3.49% | 8.37% | 445.9 MiB |
| 15 FPS, 1152×720 | 4.42% | 0.99% | 5.25% | 411.3 MiB |
| Paused after first frame | 0.00% | 0.00% | 0.00% | 440.1 MiB |

Default 24 vs previous 30 measured 9.9% less video-engine busy, 8.2% less render-engine busy and 18.8% less CPU. Pause eliminated measured steady GPU/CPU work in that isolated workload while retaining memory. RSS includes shared pages and is not PSS, private or peak RAM. The test disabled compositor blur and excludes production desktop apps, physical scanout, multiple displays and long thermal soak. Render variability was larger than decoder variability; no universal improvement percentage is established. Source: `docs/wallpaper-gpu-measurements-2026-11-13.md:11,32` and its JSON/raw artifacts.

The CLI/image/scan/proxy/native socket timings in the optimization table come from `docs/code-review-2026-11-13.md:40`. They cannot be extrapolated to whole-desktop CPU/GPU reductions. There is **no Python-to-C++ A/B measurement** in either existing report.

## Proposed optimizations to rank with current measurements

| Candidate | Expected resource and scope | Why source supports investigation | Verification/tradeoff |
| --- | --- | --- | --- |
| Further GPU parser/discovery optimization | CPU/syscalls while System is open | The idle scan was removed by consumer-owned collection; visible Intel fallback still scans readable fdinfo. | Profile remaining parser/syscall cost before a native rewrite; preserve permissions, counter semantics and discovery/hotplug. |
| Share visualiser capture by consumers | CPU/RAM/audio IPC on multiple visible consumers/displays | Each active VisualiserLevels owns its own Python+cava; comment's sharing is only within that instance. | Compare one/two consumers; preserve ordinary/party format and timestamps, subscribe/unsubscribe behavior and child cleanup. |
| Unload inactive heavyweight bodies | Retained QML/item/texture RAM, construction CPU | Hover MediaCard, PartyStage and drawer bodies stay instantiated on each display. | Compare PSS before first use, active and after closure; keep gesture windows, closing animations and ownership intact. Expect cold-open latency tradeoff. |
| Limit party shader area/resolution/samples | Active party GPU bandwidth/offscreen buffer RAM | Full-output camera layer samples nine times per pixel while effect enabled. | Compare full native GPU workload, motion quality and frame time. C++ function conversion does not reduce these texture reads. |
| Right-size portrait/album/static image resources | Active GPU/RAM and cold decode peaks | GIF full decode, 4× minimum portrait capture; AlbumCover enabled layers with 2× art; static wallpaper/lock image have no source-size cap. | Compare scaled/high-DPI quality, layer/cache PSS and native render time. Do not repeatedly change decoder size during geometry animation. |
| Stop decorative no-data activity / add explicit low-power gates | Silent-hover or party CPU/GPU | Visualiser fallback deliberately synthesizes input every 100 ms; calm mode leaves capture/interpolation active. | Preserve missing-data UX as a deliberate choice; measure paused/silent/audio-live separately rather than counting silence as settled. |
| Replace lock keyboard process polling with events | Locked-desktop CPU/process churn | `hyprctl devices` every 500 ms. | Preserve caps-lock/layout changes and fallbacks; verify native lock/security behavior in isolated environment. |
| Align focus display updates to seconds | Small ongoing QML CPU/repaint reduction | 200 ms ticker changes progress/bindings while displayed time is second-granular. | Keep elapsed/deadline based on wall time and timely finish notifications; verify hidden, pause/resume and suspend semantics. |
| Cache launcher discovery across quick opens | Open-time CPU/process creation | Every Launcher construction invokes full desktop scan. | Monitor directory/content changes and preserve XDG precedence; memory/cache invalidation cost may exceed benefit on small app sets. |
| Replace Canvas/large bar object sets only if hot | Visible System/party QML CPU/texture uploads | Canvas paints histories; 208 bars update per-frame item properties. | Native scene-graph geometry can help if profiling attributes significant time here. 1 Hz bounded graphs are not automatically a high-priority rewrite. |

## C++ recommendation grounded in measured work

Keep UI declaration/control flow in QML unless profiling identifies hot JavaScript or excessive item/binding updates. Qt Quick/Qt Multimedia, Hyprland, ffmpeg, cava and much of the service plumbing are already compiled native code. Moving their orchestration to C++ will not automatically reduce decoder work, compositor blur, full-output shader reads or image allocations.

| Boundary | Native-code assessment |
| --- | --- |
| GPU telemetry | Most plausible persistent CPU candidate if live profiles confirm the scan/parsing cost. First reduce scan cadence/discovery scope safely. C++ can reduce Path/string/regex/allocation overhead, but cannot remove `/proc` enumeration syscalls by itself. Keep permission limits, DRM-client deduplication and engine counter semantics. |
| Shared audio bridge | Plausible when several consumers duplicate capture or Python/QML serialization is measured hot. Native binary framing could remove interpreter/JSON overhead and integrate existing native cava/cavacore. The FFT is already native; preserve acquisition timestamps and lifetime/cleanup. |
| Party/large graph render item | A QQuickItem/QSG geometry path can reduce hundreds of QML properties/objects or Canvas texture uploads if they are measured hot. GPU optimization still requires fewer pixels/passes/samples; replacing JS math alone is insufficient. |
| Logind watcher/inhibitor | Native D-Bus/inhibitor FD integration can eliminate watcher/monitor/waiter process duplication and lower PSS. This is primarily a memory/process-count opportunity unless current measurements show CPU. Preserve secure-lock-before-sleep acknowledgement and cleanup. |
| ffmpeg/proxy/thumbnail orchestration | Low priority for wholesale rewrite: codecs/FFT/image kernels already native, and cached ensure work is 0.05594 ms excluding startup in prior tests. Optimize imports/cache/full-image allocations before introducing another native build target. |
| Settings, calendar, battery, notification/card controls | Small event-driven or unloaded work. No existing timing evidence supports rewriting these surfaces into C++. |
| Auth protocol | Existing C++17 implementation already shows the strongest measured syscall fix: 782.618 → 4.770 ms for 1000 socket messages. It demonstrates fixing access patterns/buffers, not that another process would gain the same factor from C++. |

The current native build is standalone userspace authentication via `auth/Makefile:5` (`-O2 -g`, C++17) and its daemon/greeter targets. There is no shell extension target in the current repository; a new QML/native helper integration would need build/install, ownership, shutdown and regression coverage. There is no kernel task or target kernel tree involved in these recommendations.

## Verification entry points and unresolved measurements

Repository-defined checks: `./scripts/test.sh` runs Python unittest discovery, offscreen QML tests and qmllint; `make -C auth -j2 test` builds/tests native auth. Focused tests include `tests/python/test_gpu_monitor.py`, `test_cava_monitor.py`, `test_system_surface.py`, `test_video_wallpaper.py` and the corresponding QML suites for usage/visualiser/party/album/portrait/lock/drawers. Existing runtime runners are documented at `README.md:344`: media, party UI/audio/latency, battery, drawer pointer tests and a nested session-lock/PAM harness. These commands were read, not newly run by this catalogue helper.

The full analysis records active/closed PSS, helper CPU and per-engine GPU/blur comparisons. Remaining attribution needs include exact heap ownership, frame-time/latency, cold vs warm opening, silence vs real live audio, physical display scanout and multiple-monitor behavior. Process RSS or a component's visible dimensions are not sufficient evidence for private RAM or individual GPU attribution. Preserve actual production configuration and user changes when assembling controlled workloads.
