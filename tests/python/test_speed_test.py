import importlib.util
import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch


REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("speed_test", REPO / "scripts/speed-test.py")
speed_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(speed_test)


class Clock:
    now = 0

    def __call__(self):
        return self.now


class Response:
    def __init__(self, size, clock, slow=False, status=200):
        self.remaining = size
        self.clock = clock
        self.slow = slow
        self.status = status
        self.closed = False

    def read1(self, size):
        if self.slow:
            self.clock.now += 20
        count = min(size, self.remaining)
        self.remaining -= count
        return b"0" * count

    def close(self):
        self.closed = True


class Connection:
    def __init__(self, clock, durations, status=200, short=False, slow=False):
        self.clock = clock
        self.durations = iter(durations)
        self.status = status
        self.short = short
        self.slow = slow
        self.sock = Mock()
        self.requests = []
        self.responses = []
        self.closed = False

    def request(self, method, path, body, headers):
        self.requests.append((method, path, body, headers))

    def getresponse(self):
        self.clock.now += next(self.durations)
        method, path, _body, _headers = self.requests[-1]
        size = int(path.partition("bytes=")[2]) if method == "GET" else 4
        if self.short and size:
            size -= 1
        response = Response(size, self.clock, status=self.status, slow=self.slow)
        self.responses.append(response)
        return response

    def close(self):
        self.closed = True


class SpeedTestTest(unittest.TestCase):
    def test_latency_excludes_warmup_and_bandwidth_has_correct_units(self):
        clock = Clock()
        connection = Connection(clock, [2, 0.1, 0.3, 0.2, 2.5, 2.5])
        test = speed_test.SpeedTest(connection, clock)
        stages = []
        result = test.run(stages.append)
        self.assertEqual(stages, ["latency", "download", "upload"])
        self.assertEqual(result, {"type": "result", "download": 0.1, "upload": 0.1, "latency": 200})
        self.assertEqual(connection.requests[0][1], "/__down?bytes=0")
        self.assertEqual(connection.requests[-1][0:2], ("POST", "/__up?bytes=32768"))
        self.assertEqual(len(connection.requests[-1][2]), 32768)
        self.assertEqual(connection.requests[-1][3]["Accept-Encoding"], "identity")
        self.assertTrue(connection.closed)
        self.assertTrue(all(response.closed for response in connection.responses))

    def test_payload_ramp_stops_after_sustained_transfer(self):
        clock = Clock()
        connection = Connection(clock, [0.5, 2])
        test = speed_test.SpeedTest(connection, clock)
        test.deadline = 45
        self.assertEqual(test.bandwidth("download", [1000000, 2000000, 4000000]), 8)
        self.assertEqual(len(connection.requests), 2)

    def test_high_speed_connections_still_have_finite_byte_bounds(self):
        clock = Clock()
        connection = Connection(clock, [0.001] * 20)
        test = speed_test.SpeedTest(connection, clock)
        test.run(lambda _stage: None)
        down = sum(int(path.partition("bytes=")[2]) for method, path, _, _ in connection.requests if method == "GET")
        up = sum(len(body) for method, _, body, _ in connection.requests if method == "POST")
        self.assertEqual(down, sum(speed_test.DOWNLOAD_SIZES))
        self.assertEqual(up, sum(speed_test.UPLOAD_SIZES))
        self.assertLess(down, 43 * 1048576)
        self.assertLess(up, 27 * 1048576)

    def test_http_failure_or_truncated_download_is_not_a_success(self):
        for options in ({"status": 503}, {"short": True}):
            clock = Clock()
            connection = Connection(clock, [0.1] * 10, **options)
            test = speed_test.SpeedTest(connection, clock)
            with self.assertRaises(OSError):
                test.run(lambda _stage: None)
            self.assertTrue(connection.closed)

    def test_slow_stream_observes_total_deadline_and_closes_response(self):
        clock = Clock()
        connection = Connection(clock, [0.1], slow=True)
        test = speed_test.SpeedTest(connection, clock)
        test.deadline = 10
        with self.assertRaises(TimeoutError):
            test.transfer("download", 32768)
        self.assertTrue(connection.responses[0].closed)

    def test_failed_connection_closes_and_main_reports_actionable_error(self):
        connection = Mock()
        connection.request.side_effect = OSError("offline")
        test = speed_test.SpeedTest(connection)
        with self.assertRaises(OSError):
            test.run(lambda _stage: None)
        connection.close.assert_called_once()
        for error, message in ((TimeoutError(), "timed out"), (OSError(), "Check your connection")):
            with patch.object(speed_test.SpeedTest, "run", side_effect=error), redirect_stdout(io.StringIO()) as output:
                self.assertEqual(speed_test.main(), 1)
            data = json.loads(output.getvalue())
            self.assertEqual(data["type"], "error")
            self.assertIn(message, data["error"])


if __name__ == "__main__":
    unittest.main()
