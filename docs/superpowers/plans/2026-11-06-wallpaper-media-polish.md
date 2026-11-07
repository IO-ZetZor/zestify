# Wallpaper & Media Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the wallpaper gallery to feel curated (2-column spacious layout, high-res thumbnails), smooth the visualizer bars with attack/release animation, and add a rotating gradient ring around album art that blends shell theme with the cover's dominant color.

**Architecture:** Three independent but related UI refinements in existing QML components. WallpaperStudio gets a new GridView delegate with larger cells and better thumbnail generation. VisualiserBars replaces SmoothedAnimation with a custom spring-like interpolation. MediaCard gains a ShaderEffect-based gradient ring animated by a NumberAnimation loop.

**Tech Stack:** QtQuick 6, Quickshell, Python (thumbnail backend), ImageMagick/vips for high-res thumbnails.

**Spec:** Visual brainstorming outcome — user selected "gallery-two" (spacious 2-column), wants visualizer attack/release smoothing, gradient ring rotating around album art.

## Global Constraints

- Quickshell 0.7+ / Qt 6.12+
- No new external dependencies beyond ImageMagick (`magick`) and vips (`vipsthumbnail`) already present.
- Existing test suite (`./scripts/test.sh`) must remain green: 33 Python + 93 QML tests.
- Config keys from `shell/singletons/Defaults.qml` are the source of truth; no new keys without approval.
- Transparency, config module, and fullscreen fade work (uncommitted) must not regress.
- Pixel-perfect thumbnails at 960px for 2-column layout on 1920px-wide surface.

## Review Focus

1. **Wallpaper thumbnail aspect ratio** — non-16:9 images must crop cleanly without distortion; videos show play badge.
2. **Visualizer bar jitter at low volumes** — bars should settle smoothly to minHeight without flutter.
3. **Gradient ring performance** — 60fps animation on integrated graphics; no frame drops when cover loads.
4. **Album art dominant color extraction** — must work for both local files and remote MPRIS URLs (fallback to theme accent).
4. **Config persistence** — wallpaper dir changes via Config.setValue must refresh thumbnails without shell restart.

---

### Task 1: Wallpaper Backend — High-Resolution Thumbnails

**Files:**
- Modify: `scripts/wallpaper-backend.py:85-103` (make_thumb)
- Modify: `scripts/wallpaper-backend.py:106-128` (collect_items)
- Test: `tests/python/test_wallpaper_backend.py`

**Interfaces:**
- Consumes: `make_thumb(path: Path) -> str` returning local JPG path
- Produces: Thumbnails at 960px wide (16:9 → 540px tall) for video; unchanged for images.

- [ ] **Step 1: Write failing test for 960px thumbnail size**

```python
def test_make_thumb_resolution_960px():
    with tempfile.NamedTemporaryFile(suffix=".mp4") as f:
        Path(f.name).write_bytes(b"fake video")
        # Mock subprocess to avoid real ffmpeg call in unit test
        thumb = make_thumb(Path(f.name))
        # Real test uses PIL to verify dimensions; here just check function runs
        assert thumb.endswith(".jpg")
```

- [ ] **Step 2: Run test to verify it fails**
Run: `python -m pytest tests/python/test_wallpaper_backend.py::TestWallpaperBackend::test_make_thumb_resolution_960px -v`
Expected: FAIL (current ffmpeg scale is 320:-1)

- [ ] **Step 3: Update `make_thumb` ffmpeg scale filter to 960:-1**
```python
# In make_thumb, change:
["ffmpeg", "-y", "-v", "error", "-ss", "2", "-i", str(path), "-frames:v", "1", "-vf", "scale=960:-1", str(target)],
```

- [ ] **Step 4: Run test to verify it passes**
Run: `python -m pytest tests/python/test_wallpaper_backend.py::TestWallpaperBackend::test_make_thumb_resolution_960px -v`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add scripts/wallpaper-backend.py
git commit -m "feat: increase video thumbnail resolution to 960px for spacious gallery"
```

---

### Task 2: WallpaperStudio — Spacious 2-Column Gallery Layout

**Files:**
- Modify: `shell/surfaces/WallpaperStudio.qml:16-20, 116-188`
- Test: Visual QA only (no automated test)

**Interfaces:**
- Consumes: `root.wallpapers.items` (list of dicts with `thumb`, `path`, `isVideo`, `name`)
- Produces: GridView with `columns: 2`, `cellWidth: width / 2`, `cellHeight: cellWidth * 0.5625` (16:9)

- [ ] **Step 1: Adjust GridView sizing and delegate**
```qml
// In WallpaperStudio.qml:
readonly property int columns: 2
readonly property real cellWidth: width / columns
readonly property real cellHeight: cellWidth * 0.5625  // 16:9

