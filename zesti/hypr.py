"""Hyprland IPC client for zesti.

Talks to Hyprland's UNIX socket ($XDG_RUNTIME_DIR/hypr/<signature>/.socket.sock)
using plaintext commands. All socket I/O reads the complete response before
returning, and JSON replies are parsed explicitly.
"""

from __future__ import annotations

import json
import os
import socket
from pathlib import Path


class HyprClient:
    def __init__(self, socket_path: str | os.PathLike[str] | None = None):
        self.socket_path = Path(socket_path) if socket_path is not None else self._default_socket()

    def _default_socket(self) -> Path:
        signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
        if not signature:
            raise FileNotFoundError(
                "HYPRLAND_INSTANCE_SIGNATURE is not set; cannot locate Hyprland socket"
            )
        return Path(runtime) / "hypr" / signature / ".socket.sock"

    def message(self, command: str, *, json_response: bool = True) -> object:
        """Send a Hyprland IPC command and return the complete response.

        With ``json_response`` the reply is parsed as JSON; otherwise the raw
        stripped text is returned.
        """
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(str(self.socket_path))
            s.sendall((command + "\n").encode("utf-8"))
            s.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        text = b"".join(chunks).decode("utf-8").strip()
        if not json_response:
            return text
        return json.loads(text)

    def dispatch(self, name: str, *args: str) -> bool:
        """Issue a Hyprland ``dispatch`` and report whether it succeeded."""
        response = self.message(
            f"dispatch {name} " + " ".join(args), json_response=False
        )
        return str(response).strip().lower() in {"ok", "true", "1", ""}
