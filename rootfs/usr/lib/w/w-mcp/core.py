# w-mcp core — shared SDK for the W MCP server's domain modules.
#
# The orchestrator (/usr/bin/w-mcp) is a thin hub: it creates the FastMCP
# server, then loads every modules/<domain>.py and calls its register(mcp). The
# real per-domain tool logic lives in those modules; the helpers they all share
# (command runner, knowledge/actuation plumbing, the tool() registration wrapper)
# live here — exactly the w-style split (bin/w-style orchestrator + lib/core.sh
# SDK + modules/<band>-<name>/module.sh). See ai-integration.md.
#
# This module is import-only: it never creates the FastMCP instance (the hub owns
# it and passes it to tool()), so it has no dependency on the mcp package and can
# be imported and unit-tested on its own.

import fnmatch
import grp
import os
import pwd
import re
import subprocess
from pathlib import Path

# ── Knowledge roots ───────────────────────────────────────────────────────────
# System knowledge ships read-only; the per-user overlay may add or shadow files
# by the same relative path. User wins, matching the rest of W (themes, skills).
# W_AI_SYS_ROOT lets tooling/tests point at an alternate tree; defaults to the
# shipped location.
SYS_ROOT = Path(os.environ.get("W_AI_SYS_ROOT", "/usr/share/w/ai"))
USER_ROOT = Path(os.path.expanduser("~/.config/w/ai"))
KNOWLEDGE_ROOTS = [USER_ROOT, SYS_ROOT]  # precedence order: first match wins

# ── Memory store ──────────────────────────────────────────────────────────────
# The agent's persistent, cross-host memory (see ai-integration.md §8). Facts are
# markdown files, one fact per file (same pattern W's own library uses); a SQLite
# FTS5 table indexes them for token-cheap recall. The *files* are the source of
# truth — the db is a rebuildable index kept in sync by mtime, so edits made by
# hand or by another host are picked up. Deliberately NOT Goose's memory
# extension: that one is host-local and dumps every memory into every prompt,
# which breaks W's cross-agent + retrieval-discipline principles. Semantic
# (vector) recall via sqlite-vec + local embeddings is a future opt-in layer on
# top of this FTS5 baseline; the baseline needs no packages beyond stdlib sqlite3.
STATE_ROOT = Path(os.environ.get("W_AI_STATE_ROOT", os.path.expanduser("~/.local/state/w/ai")))
MEMORY_DIR = STATE_ROOT / "memory"
MEMORY_DB = STATE_ROOT / "memory.db"
MEM_TYPES = ("user", "feedback", "project", "reference", "task")

# ── Tier-2 actuation (privileged, via polkit) ─────────────────────────────────
# Tier-2 tools never gain privilege in-process. They exec the root dispatcher
# through pkexec; the com.w.ai.actuate polkit action makes hyprpolkitagent prompt
# the user and journald audits every run (see ai-integration.md §3). Which tools
# are *offered* is gated by per-tool switches in ai.conf (W_AI_TOOL_*): a disabled
# tool still registers (so the model can see it) but refuses with a hint to enable
# it, instead of failing opaquely.
ACTUATE = "/usr/lib/w/w-ai-actuate"

# ── Layered configuration (mirror of /usr/lib/w/w-conf-lib.sh) ──────────
# The bash library is the reference implementation; this is its Python twin, kept
# honest by a contract test in check.sh that runs both over one fixture tree and
# diffs the output. A twin (rather than shelling out to `w-conf`) because the
# tool gate below calls this on every tool invocation in a long-lived server —
# a fork per key would be pure waste. Layers, low → high priority:
#
#   vendor  /usr/share/w/defaults/<s>.conf     (phase 2+)
#   site-default  /etc/w/site-defaults.d/<s>.conf   fleet advice (phase 5)
#   system  /etc/w/<s>.conf                    the local admin
#   user    ~/.config/w/<s>.conf               the user
#   user-features  ~/.config/w/ai-features.conf   ai only: survives `w-ai profile
#           use`, which rewrites the user file wholesale
#   policy  /etc/w/policy.d/<s>.conf           fleet mandate (phase 5)
#
# Every layer also reads <file>.d/*.conf, sorted, later file winning.
#
# The roots are resolved per call, not at import: WCONF_ETC / WCONF_VENDOR_DIR /
# WCONF_HOME are the same test seams the bash library exposes, and a long-lived
# server that cached them at import could never be pointed at a fixture tree.


