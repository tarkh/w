#!/usr/bin/env python3
# mcp-wire.py — drive a real `w-mcp` over stdio JSON-RPC, exactly the way a host
# does: newline-delimited JSON-RPC 2.0, no SDK client in between. `--selftest`
# builds the server but never speaks the protocol; this does, so an SDK major
# that changes the wire (python-mcp 1.x → 2.x moved the whole server package)
# fails here — in the nightly canary, which installs a fresh python-mcp — before
# it fails on a user's machine.
#
# Usage: mcp-wire.py <path/to/w-mcp> [--dump-tools FILE]
# The caller owns the environment (W_MCP_LIB, W_AI_SYS_ROOT, W_AI_STATE_ROOT,
# HOME, W_OS_RELEASE) — see ai-protocol.bats. Prints `ok <check>` per passed
# check; the first failure prints `FAIL <check>: <why>` (+ the server's stderr)
# and exits 1.

import json
import os
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

PARALLEL = 8  # concurrent tools/call — sync tools run in SDK worker threads


class Session:
    """One spawned server: write requests, collect responses by id on a reader
    thread (so several requests can be in flight at once)."""

    def __init__(self, argv, env):
        self.err = tempfile.TemporaryFile()  # noqa: SIM115 — lives as long as the session
        self.p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=self.err, env=env, text=True)
        self.replies, self.cv, self.next_id = {}, threading.Condition(), 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.p.stdout:
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if "id" in msg and ("result" in msg or "error" in msg):
                with self.cv:
                    self.replies[msg["id"]] = msg
                    self.cv.notify_all()

    def send(self, method, params=None, notify=False):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        if not notify:
            self.next_id += 1
            msg["id"] = self.next_id
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()
        return msg.get("id")

    def wait(self, rid, timeout=60):
        with self.cv:
            if not self.cv.wait_for(lambda: rid in self.replies, timeout):
                fail(f"request {rid}", "no reply within timeout", self)
            msg = self.replies.pop(rid)
        if "error" in msg:
            fail(f"request {rid}", f"JSON-RPC error {msg['error']}", self)
        return msg["result"]

    def call(self, method, params=None):
        return self.wait(self.send(method, params))

    def start(self):
        res = self.call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                       "clientInfo": {"name": "w-check", "version": "0"}})
        self.send("notifications/initialized", notify=True)
        return res

    def stderr(self):
        self.err.seek(0)
        return self.err.read().decode(errors="replace")

    def close(self):
        self.p.stdin.close()
        try:
            self.p.wait(10)
        except subprocess.TimeoutExpired:
            self.p.kill()


def fail(check, why, sess=None):
    print(f"FAIL {check}: {why}")
    if sess is not None:
        print("--- w-mcp stderr ---\n" + sess.stderr()[-4000:])
    sys.exit(1)


def text_of(res):
    return "".join(c.get("text", "") for c in res.get("content", []))


