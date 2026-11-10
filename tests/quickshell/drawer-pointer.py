"""Exercise the left-edge drawer through actual Wayland pointer delivery.

The protocol setup matches the existing lock-pull regression fixture.
"""

import json
import os
import socket
import struct
import subprocess
import sys
import time

config, screen_name = sys.argv[1:]


def ipc(method):
    return subprocess.check_output(
        ["qs", "ipc", "-p", config, "call", "drawerTest", method], text=True
    )


def state():
    return json.loads(ipc("state"))


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


try:
    x, y = target["x"], target["y"] + target["height"] // 2
    move(x + target["width"] // 2, y)
    ipc("openLauncher")
    time.sleep(0.35)
    subprocess.run(["wtype", "zesti-drawer-check"], check=True)
    check(state()["launcherQuery"] == "zesti-drawer-check", "Launcher lost typing focus after the acquisition pulse")
    subprocess.run(["wtype", "-k", "Escape"], check=True)
    time.sleep(0.1)
    check(state()["surface"] == "", "Launcher Escape did not close after the focus pulse")
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
    print("Wayland drawer regression checks passed")
finally:
    button(False)
    move(original["x"], original["y"])
    send(5, 8)
    send(4, 1)
    connection.close()
