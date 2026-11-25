import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]


class CaptureSurfaceTest(unittest.TestCase):
    def test_capture_feedback_and_recording_indicators(self):
        with tempfile.TemporaryDirectory(prefix="zestify-capture-ui-") as directory:
            stage = Path(directory)
            shutil.copytree(REPO / "shell", stage / "shell")
            fixture = (REPO / "tests/quickshell/capture-ui.qml").read_text()
            (stage / "shell/shell.qml").write_text(fixture.replace("../../shell/", ""))
            backend = stage / "capture-stub"
            backend.write_text("""#!/usr/bin/python3
import json, os, sys
from pathlib import Path
state = Path(os.environ['CAPTURE_TEST_STATE'])
marker = Path(os.environ['XDG_STATE_HOME']) / 'zestify/record/recording'
marker.parent.mkdir(parents=True, exist_ok=True)
args = sys.argv[1:]
value = json.loads(state.read_text()) if state.exists() else {'recording': False, 'screenshots': 0}
if args == ['capture', 'screenshot']:
    value['screenshots'] += 1
    state.write_text(json.dumps(value))
    if value['screenshots'] == 2:
        print(json.dumps({'ok': True, 'cancelled': True}))
    elif value['screenshots'] == 3:
        print(json.dumps({'ok': False, 'error': 'synthetic failure'}))
        sys.exit(1)
    else:
        print(json.dumps({'ok': True, 'path': '/tmp/screenshot.png'}))
elif args == ['capture', 'record', 'toggle']:
    value['recording'] = not value['recording']
    value['error'] = None
    state.write_text(json.dumps(value))
    if value['recording']:
        marker.write_text(json.dumps(value))
    else:
        marker.unlink(missing_ok=True)
    if value.pop('fail_stop', False):
        state.write_text(json.dumps(value))
        print(json.dumps({'ok': False, 'error': 'Recorder did not produce a video'}))
        sys.exit(1)
    print(json.dumps({'ok': True, 'recording': value['recording'], 'path': '/tmp/recording.mp4'}))
elif args == ['capture', 'record', 'status']:
    print(json.dumps({'recording': value['recording'], 'path': '/tmp/recording.mp4', 'error': value.get('error')}))
elif args == ['test-stop-recording']:
    value['recording'] = False
    value['error'] = 'recording ended unexpectedly; any partial file was preserved'
    state.write_text(json.dumps(value))
elif args == ['test-start-recording']:
    value['recording'] = True
    state.write_text(json.dumps(value))
    marker.write_text(json.dumps(value))
elif args == ['test-fail-next-stop']:
    value['fail_stop'] = True
    state.write_text(json.dumps(value))
else:
    print(json.dumps({'ok': True}))
""")
            backend.chmod(0o755)
            runtime = stage / "runtime"
            runtime.mkdir(mode=0o700)
            preview = Path(os.environ.get("CAPTURE_UI_PREVIEW", str(stage / "preview.png")))
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(stage / "config"), XDG_STATE_HOME=str(stage / "state"),
                       XDG_CACHE_HOME=str(stage / "cache"), QT_QPA_PLATFORM="offscreen",
                       QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                       QT_NO_XDG_DESKTOP_PORTAL="1", ZESTI_BIN=str(backend), PYTHON="/usr/bin/true",
                       CAPTURE_TEST_STATE=str(stage / "capture-state.json"), CAPTURE_UI_PREVIEW=str(preview))
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
            result = subprocess.run(
                ["dbus-run-session", "qs", "--no-color", "-p", str(stage / "shell")],
                env=env, capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("CAPTURE UI PASS:", output)
            for error in ["CAPTURE UI FAIL:", "TypeError", "ReferenceError", "Binding loop"]:
                self.assertNotIn(error, output)
            self.assertTrue(preview.is_file(), output)
            env["ZESTI_BIN"] = str(stage / "missing-capture-cli")
            env["CAPTURE_MISSING_BACKEND"] = "1"
            result = subprocess.run(
                ["dbus-run-session", "qs", "--no-color", "-p", str(stage / "shell")],
                env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("CAPTURE UI PASS:", output)
            self.assertNotIn("CAPTURE UI FAIL:", output)


if __name__ == "__main__":
    unittest.main()