def schema_titles(node, path="$"):
    """Paths of pydantic's auto `"title": "<str>"` keys. A *property* named
    `title` maps to a schema dict, never to a string."""
    out = []
    if isinstance(node, dict):
        if isinstance(node.get("title"), str):
            out.append(path)
        for k, v in node.items():
            out += schema_titles(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out += schema_titles(v, f"{path}[{i}]")
    return out


def main():
    server, argv = sys.argv[1], sys.argv[2:]
    dump = argv[argv.index("--dump-tools") + 1] if "--dump-tools" in argv else None
    cmd = [sys.executable, server]
    env = dict(os.environ)

    s = Session(cmd, env)
    init = s.start()
    info = init.get("serverInfo", {})
    want = os.environ.get("W_MCP_EXPECT_VERSION", "")
    if info.get("name") != "w-mcp" or info.get("version") != want:
        fail("initialize", f"serverInfo {info}, expected name w-mcp version {want!r}", s)
    if not init.get("instructions"):
        fail("initialize", "no instructions (identity anchor + catalog) in the handshake", s)
    print(f"ok initialize ({info['name']} {info['version']}, protocol {init.get('protocolVersion')})")

    tools = s.call("tools/list")["tools"]
    if dump:
        Path(dump).write_text(json.dumps(sorted(tools, key=lambda t: t["name"]), indent=1, sort_keys=True))
    if not tools:
        fail("tools/list", "no tools offered", s)
    with_out = [t["name"] for t in tools if t.get("outputSchema")]
    if with_out:
        fail("tools/list", f"outputSchema present on {with_out[:5]} (structured_output=False lost)", s)
    titled = [f"{t['name']}{p[1:]}" for t in tools for p in schema_titles(t.get("inputSchema", {}))]
    if titled:
        fail("tools/list", f"pydantic titles left in schemas: {titled[:5]} (+{len(titled) - 5} more)"
             if len(titled) > 5 else f"pydantic titles left in schemas: {titled}", s)
    print(f"ok tools/list ({len(tools)} tools, no outputSchema, no schema titles)")

    resources = s.call("resources/list")["resources"]
    if not any(r["uri"] == "w-knowledge://AGENTS.md" for r in resources):
        fail("resources/list", f"w-knowledge://AGENTS.md missing among {len(resources)}", s)
    print(f"ok resources/list ({len(resources)} resources)")

    prompts = sorted(p["name"] for p in s.call("prompts/list")["prompts"])
    if "diagnose_system" not in prompts:
        fail("prompts/list", f"diagnose_system missing in {prompts}", s)
    print(f"ok prompts/list ({len(prompts)} prompts)")

    res = s.call("tools/call", {"name": "w_time_status", "arguments": {}})
    if res.get("isError") or not text_of(res):
        fail("tools/call", f"w_time_status: {res}", s)
    print("ok tools/call w_time_status")
    # The hostname comes from the kernel: W ships no `hostname` binary (inetutils).
    prof = text_of(s.call("tools/call", {"name": "w_machine_profile", "arguments": {}}))
    if not prof.startswith("Hostname: ") or prof.startswith("Hostname: ("):
        fail("tools/call", f"w_machine_profile: {prof.splitlines()[:1]}", s)
    print("ok tools/call w_machine_profile")

    # Concurrency: Cyrillic task texts (no digits) all slugify to the same base
    # ("fact"), so every call races for the next free slug — each must still land
    # in its own file.
    ids = [s.send("tools/call", {"name": "w_task_add", "arguments": {"content": f"задача {c}"}})
           for c in "абвгдежз"[:PARALLEL]]
    replies = [text_of(s.wait(i)) for i in ids]
    slugs = {r.split("'")[1] for r in replies if r.startswith("task added '")}
    if len(slugs) != PARALLEL:
        fail("parallel tools/call", f"{PARALLEL} concurrent w_task_add → {len(slugs)} distinct tasks: {replies}", s)
    listed = text_of(s.call("tools/call", {"name": "w_task_list", "arguments": {}})).splitlines()
    if len(listed) != PARALLEL:
        fail("parallel tools/call", f"w_task_list shows {len(listed)} tasks, expected {PARALLEL}: {listed}", s)
    print(f"ok parallel tools/call ({PARALLEL} concurrent w_task_add → {PARALLEL} tasks)")
    s.close()

    # A tool that crashes must tell the model why: an unwritable state root makes
    # the memory store's mkdir raise. The SDK alone would mask it as the bare
    # "Error executing tool w_task_add"; core.tool() forwards the reason.
    s = Session(cmd, {**env, "W_AI_STATE_ROOT": "/dev/null/w-mcp-state"})
    s.start()
    res = s.call("tools/call", {"name": "w_task_add", "arguments": {"content": "x"}})
    if not res.get("isError") or "Not a directory" not in text_of(res):
        fail("tool error", f"expected isError with the cause, got {res}", s)
    print(f"ok tool error ({text_of(res)[:80]})")
    s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
