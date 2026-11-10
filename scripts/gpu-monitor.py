#!/usr/bin/env python3
"""Sample Linux GPUs on stdin requests; emit one JSON array per request.

DRM/sysfs works without extra packages. NVIDIA's proprietary driver uses
optional nvidia-smi. DRM fdinfo is a fallback for Intel/Xe and other drivers;
its utilization covers only clients whose /proc fdinfo the user can read.
"""

import csv
import ctypes
import json
import math
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path


LIBC = ctypes.CDLL(None, use_errno=True)


def die_with_parent(parent_pid):
    # Linux PR_SET_PDEATHSIG: Quickshell can SIGKILL this helper on reload,
    # bypassing Python cleanup. Make an active NVIDIA child die with it.
    if LIBC.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    if os.getppid() != parent_pid:
        os.kill(os.getpid(), signal.SIGKILL)


def read_text(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return ""


def number(text):
    try:
        value = float(text)
        return value if math.isfinite(value) and value >= 0 else None
    except (TypeError, ValueError):
        return None


def pci_id(text):
    """Normalize the eight-digit domain emitted by nvidia-smi to Linux PCI IDs."""
    match = re.fullmatch(r"([0-9a-fA-F]+):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})\.([0-7])", text)
    if not match:
        return text
    return f"{int(match[1], 16):04x}:{match[2].lower()}:{match[3].lower()}.{match[4]}"


def pci_names(paths):
    for path in paths:
        text = read_text(path)
        if not text:
            continue
        devices = {}
        vendor = ""
        for line in text.splitlines():
            if re.match(r"^[0-9a-fA-F]{4}  ", line):
                vendor = line[:4].lower()
            elif re.match(r"^\t[0-9a-fA-F]{4}  ", line):
                devices[(vendor, line[1:5].lower())] = line[7:].strip()
        return devices
    return {}


def parse_fdinfo(text):
    fields = {}
    engines = {}
    capacities = {}
    for line in text.splitlines():
        key, separator, value = line.partition(":")
        if not separator:
            continue
        value = value.strip()
        fields[key] = value
        if key.startswith("drm-engine-capacity-"):
            capacity = number(value)
            if capacity and capacity.is_integer():
                capacities[key.removeprefix("drm-engine-capacity-")] = capacity
        elif key.startswith("drm-engine-"):
            match = re.fullmatch(r"(\d+)\s+ns", value)
            if match:
                engines[key.removeprefix("drm-engine-")] = (int(match[1]), None)
    for key, value in fields.items():
        if key.startswith("drm-cycles-") and value.isdecimal():
            engine = key.removeprefix("drm-cycles-")
            total = fields.get("drm-total-cycles-" + engine, "")
            if engine not in engines and total.isdecimal():
                engines[engine] = (int(value), int(total))
    if not fields.get("drm-client-id") or not fields.get("drm-pdev") or not engines:
        return None
    return (pci_id(fields["drm-pdev"]), fields["drm-client-id"], engines, capacities)


class GpuMonitor:
    def __init__(self, drm=Path("/sys/class/drm"), pci=Path("/sys/bus/pci/devices"),
                 proc=Path("/proc"), names=None, clock=time.monotonic_ns,
                 run=subprocess.run):
        self.drm = drm
        self.pci = pci
        self.proc = proc
        self.names = names if names is not None else pci_names([
            Path("/usr/share/hwdata/pci.ids"), Path("/usr/share/misc/pci.ids"),
            Path("/usr/share/pci.ids"),
        ])
        self.clock = clock
        self.run = run
        self.previous = {}
        self.previous_time = None

    def discover(self):
        devices = {}
        try:
            nodes = sorted(self.drm.iterdir())
        except OSError:
            nodes = []
        for node in nodes:
            if re.fullmatch(r"card\d+|renderD\d+", node.name):
                device = (node / "device").resolve()
                if device.is_dir():
                    devices[str(device)] = device
        # Some proprietary/headless NVIDIA setups have no DRM node.
        try:
            for device in self.pci.iterdir():
                if (read_text(device / "vendor") == "0x10de"
                        and read_text(device / "class").startswith("0x03")):
                    devices[str(device.resolve())] = device.resolve()
        except OSError:
            pass
        return sorted(devices.values(), key=lambda device: device.name)

    def clients(self, wanted):
        clients = {}
        if not wanted:
            return clients
        try:
            processes = list(self.proc.iterdir())
        except OSError:
            return clients
        for process in processes:
            if not process.name.isdecimal():
                continue
            try:
                descriptors = list((process / "fdinfo").iterdir())
            except OSError:
                continue
            for descriptor in descriptors:
                client = parse_fdinfo(read_text(descriptor))
                if not client or client[0] not in wanted:
                    continue
                key = client[:2]
                # A DRM client can have duplicated fds, including across processes.
                # Reads happen at slightly different times: retain the largest counter.
                engines, capacities = clients.setdefault(key, ({}, {}))
                for engine, counter in client[2].items():
                    previous = engines.get(engine, counter)
                    engines[engine] = max(previous, counter, key=lambda item: (item[0], item[1] or 0))
                capacities.update(client[3])
        return clients

    def client_percent(self, device_id, clients, elapsed):
        totals = {}
        capacities = {}
        for key, (engines, counts) in clients.items():
            if key[0] != device_id:
                continue
            old = self.previous.get(key)
            if old is None:
                continue
            for engine, counter in engines.items():
                before = old[0].get(engine)
                if before is not None and counter[0] >= before[0]:
                    if counter[1] is None and before[1] is None:
                        duration = elapsed
                    elif counter[1] is not None and before[1] is not None:
                        duration = counter[1] - before[1]
                    else:
                        continue
                    if not duration or duration <= 0:
                        continue
                    totals[engine] = totals.get(engine, 0) + (counter[0] - before[0]) / duration
                    capacities[engine] = max(capacities.get(engine, 1), counts.get(engine, 1))
        if not totals or not elapsed or elapsed <= 0:
            return None
        # Independent engines can run concurrently. Use the busiest class rather
        # than adding render/video/copy percentages, which can exceed 100%.
        return min(100, max(100 * busy / capacities[engine]
                            for engine, busy in totals.items()))

    def nvidia(self, ids):
        if not ids:
            return {}
        parent_pid = os.getpid()
        try:
            result = self.run([
                "nvidia-smi", "--id=" + ",".join(ids),
                "--query-gpu=pci.bus_id,name,utilization.gpu,temperature.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ], capture_output=True, text=True, timeout=2, check=False,
                preexec_fn=lambda: die_with_parent(parent_pid))
        except (OSError, subprocess.SubprocessError):
            return {}
        if result.returncode:
            return {}
        readings = {}
        for row in csv.reader(result.stdout.splitlines()):
            if len(row) != 6:
                continue
            bus, name, usage, temperature, used, total = (part.strip() for part in row)
            used, total = number(used), number(total)
            readings[pci_id(bus)] = {
                "name": name, "utilization": number(usage), "temperature": number(temperature),
                "memoryUsed": used * 1048576 if used is not None else None,
                "memoryTotal": total * 1048576 if total is not None else None,
            }
        return readings

    def sample(self):
        devices = self.discover()
        result = []
        for device in devices:
            vendor_id = read_text(device / "vendor").removeprefix("0x").lower()
            device_id = read_text(device / "device").removeprefix("0x").lower()
            vendor = {"8086": "Intel", "1002": "AMD", "10de": "NVIDIA"}.get(vendor_id, "GPU")
            driver = (device / "driver").resolve().name if (device / "driver").exists() else ""
            status = read_text(device / "power/runtime_status")
            gpu = {
                "id": pci_id(device.name), "name": self.names.get((vendor_id, device_id), vendor + " Graphics"),
                "vendor": vendor, "driver": driver,
                "status": "suspended" if status in ("suspended", "suspending") else "active",
                "utilization": None, "temperature": None,
                "memoryUsed": None, "memoryTotal": None, "source": "",
            }
            if gpu["status"] == "active":
                gpu["utilization"] = number(read_text(device / "gpu_busy_percent"))
                if gpu["utilization"] is not None:
                    gpu["source"] = "GPU usage"
                gpu["memoryUsed"] = number(read_text(device / "mem_info_vram_used"))
                gpu["memoryTotal"] = number(read_text(device / "mem_info_vram_total"))
                # Only use this GPU's own hwmon sensor; coretemp/k10temp are CPU sensors.
                for hwmon in sorted((device / "hwmon").glob("hwmon*")):
                    if read_text(hwmon / "name") not in ("amdgpu", "radeon", "nouveau", "i915", "xe"):
                        continue
                    temperature = number(read_text(hwmon / "temp1_input"))
                    if temperature is not None:
                        gpu["temperature"] = temperature / 1000
                        break
            result.append(gpu)

        # Do not invoke nvidia-smi on suspended GPUs: that can wake a hybrid dGPU.
        nvidia_ids = [gpu["id"] for gpu in result
                      if gpu["driver"] == "nvidia" and gpu["status"] == "active"]
        readings = self.nvidia(nvidia_ids)
        for gpu in result:
            if gpu["id"] in readings:
                gpu.update(readings[gpu["id"]])
                gpu["source"] = "GPU usage" if gpu["utilization"] is not None else ""

        wanted = {gpu["id"] for gpu in result if gpu["status"] == "active"
                  and gpu["utilization"] is None and gpu["driver"] != "nvidia"}
        clients = self.clients(wanted)
        now = self.clock()
        elapsed = now - self.previous_time if self.previous_time is not None else None
        for gpu in result:
            if gpu["id"] in wanted:
                gpu["utilization"] = self.client_percent(gpu["id"], clients, elapsed)
                if gpu["utilization"] is not None:
                    gpu["source"] = "Visible clients"
            if gpu["utilization"] is not None:
                gpu["utilization"] = max(0, min(100, gpu["utilization"]))
        # DRM counters may temporarily decrease. Keep the high watermark until
        # they catch up, as specified by the DRM fdinfo ABI, to avoid a later spike.
        for key, (engines, _counts) in clients.items():
            old = self.previous.get(key)
            if old is None:
                continue
            for engine, counter in engines.items():
                before = old[0].get(engine)
                if before is not None and (counter[1] is None) == (before[1] is None):
                    engines[engine] = (max(counter[0], before[0]),
                        max(counter[1], before[1]) if counter[1] is not None else None)
        self.previous = clients
        self.previous_time = now
        return result


def main():
    def terminate(_signal, _frame):
        # Raising through subprocess.run kills and reaps an in-flight nvidia-smi
        # before the helper exits on Stats.stop(). Reloads may use SIGKILL;
        # the NVIDIA child's parent-death signal covers that path.
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    monitor = GpuMonitor()
    try:
        for _request in sys.stdin:
            print(json.dumps(monitor.sample(), allow_nan=False), flush=True)
    except BrokenPipeError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
