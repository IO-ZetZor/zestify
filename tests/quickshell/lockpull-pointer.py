"""Exercise compositor-delivered drags in the isolated, dummy-lock fixture.

Uses the wlr virtual-pointer wire protocol with Python's standard library.
Run via run-lockpull.sh; the fixture must never use the real lock command.
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
        ["qs", "ipc", "-p", config, "call", "lockPullTest", method], text=True
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
    send(5, 1, uints(timestamp(), x - left, y - top, width, height))
    send(5, 4)
    sync()
    time.sleep(0.08)


def button(pressed):
    send(5, 2, uints(timestamp(), 272, int(pressed)))
    send(5, 4)
    sync()
    time.sleep(0.08)


def check(condition, message):
    if not condition:
        raise AssertionError(message + ": " + repr(state()))


try:
    x, y = target["x"] + target["width"] // 2, target["y"]
    distance = round(state()["triggerDistance"])
    move(x, y + 1)
    button(True)
    move(x, y + 80)
    check(state()["dragging"] and abs(state()["pull"] - 79) < 2,
          "Compositor motion did not reach the held gesture")
    move(x, y + distance + 20)
    time.sleep(0.5)
    check(state()["ready"] and not state()["requestingLock"] and state()["lockCount"] == 0,
          "Curtain dropped before releasing the button")
    move(x, y + distance + 80)
    check(abs(state()["pull"] - (distance + 79)) < 2,
          "Curtain stopped following beyond the threshold")
    move(x, y + 80)
    button(False)
    time.sleep(0.4)
    check(not state()["active"] and state()["lockCount"] == 0,
          "Returning above the threshold did not cancel")

    move(x, y + 1)
    button(True)
    move(x, y + distance + 20)
    button(False)
    check(state()["requestingLock"] and state()["pull"] < state()["height"],
          "Release did not start the finishing animation")
    time.sleep(0.6)
    check(state()["lockCount"] == 1 and state()["pull"] == state()["height"],
          "The full curtain did not hand off to the locker once")
    ipc("unlock")

    move(x, y + 1)
    button(True)
    move(x, y + distance + 20)
    subprocess.run(["wtype", "-k", "Escape"], check=True)
    button(False)
    time.sleep(0.4)
    check(not state()["active"] and state()["lockCount"] == 1,
          "Escape did not cancel the real held pointer gesture")
    print("Wayland pointer regression checks passed")
finally:
    button(False)
    move(original["x"], original["y"])
    send(5, 8)
    send(4, 1)
    connection.close()
