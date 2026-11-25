#!/usr/bin/env python3
"""Exercise right-edge shortcuts on an isolated compositor's headless output."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


REPO = Path(__file__).resolve().parents[2]
ARTIFACTS = Path("/tmp/zestify-shortcuts-native")
ARTIFACTS.mkdir(exist_ok=True)


def wait_for(check):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError("Timed out preparing the shortcut test compositor")


with tempfile.TemporaryDirectory(prefix="zs-") as directory:
    work = Path(directory)
    # Hyprland appends its long instance ID to Unix socket paths.
    runtime = work / "r"
    runtime.mkdir(mode=0o700)
    config = work / "hyprland.lua"
    config.write_text('hl.monitor({output="", mode="1920x1200@60", position="auto", scale=1})\n'
                      'hl.config({input={accel_profile="flat", sensitivity=0}})\n'
                      'hl.layer_rule({match={namespace="zestify-.*"}, no_anim=true})\n')
    host_display = Path(os.environ["XDG_RUNTIME_DIR"]) / os.environ["WAYLAND_DISPLAY"]
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(work / "config"),
               XDG_STATE_HOME=str(work / "state"), XDG_CACHE_HOME=str(work / "cache"),
               WAYLAND_DISPLAY=str(host_display), AQ_BACKEND="wayland,headless",
               HYPRLAND_NO_SD_VARS="1", HYPRLAND_NO_SD_NOTIFY="1", DRAWER_SHORTCUT_ONLY="1")
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    compositor = None
    with (ARTIFACTS / "hyprland.log").open("w") as log:
        try:
            compositor = subprocess.Popen(["Hyprland", "--config", str(config)], env=env,
                                          stdout=log, stderr=subprocess.STDOUT)

            def ready():
                if compositor.poll() is not None:
                    raise RuntimeError("Test compositor exited; see " + str(ARTIFACTS / "hyprland.log"))
                displays = [path for path in runtime.glob("wayland-*") if not path.name.endswith(".lock")]
                instances = list((runtime / "hypr").glob("*/.socket.sock"))
                return (displays[0], instances[0]) if displays and instances else None

            display, instance = wait_for(ready)
            env["WAYLAND_DISPLAY"] = display.name
            env["HYPRLAND_INSTANCE_SIGNATURE"] = instance.parent.name
            subprocess.run(["hyprctl", "output", "create", "headless", "DRAWER-MAIN"],
                           env=env, check=True, capture_output=True, timeout=5)
            subprocess.run(["hyprctl", "eval", 'hl.monitor({output="WAYLAND-1", disabled=true})'],
                           env=env, check=True, capture_output=True, timeout=5)

            def headless_ready():
                monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"], env=env))
                return len(monitors) == 1 and monitors[0]["name"] == "DRAWER-MAIN"

            wait_for(headless_ready)
            result = subprocess.run(["sh", str(REPO / "tests/quickshell/run-drawer.sh")],
                                    env=env, text=True, capture_output=True, timeout=100)
            output = result.stdout + result.stderr
            (ARTIFACTS / "drawer.log").write_text(output)
            if result.returncode or "DRAWER PASS:" not in output:
                raise RuntimeError("Shortcut regression failed; see " + str(ARTIFACTS / "drawer.log"))
            print("Native shortcut checks passed; preview: /tmp/zestify-shortcuts-preview.png")
        finally:
            if compositor is not None and compositor.poll() is None:
                compositor.terminate()
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()
