#!/usr/bin/env python3
"""vm/fault-mirror.py — the stalled-mirror endpoint behind the Ф.4 e2e scenario.

Host-side, dev-only. Runs on the QEMU host and is reachable from the guest at
10.0.2.2:<port> over user-mode networking, exactly like the SOCKS proxy the AI
tests use. Nothing about it ever reaches a built ISO or an installed machine.

WHAT IT REPRODUCES, AND WHY THIS SHAPE

The failure that broke three release-gate runs in a row was a mirror that
connects instantly, answers 200 and then serves <1 byte/s for twenty-five
minutes. Reproducing it by *refusing* connections would be a different failure
class entirely (curl rc=7, "the host is down"), so this stalls instead: headers
out, then not one byte, which is what makes curl and pacman hit their own
low-speed timeouts (rc=28, "Operation too slow. Less than 1 bytes/sec").
Deliberately no Content-Length — announcing a size the body never reaches makes
pacman say "Maximum file size exceeded", a signature the seam classifies as
unknown and correctly refuses to retry. Measured both ways before choosing.

Poisoning ONE entry is not enough, and that is a measurement, not an opinion:
against a real pacman, a stalled head with healthy mirrors below costs ~12 s and
the transaction still succeeds (rc=0) because pacman walks the rest of the list
per file. Only exhausting every server for a file produces the failure the seam
exists to survive:

    error: failed retrieving file 'x.pkg.tar.zst' from HOST : Operation too slow
    warning: too many errors from HOST, skipping for the remainder…
    warning: failed to retrieve some files
    error: failed to commit transaction (download library error)

So the arming side (devtools/usr/local/bin/w-fault-arm) routes the WHOLE ranked
list through this relay rather than prepending one bad entry. Depth, order and
the identity of every mirror reflector chose are preserved — each Server line
keeps its own upstream, carried base64url-encoded in the first path segment —
and only the transport is poisoned. Once the sick window closes, every request
is redirected to the upstream the entry always pointed at, so the install
finishes against the real mirrors.

ONE PORT PER ENTRY, which is not cosmetic. pacman's identity for a mirror is
host:port, and both its own fallback and the seam's demotion key on that string.
Serving the whole list from a single port makes all twenty entries one host, so
"too many errors from X" skips the entire pool at once (measured: the attempt
fails in ~30 s no matter how deep the list is) and demoting X moves every entry
together, leaving the same poisoned host at the head — a run that looks green
while proving nothing about either mechanism. A port per entry makes them twenty
distinct hosts again: pacman walks the list the way it would in the field, and
the seam has real, separate names to extract and demote.

THE SICK WINDOW is wall-clock and armed at the moment of injection, not a
request counter: a counter cannot tell "still inside the failing attempt" from
"this is the retry", and healing mid-attempt would silently make the transaction
succeed and the assertion vacuous. Cost is bounded and predictable — pacman
gives each stalled server 10 s, so one failing attempt is roughly
depth × 10 s — which is what the window is calibrated against.

Usage:
    vm/fault-mirror.py --port 18080 --ports 24 [--sick-seconds 0] [--hold 45]

    GET /__ctl/state             → JSON: armed, remaining seconds, counters
    GET /__ctl/sick?seconds=N    → (re)arm the sick window for N seconds
    GET /__ctl/heal              → close the window now
    GET /<b64url-upstream>/<path> → stalled while sick, 302 to upstream when healthy

The sick window and the counters are process-wide, so control on any of the
ports speaks for all of them. Control is unauthenticated by design: this binds
on a developer's machine for the length of one test run and speaks to a
throwaway VM.
"""

import argparse
import base64
import binascii
import json
import select
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE_LOCK = threading.Lock()
STATE = {
    "sick_until": 0.0,   # epoch seconds; <= now means healthy
    "stalled": 0,        # requests held at 0 B/s
    "proxied": 0,        # requests redirected upstream
    "hosts": {},         # ":port" → stalled count, to prove which entries were hit
}
HOLD_SECONDS = 45.0