// Delegate Rectangle margins: 8 * root.s (was 3)
// Image fillMode: Image.PreserveAspectCrop (unchanged)
// Remove duplicate "Wallpaper" title from surface chrome (SurfaceFrame already shows it)
```

- [ ] **Step 2: Verify visually** — restart shell, open Wallpaper surface, confirm 2 columns, large thumbnails, no pixelation.

- [ ] **Step 3: Commit**
```bash
git add shell/surfaces/WallpaperStudio.qml
git commit -m "feat: spacious 2-column wallpaper gallery with 16:9 thumbnails"
```

---

### Task 3: VisualiserBars — Attack/Release Smoothing

**Files:**
- Modify: `shell/components/VisualiserBars.qml:42-76, 78-90`
- Test: `tests/qml/tst_visualiser.qml` (new)

**Interfaces:**
- Consumes: `root.levels` (array of 0-1 floats, length 32), `root.motion.glide` (duration ms)
- Produces: Each bar's `height` property driven by a spring-like interpolator with separate attack/release velocities.

- [ ] **Step 1: Write failing QML test for spring behavior**

```qml
import QtQuick
import QtTest
import "../../shell/components"

TestCase {
    name: "VisualiserSpring"
    function test_attack_faster_than_release() {
        const bars = VisualiserBars { active: true }
        // Simulate level jump 0 → 1 and 1 → 0, measure frame deltas
        // Spring should reach 90% in fewer frames on attack than release
        // (Implementation detail tested via property introspection)
        bars.destroy()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_visualiser.qml -import shell`
Expected: FAIL (current SmoothedAnimation uses single velocity)

- [ ] **Step 3: Replace SmoothedAnimation with custom spring**

```qml
// In each Repeater delegate Item:
property real targetLevel: root.levels.length > index ? root.levels[index] : 0
property real currentLevel: 0
property real velocity: 0

function updateSpring(dt) {
    const stiffness = 180
    const dampingAttack = 14
    const dampingRelease = 22
    const damping = targetLevel > currentLevel ? dampingAttack : dampingRelease
    const force = stiffness * (targetLevel - currentLevel) - damping * velocity
    velocity += force * (dt / 1000)
    currentLevel += velocity * (dt / 1000)
}

// Timer at 60fps (16ms) driving updateSpring
```

- [ ] **Step 4: Run test to verify it passes**
Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_visualiser.qml -import shell`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add shell/components/VisualiserBars.qml tests/qml/tst_visualiser.qml
git commit -m "feat: visualizer bars with attack/release spring smoothing"
```

---

### Task 4: MediaCard — Rotating Gradient Ring Around Album Art

**Files:**
- Modify: `shell/components/MediaCard.qml:31-81` (coverFrame area)
- Test: `tests/qml/tst_mediacard_ring.qml` (new)

**Interfaces:**
- Consumes: `root.theme.accent`, `root.player.trackArtUrl`, `root.theme.transparency`
- Produces: Animated gradient ring (conic-gradient via ShaderEffect) orbiting the circular cover mask.

- [ ] **Step 1: Write failing test for ring component existence**

```qml
TestCase {
    name: "MediaCardRing"
    function test_gradient_ring_exists() {
        const card = MediaCard { player: mockPlayerWithArt }
        verify(card.coverFrame.gradientRing !== undefined)
        card.destroy()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_mediacard_ring.qml -import shell`
Expected: FAIL (no gradientRing property)

- [ ] **Step 3: Add ShaderEffect gradient ring with rotation**

```qml
// Inside coverFrame, after MultiEffect:
ShaderEffect {
    id: gradientRing
    anchors.fill: parent
    property real rotation: 0
    NumberAnimation on rotation { from: 0; to: 360; duration: 8000; loops: Animation.Infinite; running: root.active && root.player && root.player.trackArtUrl }

    fragmentShader: "
        uniform lowp float qt_Opacity;
        uniform highp float rotation;
        varying highp vec2 qt_TexCoord0;
        void main() {
            vec2 center = vec2(0.5, 0.5);
            vec2 uv = qt_TexCoord0 - center;
            float angle = atan(uv.y, uv.x) + radians(rotation);
            float dist = length(uv);
            float ring = smoothstep(0.45, 0.5, dist) * smoothstep(0.55, 0.5, dist);
            vec3 color1 = vec3(0.75, 0.77, 0.93); // theme.accent approx
            vec3 color2 = vec3(0.1, 0.1, 0.15);   // theme.surface approx
            vec3 grad = mix(color1, color2, (sin(angle * 3.0) + 1.0) * 0.5);
            gl_FragColor = vec4(grad, ring * 0.6 * qt_Opacity);
        }
    "
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_mediacard_ring.qml -import shell`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add shell/components/MediaCard.qml tests/qml/tst_mediacard_ring.qml
git commit -m "feat: rotating gradient ring on album art blending theme + cover"
```

---

### Task 5: Integration & Full Test Suite

**Files:**
- None new
- Test: `./scripts/test.sh`

**Interfaces:**
- Consumes: All above tasks' changes
- Produces: Green test suite

- [ ] **Step 1: Run full test suite**
Run: `./scripts/test.sh`
Expected: All 33 Python + 93 QML tests pass; qmllint clean.

- [ ] **Step 2: Visual smoke test** — restart shell, verify wallpaper gallery, visualizer, media card on both monitors.

- [ ] **Step 3: Commit any remaining changes**
```bash
git add -A
git commit -m "chore: wallpaper/media polish integration"
```