def _conf_roots():
    etc = Path(os.environ.get("WCONF_ETC", "/etc/w"))
    vendor = Path(os.environ.get("WCONF_VENDOR_DIR", "/usr/share/w/defaults"))
    home = os.environ.get("WCONF_HOME")
    if home:
        user = Path(home) / ".config" / "w"
    else:
        user = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "w"
    return etc, vendor, user


def conf_layers(subsys):
    """Ordered (layer, base file) pairs for one subsystem, low → high priority."""
    etc, vendor, udir = _conf_roots()
    layers = [
        ("vendor", vendor / f"{subsys}.conf"),
        ("site-default", etc / "site-defaults.d" / f"{subsys}.conf"),
        ("system", etc / f"{subsys}.conf"),
        ("user", udir / f"{subsys}.conf"),
    ]
    if subsys == "ai":
        layers.append(("user-features", udir / "ai-features.conf"))
    layers.append(("policy", etc / "policy.d" / f"{subsys}.conf"))
    return layers


def _conf_scalar(raw):
    """Value semantics identical to the bash reader — and to `source` itself:
    quotes take the quoted string, an unquoted '#' starts a comment only when
    whitespace precedes it (so MODEL=gpt#4 keeps its hash)."""
    v = raw
    if v[:1] in ('"', "'"):
        q = v[0]
        end = v.find(q, 1)
        return v[1:end] if end != -1 else v[1:]
    m = re.search(r"[ \t]#", v)
    if m:
        v = v[: m.start()]
    return v.strip()


def _conf_files(base):
    """A layer's files: the base file, then its .d/*.conf in sorted order."""
    out = []
    if base.is_file():
        out.append(base)
    dropin = Path(str(base) + ".d")
    if dropin.is_dir():
        out.extend(sorted(p for p in dropin.glob("*.conf") if p.is_file()))
    return out


def conf_scope_of(scopes, key):
    """Declared scope of one key: an exact row wins, else a glob row (`DNS_*`)
    covers a whole catalog. Mirrors _wconf_key_scope in the bash reader."""
    hit = scopes.get(key)
    if hit:
        return hit
    for pat, scope in scopes.items():
        if "*" in pat and fnmatch.fnmatchcase(key, pat):
            return scope
    return ""


def conf_scopes(subsys):
    """{key: system|user|both} from <subsys>.schema — which layer may decide a
    key. Absent schema = everything unconstrained (a subsystem not split yet).
    A key may be a glob (see conf_scope_of)."""
    scopes = {}
    _etc, vendor, _udir = _conf_roots()
    f = vendor / f"{subsys}.schema"
    try:
        text = f.read_text(errors="replace")
    except OSError:
        return scopes
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1] in ("system", "user", "both"):
            scopes[parts[0]] = parts[1]
    return scopes


def conf_read(subsys):
    """Effective config for one subsystem as {key: (value, layer)}."""
    conf = {}
    scopes = conf_scopes(subsys)
    for layer, base in conf_layers(subsys):
        for f in _conf_files(base):
            try:
                text = f.read_text(errors="replace")
            except OSError:
                continue
            for line in text.splitlines():
                line = line.lstrip()
                if not line or line.startswith("#"):
                    continue
                m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
                if not m:
                    continue  # lenient, exactly like the bash reader
                key = m.group(1)
                # Scope enforcement, same rule as the bash reader: a user-scope
                # file may not decide root-domain policy.
                if layer in ("user", "user-features") and conf_scope_of(scopes, key) == "system":
                    continue
                conf[key] = (_conf_scalar(m.group(2)), layer)
    return conf


def conf_get(subsys, key, default=""):
    """Effective value of one key (default only when no layer defines it)."""
    hit = conf_read(subsys).get(key)
    return hit[0] if hit else default


