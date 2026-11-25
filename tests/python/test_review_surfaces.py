"""Offscreen regressions for expensive shell work and monitor state changes."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image


REPO = Path(__file__).resolve().parents[2]


def stage_shell(temporary: Path) -> None:
    """Mock only PanelWindow's platform wrapper; retain production proxy logic."""
    shell = temporary / "shell"
    shell.mkdir()
    for name in ("components", "surfaces", "singletons", "lib", "shaders"):
        (shell / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
    backgrounds = shell / "backgrounds"
    backgrounds.mkdir()
    (backgrounds / "WallpaperImage.qml").symlink_to(REPO / "shell/backgrounds/WallpaperImage.qml")
    for name in ("WallpaperTransition.qml", "WallpaperPreviewFrame.qml"):
        (backgrounds / name).symlink_to(REPO / "shell/backgrounds" / name)
    source = (REPO / "shell/backgrounds/BackgroundWindow.qml").read_text()
    source = source.replace("PanelWindow {", "Item {", 1)
    for line in ("    screen: targetScreen\n", "    color: \"black\"\n",
                 "    exclusionMode: ExclusionMode.Ignore\n",
                 "    WlrLayershell.layer: WlrLayer.Bottom\n",
                 "    WlrLayershell.namespace: \"zestify-background\"\n"):
        source = source.replace(line, "", 1)
    source = source.replace("    anchors {\n        top: true\n        bottom: true\n        left: true\n        right: true\n    }",
                            "    width: targetScreen ? targetScreen.width : 0\n"
                            "    height: targetScreen ? targetScreen.height : 0", 1)
    (backgrounds / "BackgroundWindow.qml").write_text(source)
    (backgrounds / "VideoWallpaper.qml").write_text("import QtQuick\nItem {\n"
        " property string source: ''\n property bool playing: false\n"
        " property bool shouldDecode: false\n property bool muted: true\n"
        " property bool hasFirstFrame: true\n property bool failed: false\n}\n")


class ReviewSurfacesTest(unittest.TestCase):
    def test_offscreen_adapter_proxy_image_and_visualiser_regressions(self):
        with tempfile.TemporaryDirectory(prefix="zestify-review-surfaces-") as directory:
            temporary = Path(directory)
            config = temporary / "config/zestify"
            config.mkdir(parents=True)
            (config / "config.json").write_text(json.dumps({"theme": {"apply": False}}))
            runtime = temporary / "runtime"
            runtime.mkdir(mode=0o700)
            wallpaper = temporary / "wall paper #question?100%.png"
            Image.new("RGB", (64, 64), "#447788").save(wallpaper)
            stage_shell(temporary)
            harness = temporary / "review.qml"
            harness.write_text((REPO / "tests/quickshell/review-regressions.qml").read_text()
                               .replace("../../shell/", "shell/"))
            env = dict(os.environ)
            for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
                env.pop(name, None)
            env.update({
                "HOME": directory,
                "XDG_CONFIG_HOME": str(temporary / "config"),
                "XDG_STATE_HOME": str(temporary / "state"),
                "XDG_CACHE_HOME": str(temporary / "cache"),
                "XDG_DATA_HOME": str(temporary / "data"),
                "XDG_RUNTIME_DIR": str(runtime),
                "QT_QPA_PLATFORM": "offscreen",
                "REVIEW_WALLPAPER": str(wallpaper),
            })
            result = subprocess.run(["dbus-run-session", "qs", "--no-color", "-p", str(harness)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("REVIEW SURFACES PASS:", output)
            for error in ("REVIEW SURFACES FAIL:", "TypeError", "ReferenceError", "Binding loop", "Cannot assign", "Unable to assign"):
                self.assertNotIn(error, output)


if __name__ == "__main__":
    unittest.main()
