#!/usr/bin/env python3
"""Exercise Quest HTTP artifact methods against a real local receiver."""

from __future__ import annotations

import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
received: dict[str, tuple[str, str, object]] = {}


class Handler(BaseHTTPRequestHandler):
    def _receive(self) -> None:
        length = int(self.headers["Content-Length"])
        body = json.loads(self.rfile.read(length))
        received[self.path] = (
            self.command,
            self.headers["Content-Type"],
            body,
        )
        self.send_response(204)
        self.end_headers()

    do_POST = _receive
    do_PUT = _receive

    def log_message(self, *_args: object) -> None:
        pass


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    try:
        subprocess.run(
            [
                "nim",
                "r",
                f"--path:{ROOT / 'src'}",
                str(ROOT / "tests/http_artifact_writer.nim"),
                f"http://{host}:{port}/results",
                f"http://{host}:{port}/replay",
            ],
            cwd=ROOT,
            check=True,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    assert received["/results"] == (
        "PUT",
        "application/json",
        {"mode": "quest", "scores": [1, 2, 3, 4, 5, 6, 7, 8]},
    )
    assert received["/replay"] == (
        "POST",
        "application/json",
        {"mode": "quest", "steps": 3},
    )
    print("Quest HTTP artifact receiver proof passed")


if __name__ == "__main__":
    main()
