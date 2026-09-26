#!/usr/bin/env python3
"""Local static server for the WASM spike.

Serves ./dist-local (your local build) with the cross-origin-isolation headers (COOP/COEP) that WebAssembly
needs and the correct application/wasm MIME — the two things Python's default
http.server doesn't do. No Node required.

    python3 serve.py            # serves ./dist-local on http://localhost:8000
    python3 serve.py 8080 dist  # custom port / directory (dist = the CI build)
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
# Local builds land in dist-local; ./dist is the CI-published bundle.
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else "dist-local"


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    handler = partial(Handler, directory=DIRECTORY)
    print(f"Serving ./{DIRECTORY} at http://localhost:{PORT}  (COOP/COEP on, wasm MIME set)")
    print("Ctrl-C to stop.")
    ThreadingHTTPServer(("127.0.0.1", PORT), handler).serve_forever()
