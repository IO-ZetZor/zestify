#!/usr/bin/env python3
"""Keep Dolphin's graphics items on Breeze; scope QSS to its main window."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def launch(arguments, profile):
    stylesheet = (profile / "dolphin.qss").read_text()
    env = dict(os.environ)
    # Dolphin's Ctrl+N and FileManager1 paths invoke literal "dolphin".
    # Keep those child launches on this profile even in a minimal session PATH.
    env["PATH"] = str(profile) + os.pathsep + env.get("PATH", os.defpath)
    data_home = Path(env.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    style = data_home / "zestify/dolphin-style"
    if (style / "plugins/styles/breeze6.so").is_file():
        for key, directory in (("QT_PLUGIN_PATH", style / "plugins"),
                               ("LD_LIBRARY_PATH", style / "lib")):
            env[key] = str(directory) + (os.pathsep + env[key] if env.get(key) else "")
    if not shutil.which("qdbus6", path=env["PATH"]):
        print("Dolphin: the Zestify profile requires qdbus6", file=sys.stderr)
        return 1
    daemon = "--daemon" in arguments
    # Retain Dolphin's choice of existing tabs versus new windows. A reused
    # process already received its window stylesheet from its first launch.
    process = subprocess.Popen(["/usr/bin/dolphin", "-style", "breeze", *arguments], env=env)
    if daemon:
        # FileManager1's daemon creates GUI processes through the PATH above.
        return process.wait()
    service = "org.kde.dolphin-" + str(process.pid)
    deadline = time.monotonic() + 10
    while process.poll() is None and time.monotonic() < deadline:
        try:
            result = subprocess.run(["qdbus6", service], capture_output=True, text=True, timeout=2)
            windows = [path for path in result.stdout.splitlines()
                       if re.fullmatch(r"/dolphin/Dolphin_\d+", path)]
            applied = []
            for window in windows:
                result = subprocess.run(["qdbus6", service, window,
                                         "org.qtproject.Qt.QWidget.setStyleSheet", stylesheet],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
                applied.append(result.returncode == 0)
            if applied and all(applied):
                break
        except subprocess.TimeoutExpired:
            pass
        time.sleep(0.1)
    else:
        if process.poll() is None:
            print("Dolphin: could not apply the Zestify window stylesheet", file=sys.stderr)
    return process.wait()


if __name__ == "__main__":
    raise SystemExit(launch(sys.argv[1:], Path(__file__).resolve().parent))
