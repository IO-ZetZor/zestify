"""Hyprland IPC client tests for zesti.

Uses fake UNIX sockets so no real Hyprland instance is required.
"""

import json
import os
import socket
import tempfile
import threading
import unittest
from pathlib import Path

from zesti.hypr import HyprClient


class FakeHyprland:
    """A minimal fake Hyprland IPC socket for unit tests."""

    def __init__(self, responses: dict[str, str]):
        self.responses = {k: v.encode() for k, v in responses.items()}
        self.sock_path: str | None = None
        self._server = None
        self._thread = None

    def start(self) -> str:
        import socketserver

        class Handler(socketserver.BaseRequestHandler):
            def handle(self):
                data = b""
                while True:
                    chunk = self.request.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                server = self.server  # type: ignore[attr-defined]
                server.last_command = data.decode().strip()
                resp = server.responses.get(server.last_command, b"unknown command")
                self.request.sendall(resp)
                self.request.shutdown(socket.SHUT_WR)

        class Server(socketserver.UnixStreamServer):
            last_command: str | None = None

        fd, path = tempfile.mkstemp(suffix=".sock")
        os.close(fd)
        os.unlink(path)
        server = Server(path, Handler)
        server.responses = self.responses
        self._server = server
        self.sock_path = path
        self._thread = threading.Thread(target=server.serve_forever, daemon=True)
        self._thread.start()
        return path

    def stop(self):
        if self._server:
            self._server.shutdown()
            self._server.server_close()
        if self.sock_path and os.path.exists(self.sock_path):
            os.unlink(self.sock_path)


class HyprClientTest(unittest.TestCase):
    def setUp(self):
        self.fake = FakeHyprland({
            "clients": json.dumps([{"address": "0x1", "class": "firefox"}]),
            "monitors": json.dumps([{"name": "eDP-1"}]),
            "dispatch workspace 2": "ok",
            "dispatch togglespecialworkspace magic": "ok",
        })
        self.fake.start()

    def tearDown(self):
        self.fake.stop()

    def client(self) -> HyprClient:
        return HyprClient(socket_path=self.fake.sock_path)

    def test_message_reads_complete_json_response(self):
        clients = self.client().message("clients", json_response=True)
        self.assertEqual(clients, [{"address": "0x1", "class": "firefox"}])

    def test_message_json_prefix_parsing(self):
        monitors = self.client().message("monitors", json_response=True)
        self.assertEqual(monitors, [{"name": "eDP-1"}])

    def test_message_plain_response(self):
        resp = self.client().message("dispatch workspace 2", json_response=False)
        self.assertEqual(resp, "ok")

    def test_dispatch_returns_bool(self):
        self.assertTrue(self.client().dispatch("workspace", "2"))

    def test_dispatch_formats_name_and_args(self):
        self.client().dispatch("togglespecialworkspace", "magic")
        self.assertEqual(self.fake._server.last_command, "dispatch togglespecialworkspace magic")

    def test_missing_socket_raises(self):
        with self.assertRaises(FileNotFoundError):
            HyprClient(socket_path="/tmp/does-not-exist.sock").message("clients")


if __name__ == "__main__":
    unittest.main()
