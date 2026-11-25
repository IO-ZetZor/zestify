"""Exercise the circular picker and asynchronous palette/video preview lifecycle."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image, ImageDraw
from zesti.palette import PaletteSettings, SchemeMetadata, generate_palette, normalize_matugen

REPO = Path(__file__).resolve().parents[2]


class WallpaperStripTest(unittest.TestCase):
    def test_native_strip_and_preview_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="zestify-wallpaper-strip-") as directory:
            temporary = Path(directory)
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            config = temporary / "config/zestify"
            config.mkdir(parents=True)
            (config / "config.json").write_text(json.dumps({
                "theme": {"apply": False, "mode": "dark", "smartScheme": True},
                "bar": {"showTray": False},
            }))
            items = []
            for name, sky, ridge in (("slow #blue", "#639ebd", "#193647"),
                                     ("warm", "#eeac79", "#653e48"),
                                     ("gray", "#999999", "#333333")):
                path = temporary / f"{name}.png"
                image = Image.new("RGB", (640, 360), sky)
                draw = ImageDraw.Draw(image)
                draw.ellipse((430, 45, 510, 125), fill="#eeeeee" if name == "gray" else "#ffe1ac")
                draw.polygon([(0, 280), (140, 100), (290, 290), (430, 170), (640, 300), (640, 360), (0, 360)], fill=ridge)
                image.save(path)
                items.append({"path": str(path), "thumb": str(path), "name": path.name, "isVideo": False})
            live = temporary / "live.mp4"
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                            "testsrc=size=320x180:rate=30", "-t", "3", "-pix_fmt", "yuv420p",
                            "-movflags", "+faststart", str(live)], check=True, capture_output=True, timeout=10)
            items.append({"path": str(live), "thumb": items[0]["thumb"], "name": "Live.mp4", "isVideo": True})
            items += [dict(items[1], name="Warm again"), dict(items[2], name="Gray again")]
            expected = {}
            for name, item, mode in (("warm", items[1], "dark"), ("gray", items[2], "dark"), ("grayLight", items[2], "light")):
                payload = generate_palette(Path(item["path"]), PaletteSettings(mode=mode, smart_scheme=True))
                expected[name] = normalize_matugen(payload, mode, SchemeMetadata("preview", "hard", mode, payload["scheme"]["variant"], 0))["primary"]
            state = temporary / "state/zestify/wallpaper"
            state.mkdir(parents=True)
            saved = temporary / "saved.png"
            saved.write_bytes(Path(items[2]["path"]).read_bytes())
            items.append({"path": str(saved), "thumb": str(saved), "name": saved.name, "isVideo": False})
            (state / "path.txt").write_text(str(saved))
            before = (state / "path.txt").read_bytes()
            collection = temporary / "collection.json"
            collection.write_text(json.dumps(items))
            # Only palette printing reaches the CLI; all desktop actions stay isolated.
            command = temporary / "zesti-fixture"
            command.write_text("#!/usr/bin/env python3\n"
                "import json, os, subprocess, sys, time\n"
                "from pathlib import Path\n"
                f"collection = Path({str(collection)!r})\n"
                "if sys.argv[1:3] == ['wallpaper', 'list']:\n"
                "    print(collection.read_text())\n"
                "elif sys.argv[1:4] == ['wallpaper', 'effects', 'prepare']:\n"
                f"    print({json.dumps({'ok': True, 'kind': 'contagio', 'field': str(REPO / 'tests/fixtures/wallfx/colony-field.png'), 'line': str(REPO / 'tests/fixtures/wallfx/colony-line.png')})!r})\n"
                "elif sys.argv[1:3] == ['wallpaper', 'print']:\n"
                "    if Path(sys.argv[3]).name.startswith('slow'):\n"
                "        time.sleep(0.65)\n"
                f"    sys.exit(subprocess.call([{str(REPO / 'bin/zesti')!r}, *sys.argv[1:]]))\n"
                "elif sys.argv[1:3] == ['wallpaper', 'set']:\n"
                "    pointer = Path(os.environ['XDG_STATE_HOME']) / 'zestify/wallpaper/path.txt'\n"
                "    count_file = pointer.with_name('apply-count.txt')\n"
                "    count = int(count_file.read_text()) + 1 if count_file.exists() else 1\n"
                "    count_file.write_text(str(count))\n"
                "    time.sleep(0.45)\n"
                "    if count == 1:\n"
                "        print('Simulated apply failure', file=sys.stderr)\n"
                "        sys.exit(1)\n"
                "    pointer.with_name('before-apply.txt').write_bytes(pointer.read_bytes())\n"
                "    pointer.write_text(sys.argv[3])\n")
            command.chmod(0o755)
            # Replace only the Wayland window wrapper; preserve picker ownership,
            # focus, preview and close handling from the production component.
            shell = temporary / "shell"
            shell.mkdir()
            for name in ("singletons", "surfaces", "lib", "shaders"):
                (shell / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
            backgrounds = shell / "backgrounds"
            backgrounds.mkdir()
            for path in (REPO / "shell/backgrounds").iterdir():
                if path.name != "BackgroundWindow.qml":
                    (backgrounds / path.name).symlink_to(path)
            background = (REPO / "shell/backgrounds/BackgroundWindow.qml").read_text().replace("PanelWindow {", "Item {", 1)
            for line in ('    screen: targetScreen\n', '    color: "black"\n',
                         '    exclusionMode: ExclusionMode.Ignore\n', '    WlrLayershell.layer: WlrLayer.Bottom\n',
                         '    WlrLayershell.namespace: "zestify-background"\n'):
                background = background.replace(line, "", 1)
            background = background.replace('    anchors {\n        top: true\n        bottom: true\n        left: true\n        right: true\n    }', '')
            (backgrounds / "BackgroundWindow.qml").write_text(background)
            components = shell / "components"
            components.mkdir()
            for path in (REPO / "shell/components").iterdir():
                if path.name != "WallpaperPickerWindow.qml":
                    (components / path.name).symlink_to(path)
            source = (REPO / "shell/components/WallpaperPickerWindow.qml").read_text().replace("PanelWindow {", "Window {", 1)
            first = source.index("    WlrLayershell.keyboardFocus:")
            last = source.index("    Region { id: emptyMask", first)
            source = source[:first] + source[last:]
            for line in ('    screen: targetScreen\n', '    exclusionMode: ExclusionMode.Ignore\n',
                         '    exclusiveZone: 0\n', '    WlrLayershell.layer: WlrLayer.Overlay\n',
                         '    WlrLayershell.namespace: "zestify-wallpaper-picker"\n'):
                source = source.replace(line, "")
            source = source.replace('    color: "transparent"', '    width: targetScreen ? targetScreen.width : 800\n    height: 780\n    color: "transparent"')
            (components / "WallpaperPickerWindow.qml").write_text(source)
            harness = temporary / "wallpaper-strip.qml"
            harness.write_text((REPO / "tests/quickshell/wallpaper-strip.qml").read_text().replace("../../shell/", "shell/"))
            previews = Path(os.environ.get("WALLPAPER_STRIP_PREVIEW", str(temporary / "previews")))
            previews.mkdir(exist_ok=True)
            env = dict(os.environ)
            for name in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
                env.pop(name, None)
            env.update({"HOME": directory, "XDG_CONFIG_HOME": str(temporary / "config"),
                        "XDG_STATE_HOME": str(temporary / "state"), "XDG_CACHE_HOME": str(temporary / "cache"),
                        "XDG_RUNTIME_DIR": str(runtime), "XDG_DATA_HOME": str(temporary / "data"),
                        "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "rhi", "QSG_RHI_BACKEND": "opengl",
                        "ZESTI_BIN": str(command), "WALLPAPER_STRIP_PREVIEW": str(previews),
                        "WALLPAPER_COLLECTION": json.dumps(items), "WALLPAPER_EXPECTED": json.dumps(expected),
                        "WALLPAPER_COMMITTED": str(saved)})
            try:
                result = subprocess.run(["dbus-run-session", "qs", "--no-color", "-p", str(harness)],
                                        env=env, capture_output=True, text=True, timeout=25)
            except subprocess.TimeoutExpired as error:
                self.fail((error.stdout or b"").decode() + (error.stderr or b"").decode())
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("WALLPAPER STRIP PASS:", output)
            for error in ("WALLPAPER STRIP FAIL:", "TypeError", "ReferenceError", "Binding loop", "Cannot assign", "Unable to assign"):
                self.assertNotIn(error, output)
            self.assertEqual((state / "before-apply.txt").read_bytes(), before)
            self.assertEqual((state / "path.txt").read_text(), items[3]["path"])
            self.assertEqual((state / "apply-count.txt").read_text(), "2")
            self.assertFalse((temporary / "state/zestify/scheme.json").exists())
            for frame in ("hover", "entry", "strip", "warm", "gray", "light", "apply-fade", "apply-failure", "applied-transition"):
                self.assertTrue((previews / f"{frame}.png").is_file(), output)
            self.assertTrue((previews / "circles.png").is_file(), output)


if __name__ == "__main__":
    unittest.main()