def conf_policy_block(subsys, key, what):
    """Refusal text when fleet policy owns `key`, else "".

    A Tier-2 setter whose value is pinned by /etc/w/policy.d cannot succeed: the
    W setter behind the capability refuses the write (w-conf-lib). Firing pkexec
    anyway would raise an auth prompt, make the user authenticate, and THEN fail —
    so the tools ask here first and explain instead. Same reason the Hub greys a
    locked control out rather than letting the click through."""
    hit = conf_read(subsys).get(key)
    if not hit or hit[1] != "policy":
        return ""
    value, _layer = hit
    return (f"({what} is set by site policy on this machine (/etc/w/policy.d/{subsys}.conf) "
            f"and pinned to '{value}'. A local change would be refused — this is a fleet "
            f"decision, so it has to be changed by whoever manages the site policy.)")


def kv_file(path, key, default="?"):
    """One key out of a single flat KEY=value file that is NOT part of W's layered
    namespace (/etc/locale.conf, /etc/vconsole.conf — systemd's, not ours). Same
    value semantics, no layering."""
    try:
        for line in Path(path).read_text(errors="replace").splitlines():
            line = line.lstrip()
            m = re.match(rf"{re.escape(key)}=(.*)$", line)
            if m:
                return _conf_scalar(m.group(1))
    except OSError:
        pass
    return default

# ── Tool profile ──────────────────────────────────────────────────────────────
# Two profiles decide how much of the tool surface is offered to the model:
#   full     — every tool (default; frontier/provider models tool-call reliably).
#   minimal  — Tier-0 reads + memory + a couple safe Tier-1 actions. A smaller
#              surface that small local models (e.g. Qwen3 4B via Ollama) drive far
#              more reliably: their tool-calling degrades sharply past ~15-20 tools.
# The orchestrator sets PROFILE (via resolve_profile) before loading modules, so
# tool() below can skip registering out-of-profile tools. Every tool is still
# recorded in REGISTRY regardless — only whether it is *offered* changes.
PROFILE = "full"

# ── Tool registry ─────────────────────────────────────────────────────────────
# Every tool registers through tool() below, which records its domain (the owning
# skill, or "shared") and whether it belongs to the minimal profile. The registry
# is the single machine-readable map of tool → domain → profile: --selftest reads
# it, the profile gate reads `minimal`, and the dev drift checker cross-links it
# against the shipped skills.
REGISTRY = []  # list of {"name": str, "domain": str, "minimal": bool, "fn": callable}
# `fn` is the undecorated function object — lets contract.py introspect real
# signatures/source (schema validity, the Tier-2 pkexec-guard invariant) without
# needing the `mcp` package at all.


def resolve_profile():
    """Resolve the active MCP tool profile from ai.conf. An explicit
    MCP_PROFILE=full|minimal wins; otherwise HOST=local defaults to minimal (small
    local models tool-call poorly with a large surface), and everything else to full."""
    conf = _ai_conf()
    p = conf.get("MCP_PROFILE", "").strip().lower()
    if p in ("full", "minimal"):
        return p
    if conf.get("HOST", "").strip().lower() == "local":
        return "minimal"
    return "full"


def tool(mcp, *, domain, minimal=False):
    """Decorator: register a function as an MCP tool and record its metadata.

    Wraps FastMCP's own mcp.tool() (so the wire schema is identical — same
    signature + docstring) and appends {name, domain, minimal} to REGISTRY. In the
    minimal profile, a tool not flagged minimal is recorded but NOT offered.
    Use as `@tool(mcp, domain=DOMAIN, minimal=True)` inside a module's register().
    """
    def deco(fn):
        REGISTRY.append({"name": fn.__name__, "domain": domain, "minimal": minimal, "fn": fn})
        if PROFILE == "minimal" and not minimal:
            return fn  # out of profile: recorded, but not exposed to the host
        return mcp.tool()(fn)
    return deco


# ── Prompt registry ───────────────────────────────────────────────────────────
# MCP Prompts are parameterized *task recipes* the server offers to any host — the
# cross-host, protocol-native replacement for platform-specific recipe files (e.g.
# goose recipes, which only goose can read). A host lists them and runs one on
# demand; unlike tool schemas they cost nothing until pulled, so they are NOT gated
# by PROFILE. A prompt lives in its domain module beside the tools it drives.
PROMPTS = []  # list of {"name": str, "domain": str}


