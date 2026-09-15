#!/usr/bin/env python3
"""Static file server for the StyleLink web preview with aggressive no-cache
headers.

WHY: python -m http.server sends caching-friendly responses (Last-Modified,
no Cache-Control), which let browsers and service workers pin stale bundles
after rebuilds. This server forces every response to be revalidated, so a
reload always shows the latest build/web content.

USAGE:
  python tool/serve_preview.py [port] [directory]

Defaults: port 9091, directory ../build/web relative to this file.
"""

import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

NO_CACHE_HEADERS = [
    ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
    ("Pragma", "no-cache"),
    ("Expires", "0"),
]


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        for name, value in NO_CACHE_HEADERS:
            self.send_header(name, value)
        # Never advertise SW support niceties; keep responses lean.
        super().end_headers()

    def log_message(self, fmt, *args):  # keep default logging (goes to stderr)
        super().log_message(fmt, *args)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9091
    directory = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "build", "web"))
    )
    if not os.path.isdir(directory):
        print(f"ERROR: directory not found: {directory}", file=sys.stderr)
        sys.exit(1)

    handler = lambda *args, **kwargs: NoCacheHandler(*args, directory=directory, **kwargs)
    server = ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(f"Serving {directory} on http://127.0.0.1:{port} (Cache-Control: no-store)")
    server.serve_forever()


if __name__ == "__main__":
    main()
