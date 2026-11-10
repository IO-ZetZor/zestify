import importlib.util
import ctypes
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock


REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("gpu_monitor", REPO / "scripts/gpu-monitor.py")
gpu_monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_monitor)


class GpuMonitorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("drm", "pci", "proc", "drivers"):
            (self.root / name).mkdir()
        self.now = 0
        self.run = Mock(side_effect=FileNotFoundError)
        self.monitor = gpu_monitor.GpuMonitor(
            drm=self.root / "drm", pci=self.root / "pci", proc=self.root / "proc",
            names={("8086", "46a3"): "Intel Integrated Graphics"},
            clock=lambda: self.now, run=self.run,
        )

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(value))

    def device(self, bus="0000:00:02.0", vendor="8086", driver="i915", card=1):
        device = self.root / "pci" / bus
        device.mkdir()
        self.write(device / "vendor", "0x" + vendor)
        self.write(device / "device", "0x46a3")
        self.write(device / "class", "0x030000")
        self.write(device / "power/runtime_status", "active")
        driver_path = self.root / "drivers" / driver
        driver_path.mkdir(exist_ok=True)
        (device / "driver").symlink_to(driver_path, target_is_directory=True)
        if card is not None:
            for node in (f"card{card}", f"renderD{128 + card}"):
                (self.root / "drm" / node).mkdir()
                (self.root / "drm" / node / "device").symlink_to(device, target_is_directory=True)
        return device

    def client(self, pid, fd, counters, client="7", bus="0000:00:02.0", capacity=None):
        lines = [f"drm-client-id: {client}", f"drm-pdev: {bus}", "drm-driver: i915"]
        lines += [f"drm-engine-{name}: {value} ns" for name, value in counters.items()]
        lines += [f"drm-engine-capacity-{name}: {value}" for name, value in (capacity or {}).items()]
        self.write(self.root / "proc" / str(pid) / "fdinfo" / str(fd), "\n".join(lines))

    def test_discovers_integrated_and_discrete_and_deduplicates_drm_nodes(self):
        self.device()
        self.device("0000:03:00.0", "1002", "amdgpu", 2)
        # Connector names must not be mistaken for adapters.
        (self.root / "drm/card1-eDP-1").mkdir()
        readings = self.monitor.sample()
        self.assertEqual([gpu["vendor"] for gpu in readings], ["Intel", "AMD"])
        self.assertEqual(readings[0]["name"], "Intel Integrated Graphics")
        self.assertIsNone(readings[0]["utilization"])
        self.assertIsNone(readings[0]["temperature"])

    def test_amd_uses_gpu_local_metrics_without_cpu_temperature(self):
        device = self.device(vendor="1002", driver="amdgpu")
        self.write(device / "gpu_busy_percent", 42)
        self.write(device / "mem_info_vram_used", 1073741824)
        self.write(device / "mem_info_vram_total", 8589934592)
        self.write(device / "hwmon/hwmon0/name", "coretemp")
        self.write(device / "hwmon/hwmon0/temp1_input", 99000)
        self.write(device / "hwmon/hwmon1/name", "amdgpu")
        self.write(device / "hwmon/hwmon1/temp1_input", 56000)
        gpu = self.monitor.sample()[0]
        self.assertEqual(gpu["utilization"], 42)
        self.assertEqual(gpu["temperature"], 56)
        self.assertEqual(gpu["memoryTotal"], 8589934592)
        self.assertEqual(gpu["memoryUsed"], 1073741824)
        self.assertEqual(gpu["source"], "GPU usage")

    def test_fdinfo_deduplicates_across_processes_and_uses_busiest_engine_class(self):
        self.device()
        for pid, fd in ((100, 3), (100, 5), (200, 8)):
            self.client(pid, fd, {"render": 100, "video": 100}, capacity={"video": 2})
        self.assertIsNone(self.monitor.sample()[0]["utilization"])
        self.now = 1000000000
        for pid, fd in ((100, 3), (100, 5), (200, 8)):
            self.client(pid, fd, {"render": 500000100, "video": 800000100}, capacity={"video": 2})
        gpu = self.monitor.sample()[0]
        self.assertEqual(gpu["utilization"], 50)
        self.assertEqual(gpu["source"], "Visible clients")

    def test_fdinfo_sums_distinct_clients_and_ignores_new_and_reset_counters(self):
        self.device()
        self.client(100, 3, {"render": 100}, client="1")
        self.client(200, 3, {"render": 100}, client="2")
        self.monitor.sample()
        self.now = 1000000000
        self.client(100, 3, {"render": 300000100}, client="1")
        self.client(200, 3, {"render": 400000100}, client="2")
        self.client(300, 3, {"render": 9999999999}, client="3")
        self.assertEqual(self.monitor.sample()[0]["utilization"], 70)
        self.now = 2000000000
        self.client(100, 3, {"render": 5}, client="1")
        self.client(200, 3, {"render": 0}, client="2")
        self.assertEqual(self.monitor.sample()[0]["utilization"], 0)

    def test_fdinfo_keeps_devices_separate_and_bounds_usage(self):
        self.device()
        self.device("0000:03:00.0", "8086", "i915", 2)
        self.client(100, 3, {"render": 0})
        self.client(100, 4, {"render": 0}, bus="0000:03:00.0")
        self.monitor.sample()
        self.now = 1000000000
        self.client(100, 3, {"render": 2000000000})
        self.client(100, 4, {"render": 100000000}, bus="0000:03:00.0")
        self.assertEqual([gpu["utilization"] for gpu in self.monitor.sample()], [100, 10])

    def test_fdinfo_temporary_counter_drop_does_not_create_recovery_spike(self):
        self.device()
        self.client(100, 3, {"render": 5000000000})
        self.monitor.sample()
        self.now = 1000000000
        self.client(100, 3, {"render": 100000000})
        self.assertIsNone(self.monitor.sample()[0]["utilization"])
        self.now = 2000000000
        self.client(100, 3, {"render": 5100000000})
        self.assertEqual(self.monitor.sample()[0]["utilization"], 10)

    def test_xe_cycle_counters_use_gpu_time_and_engine_capacity(self):
        self.device(driver="xe")
        path = self.root / "proc/100/fdinfo/3"
        def cycles(busy, total):
            self.write(path, f"drm-driver: xe\ndrm-client-id: 7\ndrm-pdev: 0000:00:02.0\n"
                f"drm-cycles-ccs: {busy}\ndrm-total-cycles-ccs: {total}\ndrm-engine-capacity-ccs: 2\n")
        cycles(100, 1000)
        self.assertIsNone(self.monitor.sample()[0]["utilization"])
        self.now = 1000000000
        cycles(900, 2000)
        self.assertEqual(self.monitor.sample()[0]["utilization"], 40)
        self.now = 2000000000
        cycles(900, 2000)
        self.assertIsNone(self.monitor.sample()[0]["utilization"])

    def test_nvidia_matches_pci_ids_and_keeps_unsupported_values_null(self):
        self.device()
        self.device("0000:03:00.0", "10de", "nvidia", card=None)
        self.run.side_effect = None
        self.run.return_value = subprocess.CompletedProcess([], 0,
            "00000000:03:00.0, NVIDIA GeForce RTX, 61, [N/A], 512, 8192\n")
        readings = self.monitor.sample()
        self.assertIsNone(readings[0]["utilization"])
        self.assertEqual(readings[1]["name"], "NVIDIA GeForce RTX")
        self.assertEqual(readings[1]["utilization"], 61)
        self.assertIsNone(readings[1]["temperature"])
        self.assertEqual(readings[1]["memoryUsed"], 512 * 1048576)
        self.assertIn("--id=0000:03:00.0", self.run.call_args.args[0])

    def test_suspended_gpu_never_reads_metrics_or_invokes_nvidia_smi(self):
        device = self.device(vendor="10de", driver="nvidia")
        self.write(device / "power/runtime_status", "suspended")
        self.write(device / "gpu_busy_percent", 42)
        self.write(device / "mem_info_vram_total", 8589934592)
        gpu = self.monitor.sample()[0]
        self.assertEqual(gpu["status"], "suspended")
        self.assertIsNone(gpu["utilization"])
        self.assertIsNone(gpu["memoryTotal"])
        self.run.assert_not_called()

    def test_missing_tool_timeout_bad_values_and_disappearing_device(self):
        device = self.device(vendor="10de", driver="nvidia")
        for failure in (FileNotFoundError(), subprocess.TimeoutExpired("nvidia-smi", 2)):
            self.run.side_effect = failure
            self.assertIsNone(self.monitor.sample()[0]["utilization"])
        self.write(device / "gpu_busy_percent", "nan")
        self.write(device / "mem_info_vram_used", "-1")
        self.assertIsNone(self.monitor.sample()[0]["memoryUsed"])
        device.rename(self.root / "removed")
        self.assertEqual(self.monitor.sample(), [])

    def test_missing_proc_and_empty_discovery_are_safe(self):
        self.monitor.proc = self.root / "unavailable"
        self.assertEqual(self.monitor.sample(), [])
        self.device()
        self.assertIsNone(self.monitor.sample()[0]["utilization"])

    def test_pci_name_lookup_and_invalid_fdinfo(self):
        database = self.root / "pci.ids"
        database.write_text("8086  Intel Corporation\n\t46a3  Integrated Graphics\n\t\t1028 1234  Subsystem\n")
        self.assertEqual(gpu_monitor.pci_names([database]), {("8086", "46a3"): "Integrated Graphics"})
        for text in ("", "drm-engine-render: 123 ns", "drm-pdev: 0000:00:02.0\ndrm-client-id: 1\ndrm-engine-render: -1 ns"):
            self.assertIsNone(gpu_monitor.parse_fdinfo(text))

    def test_terminating_helper_kills_and_reaps_active_nvidia_query(self):
        self.check_query_teardown()

    def test_killing_helper_also_kills_active_nvidia_query(self):
        self.check_query_teardown(hard=True)

    def check_query_teardown(self, hard=False):
        self.device(vendor="10de", driver="nvidia")
        executable = self.root / "nvidia-smi"
        pidfile = self.root / "query.pid"
        executable.write_text(f"#!{sys.executable}\nimport os, time\n"
            f"open({str(pidfile)!r}, 'w').write(str(os.getpid()))\ntime.sleep(30)\n")
        executable.chmod(0o755)
        harness = self.root / "monitor.py"
        harness.write_text(
            "import importlib.util\nfrom pathlib import Path\n"
            f"spec = importlib.util.spec_from_file_location('gpu', {str(REPO / 'scripts/gpu-monitor.py')!r})\n"
            "module = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(module)\n"
            "original = module.GpuMonitor\n"
            f"module.GpuMonitor = lambda: original(drm=Path({str(self.root / 'drm')!r}), "
            f"pci=Path({str(self.root / 'pci')!r}), proc=Path({str(self.root / 'proc')!r}), names={{}})\n"
            "module.main()\n"
        )
        env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ.get("PATH", ""))
        # Adopt the orphan in the forced-kill test so we can reap it and prove
        # its death, including on test hosts where PID 1 does not reap promptly.
        subreaper = ctypes.c_int()
        if hard:
            self.assertEqual(gpu_monitor.LIBC.prctl(37, ctypes.byref(subreaper), 0, 0, 0), 0)
            self.assertEqual(gpu_monitor.LIBC.prctl(36, 1, 0, 0, 0), 0)
        process = subprocess.Popen([sys.executable, str(harness)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        try:
            process.stdin.write("sample\n")
            process.stdin.flush()
            for _ in range(100):
                if pidfile.is_file() and pidfile.read_text():
                    break
                time.sleep(0.01)
            self.assertTrue(pidfile.is_file(), "NVIDIA query did not start")
            child_pid = int(pidfile.read_text())
            if hard:
                process.kill()
            else:
                process.terminate()
            process.wait(timeout=3)
            self.assertEqual(process.returncode, -9 if hard else 0, process.stderr.read())
            if hard:
                for _ in range(100):
                    reaped, _status = os.waitpid(child_pid, os.WNOHANG)
                    if reaped == child_pid:
                        break
                    time.sleep(0.01)
                self.assertEqual(reaped, child_pid, "NVIDIA query survived helper SIGKILL")
            with self.assertRaises(ProcessLookupError):
                os.kill(child_pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            for stream in (process.stdin, process.stdout, process.stderr):
                stream.close()
            if hard:
                gpu_monitor.LIBC.prctl(36, subreaper.value, 0, 0, 0)


if __name__ == "__main__":
    unittest.main()