def prompt(mcp, *, domain):
    """Decorator: register an MCP prompt (a host-agnostic task recipe) and record
    its domain. Wraps FastMCP's mcp.prompt(); use as `@prompt(mcp, domain=DOMAIN)`
    inside a module's register(), on a function returning the recipe text."""
    def deco(fn):
        PROMPTS.append({"name": fn.__name__, "domain": domain})
        return mcp.prompt()(fn)
    return deco


# ── Shared helpers ────────────────────────────────────────────────────────────
def run(cmd, timeout=20):
    """Run a read-only command, return combined stdout/stderr as text.

    Never raises: a missing tool or non-zero exit is reported inline so the
    model sees the real failure instead of the server crashing.
    """
    try:
        p = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=False
        )
    except FileNotFoundError:
        return f"(command not found: {cmd[0]})"
    except subprocess.TimeoutExpired:
        return f"(timed out after {timeout}s: {' '.join(cmd)})"
    out = (p.stdout or "") + (p.stderr or "")
    out = out.strip()
    if p.returncode != 0 and not out:
        out = f"(exit {p.returncode}: {' '.join(cmd)})"
    return out or "(no output)"


def resolve(rel):
    """Resolve a knowledge-relative path against the overlay roots (user wins)."""
    for root in KNOWLEDGE_ROOTS:
        p = root / rel
        if p.is_file():
            return p
    return None


def _ai_conf():
    """Flat {key: value} view of the `ai` subsystem across every layer.

    Kept as a named function because modules import it and the contract selftest
    patches it; the layering itself lives in conf_read (one reader for every
    subsystem, mirroring w-conf-lib.sh)."""
    return {k: v for k, (v, _layer) in conf_read("ai").items()}


def _tool_on(name, default="on"):
    """Is Tier-2 tool W_AI_TOOL_<name> enabled in ai.conf?"""
    return _ai_conf().get(f"W_AI_TOOL_{name}", default).lower() in ("on", "1", "yes", "true")


def _disabled_msg(tool, switch):
    return (
        f"({tool} is disabled. To allow it, set {switch}=on in "
        f"~/.config/w/ai.conf (or /etc/w/ai.conf), then retry — it is a privileged "
        f"action gated behind a polkit prompt. Tell the user to flip this switch.)"
    )


def _is_admin():
    """Is the user this server runs as an administrator (member of `wheel`)?

    Twin of w_is_admin in /usr/lib/w/w-priv-lib.sh — same definition (what
    %wheel in sudoers grants and what polkit's Arch default calls an admin), read
    the same way for the AI path. Pure stdlib, no subprocess: this sits in front of
    every Tier-2 tool in a long-lived server. NOT a security boundary (polkit still
    is), so it fails OPEN on an odd machine with no `wheel` group — see the header
    of w-priv-lib.sh."""
    if os.geteuid() == 0:
        return True
    try:
        pw = pwd.getpwuid(os.getuid())
        wheel = grp.getgrnam("wheel").gr_gid
    except KeyError:
        return True
    return wheel in os.getgrouplist(pw.pw_name, pw.pw_gid)


def _not_admin_msg():
    return (
        "(this machine's administrators are the members of the 'wheel' group, and "
        "this user is not one of them — so W did not raise the authorization prompt "
        "and nothing was changed. Tell the user to ask an administrator of this "
        "machine to run it; there is no workaround from here.)"
    )


def _actuate(cap, *args, timeout=300):
    """Run a Tier-2 capability through pkexec + the com.w.ai.actuate polkit action.
    hyprpolkitagent prompts the user and journald audits it. Returns the command
    output, or a clear message if the dispatcher is missing / polkit denies."""
    # One gate for every Tier-2 tool: a non-admin cannot answer the polkit prompt
    # (it asks for an admin's password), so raising it would be a dead end dressed
    # as a chance. Explain instead of prompting; pkexec is never reached.
    if not _is_admin():
        return _not_admin_msg()
    if not Path(ACTUATE).exists():
        return f"(privileged dispatcher missing at {ACTUATE}; run 'sudo apply.sh --ai')"
    return run(["pkexec", ACTUATE, cap, *args], timeout=timeout)
