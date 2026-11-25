"""Exercise notification, power and shortcut drawers through actual Wayland input.

The protocol setup matches the existing lock-pull regression fixture.
"""

import io
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time

config, screen_name = sys.argv[1:]


def ipc(method, *args):
    return subprocess.check_output(
        ["qs", "ipc", "-p", config, "call", "drawerTest", method, *map(str, args)], text=True
    )


def state():
    return json.loads(ipc("state"))


def power_state():
    return json.loads(ipc("powerState"))


def shortcut_state():
    return json.loads(ipc("shortcutState"))


def wait_for_shortcut(predicate, timeout=2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        current = shortcut_state()
        if predicate(current):
            return current
        time.sleep(0.025)
    check(False, "Shortcut state did not settle: " + repr(current))


def query(kind):
    return json.loads(subprocess.check_output(["hyprctl", "-j", kind]))


monitors = query("monitors")
original = query("cursorpos")
for monitor in monitors:
    if monitor["transform"] % 2:
        monitor["width"], monitor["height"] = monitor["height"], monitor["width"]
    monitor["width"] = round(monitor["width"] / monitor["scale"])
    monitor["height"] = round(monitor["height"] / monitor["scale"])
left = min(m["x"] for m in monitors)
top = min(m["y"] for m in monitors)
width = max(m["x"] + m["width"] for m in monitors) - left
height = max(m["y"] + m["height"] for m in monitors) - top
target = next(m for m in monitors if m["name"] == screen_name)

connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
connection.settimeout(3)
connection.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"]))
buffer = b""
next_id = 3
manager = None


def send(object_id, opcode, body=b""):
    connection.sendall(struct.pack("II", object_id, (len(body) + 8) << 16 | opcode) + body)


def uints(*values):
    return struct.pack("I" * len(values), *values)


def string(value):
    data = value.encode() + b"\0"
    return uints(len(data)) + data + b"\0" * (-len(data) % 4)


def sync():
    global buffer, next_id, manager
    callback = next_id
    next_id += 1
    send(1, 0, uints(callback))
    while True:
        while len(buffer) < 8:
            chunk = connection.recv(65536)
            if not chunk:
                raise RuntimeError("Wayland connection closed")
            buffer += chunk
        object_id, header = struct.unpack("II", buffer[:8])
        size, opcode = header >> 16, header & 65535
        while len(buffer) < size:
            buffer += connection.recv(65536)
        body, buffer = buffer[8:size], buffer[size:]
        if object_id == 1 and opcode == 0:
            raise RuntimeError("Wayland error: " + repr(body))
        if object_id == 2 and opcode == 0:
            name, length = struct.unpack("II", body[:8])
            interface = body[8:8 + length - 1].decode()
            if interface == "zwlr_virtual_pointer_manager_v1":
                manager = name
        if object_id == callback and opcode == 0:
            return


send(1, 1, uints(2))
sync()
if manager is None:
    raise RuntimeError("Virtual pointer protocol unavailable")
send(2, 0, uints(manager) + string("zwlr_virtual_pointer_manager_v1") + uints(1, 4))
send(4, 0, uints(0, 5))
next_id = 6
sync()


def timestamp():
    return int(time.monotonic() * 1000) & 0xffffffff


def move(x, y):
    # Hyprland can map virtual-pointer absolute coordinates through physical
    # output extents while cursorpos reports logical coordinates. Correct
    # against the compositor's actual cursor position, including mixed scales.
    raw_x, raw_y = x - left, y - top
    for _ in range(5):
        send(5, 1, uints(timestamp(), max(0, round(raw_x)), max(0, round(raw_y)), width, height))
        send(5, 4)
        sync()
        time.sleep(0.04)
        actual = query("cursorpos")
        dx, dy = x - actual["x"], y - actual["y"]
        if abs(dx) <= 1 and abs(dy) <= 1:
            break
        raw_x += dx
        raw_y += dy


def button(pressed):
    send(5, 2, uints(timestamp(), 272, int(pressed)))
    send(5, 4)
    sync()
    time.sleep(0.08)


def check(condition, message):
    if not condition:
        raise AssertionError(message + ": " + repr(state()))


def check_portrait_face(angle, message):
    # Wait for completion rather than assuming the render thread was able to
    # finish within a fixed sleep while other verification is running.
    deadline = time.monotonic() + 1.5
    while time.monotonic() < deadline:
        current = power_state()
        if current["portrait"]["angle"] == angle and not current["portrait"]["settling"]:
            return
        time.sleep(0.025)
    check(False, message + ": " + repr(current))


def check_centered_animation(method, *args):
    # QML coordinates/layer targets remain centered even when the compositor
    # is animating the actual buffer. Check rendered pixels instead.
    from PIL import Image
    ipc(method, *args)
    expected_x = target["width"] / 2
    expected_y = state()["topGap"] + 8
    deviations = []
    for _ in range(12):
        pixels = subprocess.check_output(["grim", "-s", "1", "-o", screen_name, "-"])
        image = Image.open(io.BytesIO(pixels)).convert("RGB")
        points = [(px, py) for py in range(min(80, image.height))
                  for px in range(image.width)
                  if image.getpixel((px, py))[0] > 240
                  and image.getpixel((px, py))[1] < 20
                  and image.getpixel((px, py))[2] > 240]
        check(bool(points), "Pill animation marker disappeared")
        center_x = (min(px for px, _ in points) + max(px for px, _ in points) + 1) / 2
        center_y = (min(py for _, py in points) + max(py for _, py in points) + 1) / 2
        deviations.append([center_x - expected_x, center_y - expected_y])
        check(abs(center_x - expected_x) <= 2 and abs(center_y - expected_y) <= 2,
              "Rendered pill shifted during native resizing: " + repr(deviations[-1]))
        time.sleep(0.015)
    print("Rendered pill remained centered:", method, args, deviations)


def exercise_shortcuts():
    x = target["x"]
    bottom = target["y"] + target["height"] - 1
    center_x = x + target["width"] // 2
    # The expanded pill and the other drawers must all leave the right edge free.
    right = x + target["width"] - 1
    middle_y = target["y"] + target["height"] // 2
    for opened_surface in ["openPill", "open", "openPower"]:
        ipc(opened_surface)
        wait_for_shortcut(lambda current: not current["active"])
        # Keyboard-opened pills briefly acquire Exclusive focus before OnDemand.
        time.sleep(0.3)
        move(right, middle_y)
        button(True)
        wait_for_shortcut(lambda current: current["dragging"])
        move(right - 40, middle_y)
        current = wait_for_shortcut(lambda value: abs(value["pull"] - 40) < 3)
        check(current["dragging"] and abs(current["pull"] - 40) < 3,
              "Right edge blocked by " + opened_surface + ": " + repr(current))
        check(current["maskX"] >= 6 and current["maskY"] >= 6,
              "Shortcuts did not preserve the other edges")
        # Release short of the target so the spring has distance to settle.
        move(right - current["drawerWidth"] * 0.8, middle_y)
        time.sleep(0.15)
        button(False)
        overshot = False
        for _ in range(18):
            current = shortcut_state()
            overshot |= current["pull"] > current["drawerWidth"]
            time.sleep(0.04)
        check(current["opened"] and not current["settling"] and overshot,
              "Shortcut drawer did not bounce and settle: " + repr(current))
        check(not state()["active"] and not power_state()["active"] and current["surface"] == "",
              "Shortcuts retained another surface")

    ipc("shortcutPreview")
    time.sleep(0.15)
    check(Path(os.environ["DRAWER_SHORTCUT_PREVIEW"]).is_file(), "Shortcut preview was not saved")

    # Clicking capture closes the drawer before invoking the stub CLI.
    capture_log = Path(os.environ["DRAWER_CAPTURE_LOG"])
    for action, expected in [("screenshot", "capture screenshot"), ("record", "capture record toggle")]:
        ipc("openShortcuts")
        time.sleep(0.8)
        current = shortcut_state()
        icon = next(item for item in current["icons"] if item["action"] == action)
        before = capture_log.read_text() if capture_log.exists() else ""
        move(x + icon["x"] + icon["width"] / 2, target["y"] + icon["y"] + icon["height"] / 2)
        button(True)
        button(False)
        current = shortcut_state()
        check(not current["active"] and not current["settling"] and current["owner"] == "",
              "Capture must hide the drawer immediately")
        deadline = time.monotonic() + 1
        while (capture_log.read_text() if capture_log.exists() else "") == before:
            check(not shortcut_state()["active"], "Capture ran while the drawer was still visible")
            if time.monotonic() >= deadline:
                check(False, "Capture was not dispatched after hiding the drawer")
            time.sleep(0.01)
        current = wait_for_shortcut(lambda value: value["pending"] == "")
        check(not current["active"] and current["pending"] == "", "Capture did not dismiss shortcuts")
        check(capture_log.read_text().splitlines()[-1] == expected, "Wrong capture command was dispatched")

    # Both migrated surfaces also work when the resting pill is hidden by fullscreen.
    ipc("fullscreen", "true")
    time.sleep(0.2)
    for action in ["wallpaper", "config", "system"]:
        ipc("openShortcuts")
        time.sleep(0.8)
        current = shortcut_state()
        icon = next(item for item in current["icons"] if item["action"] == action)
        move(x + icon["x"] + icon["width"] / 2, target["y"] + icon["y"] + icon["height"] / 2)
        button(True)
        button(False)
        time.sleep(1)
        current = shortcut_state()
        check(not current["active"] and current["surface"] == action,
              "Shortcut failed to open " + action + ": " + repr(current))
        if action == "wallpaper":
            check(current["wallpaperOpened"] and current["pillSurface"] == "",
                  "Wallpaper must open in its own window while fullscreen")
            subprocess.run(["wtype", "-k", "Escape"], check=True)
            wait_for_shortcut(lambda value: not value["wallpaperOpened"])
            check(shortcut_state()["surface"] == "", "Escape did not close the wallpaper picker")
        else:
            check(current["pillSurface"] == action and current["pillVisible"]
                  and current["pillOpacity"] == 1 and current["pillMaskWidth"] > 0,
                  "Surface stayed hidden in fullscreen: " + repr(current))
    ipc("fullscreen", "false")

    ipc("openShortcuts")
    time.sleep(0.8)
    current = shortcut_state()
    handle_x = right - current["drawerWidth"] + 10
    move(handle_x, middle_y)
    button(True)
    move(right - 1, middle_y)
    check(shortcut_state()["dragging"], "Shortcut handle lost its grab")
    button(False)
    time.sleep(0.8)
    check(not shortcut_state()["active"], "Shortcut handle did not close")
    move(right, middle_y)
    button(True)
    move(right - 15, middle_y)
    time.sleep(0.15)
    button(False)
    time.sleep(0.8)
    check(not shortcut_state()["active"], "A short pull opened shortcuts")

    ipc("openShortcuts")
    time.sleep(0.8)
    subprocess.run(["wtype", "-k", "Escape"], check=True)
    time.sleep(0.8)
    check(not shortcut_state()["active"], "Escape did not close shortcuts")
    ipc("openShortcuts")
    time.sleep(0.8)
    move(center_x, middle_y)
    button(True)
    button(False)
    time.sleep(0.8)
    check(not shortcut_state()["active"], "Outside click did not close shortcuts")

    ipc("openShortcuts")
    time.sleep(0.8)
    ipc("transferShortcuts")
    time.sleep(0.8)
    check(not shortcut_state()["active"] and shortcut_state()["owner"] == "other-display",
          "Shortcut close cleared another monitor's ownership")
    ipc("clearShortcutOwner")
    ipc("openShortcuts")
    time.sleep(0.8)
    move(center_x, target["y"] + 1)
    button(True)
    move(center_x, target["y"] + 65)
    current = shortcut_state()
    check(current["lockDragging"] and abs(current["lockPull"] - 64) < 3,
          "Shortcuts blocked the top-edge lock gesture")
    button(False)
    time.sleep(0.8)
    check(not shortcut_state()["active"], "Lock cancellation left shortcuts open")
    ipc("openShortcuts")
    time.sleep(0.8)
    ipc("dpmsOff")
    time.sleep(0.1)
    check(not shortcut_state()["active"] and shortcut_state()["maskWidth"] == 0,
          "DPMS off retained shortcut input")
    ipc("dpmsOn")
    time.sleep(0.1)
    check(shortcut_state()["maskWidth"] == shortcut_state()["edgeWidth"], "DPMS on did not restore right input")
    print("Wayland drawer regression checks passed")


def exercise_existing_drawers():
    x, y = target["x"], target["y"] + target["height"] // 2
    move(x + target["width"] // 2, y)
    if os.environ.get("PILL_ANIMATION_CHECK") == "1":
        # The before-control overrides only this isolated compositor's rule.
        if os.environ.get("PILL_ANIMATION_BASELINE") == "1":
            subprocess.run(["hyprctl", "eval", 'hl.layer_rule({match={namespace="zestify-pill"},no_anim=false})'], check=True)
        time.sleep(0.2)
        check_centered_animation("pin", "true")
        check_centered_animation("pin", "false")
        check_centered_animation("openPill")
        check_centered_animation("closePill")
        # Runtime rules are cleared by compositor reload; the event handler
        # must restore them without requiring a transparency change.
        generation = state()["layerRuleGeneration"]
        subprocess.run(["hyprctl", "reload"], check=True)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            current = state()
            if (current["layerRuleGeneration"] > generation
                    and current["appliedLayerSettings"]):
                break
            time.sleep(0.05)
        check(current["layerRuleGeneration"] > generation
              and bool(current["appliedLayerSettings"]),
              "Compositor reload did not successfully reapply layer rules")
        time.sleep(0.2)
        check_centered_animation("pin", "true")
        check_centered_animation("pin", "false")
        time.sleep(0.6)
    current = state()
    check(current["nativeWidth"] == current["screenWidth"]
          and current["nativeHeight"] == current["screenHeight"],
          "Pill native canvas must remain stable to avoid stale-buffer rescaling")
    ipc("pin", "true")
    time.sleep(0.6)
    ipc("scale", 1.5)
    time.sleep(0.6)
    ipc("scale", 1.0)
    sizes = set()
    for _ in range(24):
        current = state()
        sizes.add((current["nativeWidth"], current["nativeHeight"]))
        check(current["nativeWidth"] + 1 >= current["pillWidth"]
              and current["nativeHeight"] + 1 >= current["topGap"] + current["pillHeight"],
              "Scale shrink clipped the animating pill")
        time.sleep(0.025)
    check(len(sizes) == 1, "Pill native canvas resized during a QML morph")
    ipc("pin", "false")
    time.sleep(0.6)
    ipc("openLauncher")
    time.sleep(0.35)
    current = state()
    check(current["nativeWidth"] == current["screenWidth"]
          and current["nativeHeight"] == current["screenHeight"],
          "Expanded pill lost its full-screen outside-click catcher")
    subprocess.run(["wtype", "zesti-drawer-check"], check=True)
    check(state()["launcherQuery"] == "zesti-drawer-check", "Launcher lost typing focus after the acquisition pulse")
    subprocess.run(["wtype", "-k", "Escape"], check=True)
    time.sleep(0.1)
    check(state()["surface"] == "", "Launcher Escape did not close after the focus pulse")
    ipc("openPill")
    time.sleep(0.6)
    ipc("createOpenPanel")
    time.sleep(0.1)
    check(state()["temporaryPill"]["held"], "Initially expanded panel did not initialize its canvas hold")
    ipc("closePill")
    time.sleep(0.1)
    check(state()["temporaryPill"]["visible"]
          and state()["temporaryPill"]["height"] == state()["screenHeight"],
          "Hidden-mode panel was unmapped during the closing morph")
    time.sleep(0.7)
    check(not state()["temporaryPill"]["visible"], "Hidden-mode closing panel did not unmap after settling")
    ipc("destroyOpenPanel")
    ipc("openPill")
    time.sleep(0.2)
    check(state()["pillSurface"] == "calendar" and state()["pillFocus"] != 0,
          "Pill fixture did not hold keyboard focus")
    move(x + 1, y)
    button(True)
    move(x + 100, y)
    check(state()["dragging"] and abs(state()["pull"] - 99) < 3,
          "Left-edge pointer motion was lost after the grab")
    check(state()["maskWidth"] > state()["edgeWidth"] and state()["maskY"] >= 6,
          "Held drawer did not expand input while preserving the lock edge")
    move(x + 280, y)
    time.sleep(0.15)
    check(state()["dragging"] and not state()["opened"], "Drawer settled before release")
    button(False)
    overshot = False
    for _ in range(18):
        current = state()
        overshot |= current["pull"] > current["drawerWidth"]
        time.sleep(0.04)
    check(overshot and state()["opened"] and not state()["settling"],
          "Release did not bounce and settle open")
    check(state()["surface"] == "" and state()["pillSurface"] == "",
          "Drawer did not close the expanded pill surface")

    handle_x = x + round(state()["drawerWidth"]) - 10
    move(handle_x, y)
    button(True)
    move(x + 75, y)
    check(state()["dragging"] and state()["pull"] < 100, "Right-side closing handle lost the grab")
    button(False)
    time.sleep(0.9)
    check(not state()["active"] and state()["owner"] == "", "Handle release did not close the drawer")

    move(x + 1, y)
    button(True)
    move(x + 45, y)
    time.sleep(0.15)
    button(False)
    time.sleep(0.9)
    check(not state()["active"], "A held short pull opened the drawer")

    ipc("openPill")
    time.sleep(0.2)
    move(x + 1, y)
    button(True)
    move(x + 280, y)
    subprocess.run(["wtype", "-k", "Escape"], check=True)
    button(False)
    time.sleep(0.9)
    check(not state()["active"], "Escape during a held drag reopened the drawer")

    ipc("open")
    time.sleep(0.9)
    move(x + target["width"] - 30, y)
    button(True)
    button(False)
    time.sleep(0.9)
    check(not state()["active"], "Outside click did not dismiss the drawer")

    ipc("open")
    time.sleep(0.9)
    ipc("transfer")
    time.sleep(0.9)
    check(not state()["active"] and state()["owner"] == "other-display",
          "Closing the previous monitor cleared the new monitor's ownership")
    ipc("clearOwner")

    ipc("open")
    time.sleep(0.9)
    move(x + 1, target["y"] + 1)
    button(True)
    move(x + 1, target["y"] + 65)
    check(state()["lockDragging"] and abs(state()["lockPull"] - 64) < 3
          and not state()["dragging"], "Drawer intercepted the top-edge lock gesture")
    button(False)
    time.sleep(0.9)
    check(not state()["lockActive"] and not state()["active"], "Top-edge cancellation left an overlay active")

    ipc("open")
    time.sleep(0.9)
    ipc("dpmsOff")
    time.sleep(0.1)
    check(not state()["active"] and state()["maskWidth"] == 0, "DPMS off retained drawer input")
    ipc("dpmsOn")
    time.sleep(0.1)
    check(state()["maskWidth"] == state()["edgeWidth"], "DPMS on did not restore left-edge input")

    # Start with an expanded pill: its scrim must leave the bottom edge free.
    bottom = target["y"] + target["height"] - 1
    center_x = x + target["width"] // 2
    ipc("openPill")
    time.sleep(0.2)
    move(center_x, bottom)
    button(True)
    move(center_x, bottom - 100)
    current = power_state()
    check(current["dragging"] and abs(current["pull"] - 100) < 3,
          "Bottom-edge power drag was blocked by the pill: " + repr(current))
    check(current["maskHeight"] > current["edgeHeight"] and current["maskX"] >= 6
          and current["maskY"] >= 6, "Power grab did not preserve the other edges")
    move(center_x, bottom - 320)
    time.sleep(0.15)
    check(power_state()["dragging"] and not power_state()["opened"], "Power drawer settled before release")
    button(False)
    overshot = False
    for _ in range(18):
        current = power_state()
        overshot |= current["pull"] > current["drawerHeight"]
        time.sleep(0.04)
    current = power_state()
    check(overshot and current["opened"] and not current["settling"],
          "Power release did not bounce and settle: " + repr(current))
    check(current["surface"] == "" and current["pillSurface"] == "",
          "Power drawer retained an expanded pill surface")

    portrait = current["portrait"]
    portrait_x = x + portrait["x"] + portrait["width"] / 2
    portrait_y = target["y"] + portrait["y"] + portrait["height"] / 2
    move(portrait_x, portrait_y)
    button(True)
    move(portrait_x + portrait["width"] / 2, portrait_y)
    current = power_state()
    check(current["portrait"]["dragging"] and abs(current["portrait"]["angle"] - 90) < 4,
          "Portrait did not follow the drag to edge-on: " + repr(current))
    move(portrait_x + portrait["width"] * 1.5, portrait_y)
    current = power_state()
    check(current["portrait"]["dragging"] and abs(current["portrait"]["angle"] - 270) < 4,
          "Portrait lost its grab past the edge: " + repr(current))
    move(portrait_x - portrait["width"] / 3, portrait_y + 30)
    current = power_state()
    check(abs(current["portrait"]["angle"] + 60) < 4 and not current["dragging"]
          and current["pull"] == current["drawerHeight"],
          "Reverse/vertical portrait motion moved the drawer: " + repr(current))
    button(False)
    check(not power_state()["portrait"]["dragging"] and power_state()["opened"],
          "Portrait release dismissed the drawer")
    check_portrait_face(0, "A release near the original face did not settle to it")

    # Past the halfway point, the closest face is the mirrored back.
    move(portrait_x, portrait_y)
    button(True)
    move(portrait_x + portrait["width"] * 2 / 3, portrait_y)
    button(False)
    check_portrait_face(180, "A release near the mirrored face did not settle to it")
    subprocess.run(["wtype", "-k", "Right"], check=True)
    check_portrait_face(0, "Portrait arrow key did not flip to the original face")
    subprocess.run(["wtype", "-k", "Left"], check=True)
    check_portrait_face(180, "Portrait arrow key did not flip to the mirrored face")
    subprocess.run(["wtype", "-k", "Home"], check=True)
    check_portrait_face(0, "Portrait Home did not reset rotation")

    handle_y = target["y"] + target["height"] - round(current["drawerHeight"]) + 10
    move(center_x, handle_y)
    button(True)
    move(center_x, bottom - 60)
    check(power_state()["dragging"] and power_state()["pull"] < 100,
          "Power top handle lost the grab: " + repr(power_state()))
    button(False)
    time.sleep(0.9)
    check(not power_state()["active"] and power_state()["owner"] == "", "Power handle did not close")

    move(center_x, bottom)
    button(True)
    move(center_x, bottom - 40)
    time.sleep(0.15)
    button(False)
    time.sleep(0.9)
    check(not power_state()["active"], "A held short pull opened the power drawer")

    move(center_x, bottom)
    button(True)
    move(center_x, bottom - 320)
    subprocess.run(["wtype", "-k", "Escape"], check=True)
    button(False)
    time.sleep(0.9)
    check(not power_state()["active"], "Escape during a power drag reopened the drawer")

    # Each overlay must leave the other's opening edge reachable.
    ipc("open")
    time.sleep(0.9)
    move(center_x, bottom)
    button(True)
    move(center_x, bottom - 320)
    time.sleep(0.15)
    button(False)
    time.sleep(0.9)
    check(power_state()["opened"] and not state()["active"], "Notifications blocked the bottom edge")
    move(x + 1, y)
    button(True)
    move(x + 280, y)
    time.sleep(0.15)
    button(False)
    time.sleep(0.9)
    check(state()["opened"] and not power_state()["active"], "Power drawer blocked the notification edge")

    ipc("openPower")
    time.sleep(0.9)
    check(power_state()["opened"] and not state()["active"], "CLI power opening did not transfer ownership")
    move(center_x, target["y"] + 100)
    button(True)
    button(False)
    time.sleep(0.9)
    check(not power_state()["active"], "Outside click did not close the power drawer")

    ipc("openPower")
    time.sleep(0.9)
    ipc("transferPower")
    time.sleep(0.9)
    check(not power_state()["active"] and power_state()["owner"] == "other-display",
          "Power drawer close cleared another monitor's ownership")
    ipc("clearPowerOwner")

    ipc("openPower")
    time.sleep(0.9)
    move(center_x, target["y"] + 1)
    button(True)
    move(center_x, target["y"] + 65)
    current = power_state()
    check(current["lockDragging"] and abs(current["lockPull"] - 64) < 3
          and not current["dragging"], "Power drawer blocked the top-edge lock gesture")
    button(False)
    time.sleep(0.9)
    check(not power_state()["active"], "Lock cancellation left power open")

    ipc("openPower")
    time.sleep(0.9)
    ipc("dpmsOff")
    time.sleep(0.1)
    check(not power_state()["active"] and power_state()["maskHeight"] == 0,
          "DPMS off retained power drawer input")
    ipc("dpmsOn")
    time.sleep(0.1)
    check(power_state()["maskHeight"] == power_state()["edgeHeight"], "DPMS on did not restore bottom input")


try:
    if os.environ.get("DRAWER_SHORTCUT_ONLY") != "1":
        exercise_existing_drawers()
    exercise_shortcuts()
finally:
    button(False)
    move(original["x"], original["y"])
    send(5, 8)
    send(4, 1)
    connection.close()
