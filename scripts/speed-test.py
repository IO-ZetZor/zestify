#!/usr/bin/env python3
"""On-demand HTTPS throughput and latency estimates against Cloudflare.

Emit JSON lines for progress, results, and errors. Reuse one TLS connection and
ramp payloads up until a transfer lasts two seconds. Traffic is bounded to about
43 MiB down and 27 MiB up; the entire test has a 45-second deadline.
"""

import http.client
import json
import socket
import statistics
import sys
import time


HOST = "speed.cloudflare.com"
DOWNLOAD_SIZES = [32768, 131072, 524288, 2097152, 8388608, 33554432]
UPLOAD_SIZES = [32768, 131072, 524288, 2097152, 8388608, 16777216]


class SpeedTest:
    def __init__(self, connection=None, clock=time.monotonic):
        self.connection = connection or http.client.HTTPSConnection(HOST, timeout=10)
        self.clock = clock
        self.deadline = None

    def remaining(self):
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise TimeoutError("Speed test timed out")
        return min(10, remaining)

    def transfer(self, direction, size):
        self.connection.timeout = self.remaining()
        if self.connection.sock is not None:
            self.connection.sock.settimeout(self.connection.timeout)
        headers = {"Accept-Encoding": "identity", "Cache-Control": "no-cache",
                   "User-Agent": "Zestify-SpeedTest/1.0"}
        body = None
        if direction == "upload":
            body = b"0" * size
            headers["Content-Type"] = "application/octet-stream"
        path = ("/__up" if direction == "upload" else "/__down") + f"?bytes={size}"
        start = self.clock()
        self.connection.request("POST" if body is not None else "GET", path, body=body, headers=headers)
        if self.connection.sock is not None:
            self.connection.sock.settimeout(self.remaining())
        response = self.connection.getresponse()
        received = 0
        try:
            if response.status != 200:
                raise OSError(f"Test server returned HTTP {response.status}")
            while True:
                if self.connection.sock is not None:
                    self.connection.sock.settimeout(self.remaining())
                else:
                    self.remaining()
                chunk = response.read1(65536)
                if not chunk:
                    break
                received += len(chunk)
                if direction != "upload" and received > size:
                    raise OSError("Invalid test server response")
                if direction == "upload" and received > 65536:
                    raise OSError("Invalid test server response")
        finally:
            response.close()
        elapsed = self.clock() - start
        self.remaining()
        if elapsed <= 0 or (direction != "upload" and received != size):
            raise OSError("Incomplete test server response")
        return elapsed

    def bandwidth(self, direction, sizes):
        speed = 0
        for size in sizes:
            elapsed = self.transfer(direction, size)
            speed = size * 8 / elapsed / 1000000
            if elapsed >= 2:
                break
        return round(speed, 2)

    def run(self, progress):
        self.deadline = self.clock() + 45
        try:
            progress("latency")
            self.transfer("download", 0)  # TLS/connection warm-up is not a ping.
            latency = statistics.median(self.transfer("download", 0) * 1000 for _ in range(3))
            progress("download")
            download = self.bandwidth("download", DOWNLOAD_SIZES)
            progress("upload")
            upload = self.bandwidth("upload", UPLOAD_SIZES)
            return {"type": "result", "download": download, "upload": upload,
                    "latency": round(latency, 1)}
        finally:
            self.connection.close()


def emit(data):
    print(json.dumps(data, allow_nan=False), flush=True)


def main():
    try:
        emit(SpeedTest().run(lambda stage: emit({"type": "progress", "stage": stage})))
    except (TimeoutError, socket.timeout):
        emit({"type": "error", "error": "Speed test timed out. Try again."})
        return 1
    except (OSError, http.client.HTTPException):
        emit({"type": "error", "error": "Cannot reach the test server. Check your connection and try again."})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