def _decode_upstream(segment):
    """First path segment → the upstream prefix it encodes (base64url, unpadded)."""
    pad = "=" * (-len(segment) % 4)
    raw = base64.urlsafe_b64decode(segment + pad)
    return raw.decode("utf-8")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "w-fault-mirror/1"

    # One line per request would drown the harness log in a 20-deep stalled list;
    # the counters in /__ctl/state are the record that matters.
    def log_message(self, *args):
        pass

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _control(self, parsed):
        action = parsed.path[len("/__ctl/"):]
        query = parse_qs(parsed.query)
        with STATE_LOCK:
            if action == "sick":
                seconds = float(query.get("seconds", ["300"])[0])
                STATE["sick_until"] = time.time() + seconds
                STATE["stalled"] = 0
                STATE["proxied"] = 0
                STATE["hosts"] = {}
            elif action == "heal":
                STATE["sick_until"] = 0.0
            elif action != "state":
                self.send_error(404, "unknown control action")
                return
            remaining = max(0.0, STATE["sick_until"] - time.time())
            payload = {
                "sick": remaining > 0,
                "remaining_seconds": round(remaining, 1),
                "stalled": STATE["stalled"],
                "proxied": STATE["proxied"],
                "hosts": dict(STATE["hosts"]),
            }
        self._json(payload)

    def _stall(self, port_key):
        """Answer 200, then serve nothing at all until the peer gives up."""
        with STATE_LOCK:
            STATE["stalled"] += 1
            STATE["hosts"][port_key] = STATE["hosts"].get(port_key, 0) + 1
        try:
            # No Content-Length and no chunked framing: the body is "until close",
            # so the client's own low-speed timeout is what ends this, which is
            # precisely the real mirror's behaviour.
            self.wfile.write(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            self.wfile.flush()
        except OSError:
            return
        # Hold the connection, but notice a peer that hung up so threads are
        # reclaimed promptly instead of accumulating one per stalled download.
        deadline = time.time() + HOLD_SECONDS
        while time.time() < deadline:
            readable, _, _ = select.select([self.connection], [], [], 1.0)
            if readable:
                return
        self.close_connection = True

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/__ctl/"):
            self._control(parsed)
            return

        segments = parsed.path.lstrip("/").split("/", 1)
        if len(segments) != 2 or not segments[1]:
            self.send_error(400, "expected /<b64url-upstream>/<path>")
            return
        try:
            upstream = _decode_upstream(segments[0])
        except (binascii.Error, UnicodeDecodeError, ValueError):
            self.send_error(400, "first path segment is not a base64url upstream")
            return

        with STATE_LOCK:
            sick = STATE["sick_until"] > time.time()
        port_key = str(self.server.server_address[1])
        if sick:
            self._stall(port_key)
            return

        with STATE_LOCK:
            STATE["proxied"] += 1
        target = upstream.rstrip("/") + "/" + segments[1]
        self.send_response(302)
        self.send_header("Location", target)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # pacman only ever GETs; HEAD keeps a stray probe from hanging the socket.
    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    global HOLD_SECONDS
    ap = argparse.ArgumentParser(description="stalled-mirror fault endpoint (dev-only)")
    ap.add_argument("--port", type=int, default=18080, help="first port of the range")
    ap.add_argument("--ports", type=int, default=24,
                    help="how many consecutive ports to bind — one per mirrorlist entry, "
                         "so each entry is a distinct host in pacman's eyes")
    ap.add_argument("--sick-seconds", type=float, default=0.0,
                    help="arm the sick window immediately for N seconds (0 = start healthy)")
    ap.add_argument("--hold", type=float, default=45.0,
                    help="max seconds to hold one stalled connection")
    args = ap.parse_args()

    HOLD_SECONDS = args.hold
    if args.sick_seconds > 0:
        STATE["sick_until"] = time.time() + args.sick_seconds

    servers = []
    for port in range(args.port, args.port + args.ports):
        server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
        server.daemon_threads = True
        servers.append(server)
        threading.Thread(target=server.serve_forever, daemon=True).start()

    last = args.port + args.ports - 1
    print(f"fault-mirror: listening on 0.0.0.0:{args.port}-{last} "
          f"(sick for {args.sick_seconds:.0f}s, hold {args.hold:.0f}s)", flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
    finally:
        for server in servers:
            server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
