# w-mcp: contract.py — mechanical, zero-LLM checks over the tool registry and
# AGENTS.md ("Tool Contract Selftest"). Import-only, like
# core.py: no dependency on the `mcp` package, so the exact same checks run in
# scripts/check/tests/*.bats (dev machine, python-mcp not installed) and inside
# `w-mcp --selftest` on a real target (where python-mcp IS installed and modules
# are already registered against the real FastMCP instance).
#
# Two entry points:
#   collect_checks(registry, lib_dir, agents_path) — checks an ALREADY populated
#     core.REGISTRY (the real on-target path: bin/w-mcp calls this after its own
#     load_modules() has run against the real mcp — never re-imports modules,
#     which would double-register every tool).
#   run_checks_standalone()                        — the dev/CI path: nothing is
#     loaded yet, so this discovers+registers every module itself against a
#     throwaway recording mcp, then calls collect_checks. Used by check.sh's bats
#     suite and by `python3 contract.py` directly.
#
# discover_and_register() is a deliberate small duplicate of bin/w-mcp's own
# load_modules() (~10 lines) rather than a shared import: bin/w-mcp has no .py
# suffix and hub-specific stderr phrasing, so importing it here would couple a
# dev/CI checker to the production entry point for no real benefit.
import importlib
import inspect
import re
import sys
from pathlib import Path

import core

LIB = Path(__file__).resolve().parent


class _RecordingMCP:
    """Just enough of FastMCP's surface for a module's register(mcp) to run
    without the real `mcp` package. core.tool() already records everything the
    checks below need into core.REGISTRY; `.offered` additionally captures which
    names actually got wrapped (used by _check_profile_gate)."""

    def __init__(self):
        self.offered = []

    def tool(self, *_a, **_kw):
        def deco(fn):
            self.offered.append(fn.__name__)
            return fn
        return deco

    def prompt(self, *_a, **_kw):
        return lambda fn: fn

    def add_resource(self, *_a, **_kw):
        pass


def discover_and_register(mcp, lib_dir=None):
    """Import every modules/<domain>.py under lib_dir and call register(mcp).
    Returns the list of module names that loaded."""
    lib_dir = Path(lib_dir) if lib_dir else LIB
    if str(lib_dir) not in sys.path:
        sys.path.insert(0, str(lib_dir))
    loaded = []
    for path in sorted((lib_dir / "modules").glob("*.py")):
        if path.stem == "__init__":
            continue
        mod = importlib.import_module(f"modules.{path.stem}")
        if hasattr(mod, "register"):
            mod.register(mcp)
            loaded.append(path.stem)
    return loaded


# ── 7.4.1 Tool Contract Selftest ──────────────────────────────────────────────
def _check_schema_validity(registry):
    """Every registered tool's parameters and return value must be type-annotated
    — that's what lets FastMCP build a real JSON Schema instead of an untyped
    `any`. Cheap, offline, catches a class of regression no wire-level test can
    (a missing annotation still "works" until a strict host validates the schema)."""
    problems = []
    for r in registry:
        sig = inspect.signature(r["fn"])
        for pname, p in sig.parameters.items():
            if p.annotation is inspect.Parameter.empty:
                problems.append(f"{r['name']}: parameter '{pname}' has no type annotation")
        if sig.return_annotation is inspect.Signature.empty:
            problems.append(f"{r['name']}: missing return type annotation")
    return problems


def _check_name_collision(registry):
    """Tool names are the MCP wire identity — a duplicate silently shadows one of
    the two implementations depending on dict/registration order."""
    counts = {}
    for r in registry:
        counts[r["name"]] = counts.get(r["name"], 0) + 1
    return [f"tool name '{n}' registered {c} times (must be globally unique)"
            for n, c in counts.items() if c > 1]


def _check_profile_gate(registry):
    """Unit-tests core.tool()'s own minimal-profile gating on two synthetic
    probes (not a real module) — the actual mechanism behind "profile placement":
    a tool not flagged minimal=True must never be *offered* under PROFILE=minimal,
    but must still be *recorded* in REGISTRY regardless of profile. Saves/restores
    the real registry/profile so it never disturbs the caller's state."""
    saved_registry, saved_profile = core.REGISTRY, core.PROFILE
    problems = []
    try:
        offered = {}
        for profile in ("full", "minimal"):
            core.REGISTRY = []
            core.PROFILE = profile
            rec = _RecordingMCP()

            @core.tool(rec, domain="test", minimal=True)
            def _probe_minimal():
                return "ok"

            @core.tool(rec, domain="test", minimal=False)
            def _probe_full_only():
                return "ok"

            offered[profile] = set(rec.offered)
            if len(core.REGISTRY) != 2:
                problems.append(f"profile={profile}: expected 2 REGISTRY entries (recorded regardless "
                                 f"of profile), found {len(core.REGISTRY)}")
        if "_probe_minimal" not in offered["minimal"]:
            problems.append("a minimal=True tool was NOT offered under PROFILE=minimal")
        if "_probe_full_only" in offered["minimal"]:
            problems.append("a minimal=False tool WAS offered under PROFILE=minimal (profile gate broken)")
        if offered["full"] != {"_probe_minimal", "_probe_full_only"}:
            problems.append("PROFILE=full did not offer every registered tool")
    finally:
        core.REGISTRY, core.PROFILE = saved_registry, saved_profile
    return problems


# ── Tier-2 privilege invariant ("tier consistency" + "tier escalation") ──
# W has no per-tool `tier` metadata field (adding one to all ~65 call sites was
# weighed against a "mechanical, compact" brief and rejected). The real,
# enforced barrier is structural: Tier-2
# tools escalate privilege ONLY via core._actuate() -> pkexec, gated by a
# W_AI_TOOL_* toggle checked as their first statement. These checks verify that
# invariant directly instead of trusting a self-declared label.
_ACTUATE_CALL_RE = re.compile(r"_actuate\(")
_TOOL_ON_CALL_RE = re.compile(r"_tool_on\(")
_TOOL_ON_NAME_RE = re.compile(r'_tool_on\(\s*"([A-Z0-9_]+)"')
_PKEXEC_RE = re.compile(r"\bpkexec\b")
_ADMIN_GATE_RE = re.compile(r"_is_admin\(")


def _check_privilege_invariant(lib_dir):
    """pkexec must appear nowhere but core._actuate(); shell=True must appear
    nowhere at all (both would be an in-process privilege-escalation or
    injection path bypassing the one audited dispatcher)."""
    problems = []
    for path in sorted((lib_dir / "modules").glob("*.py")):
        text = path.read_text(errors="replace")
        if _PKEXEC_RE.search(text):
            problems.append(f"modules/{path.name}: calls pkexec directly (bypasses core._actuate)")
        if "shell=True" in text:
            problems.append(f"modules/{path.name}: subprocess call with shell=True (injection risk)")
    core_text = (lib_dir / "core.py").read_text(errors="replace")
    if "shell=True" in core_text:
        problems.append("core.py: subprocess call with shell=True (injection risk)")
    if not _PKEXEC_RE.search(core_text):
        problems.append("core.py: _actuate() no longer calls pkexec — privilege path may be broken")
    # The admin gate is part of the same one-door invariant: because every Tier-2
    # tool escalates through _actuate() alone, one check there covers all of them —
    # and losing it would silently put non-admins back in front of a polkit prompt
    # they cannot answer.
    if not _ADMIN_GATE_RE.search(core_text):
        problems.append("core.py: _actuate() no longer checks _is_admin() — non-admins would be prompted")
    return problems


def _check_tier2_guard(registry):
    """Any tool whose body calls _actuate() must also call _tool_on() (the
    disabled-toggle guard) — the structural proof that no Tier-2 action can run
    without going through the one gated, toggleable, audited path."""
    problems = []
    for r in registry:
        try:
            src = inspect.getsource(r["fn"])
        except (OSError, TypeError):
            continue
        if _ACTUATE_CALL_RE.search(src) and not _TOOL_ON_CALL_RE.search(src):
            problems.append(f"{r['name']}: calls _actuate() without a _tool_on()/_disabled_msg() guard")
    return problems


def _placeholder_args(fn):
    """Dummy args for every required parameter, type-matched so the call doesn't
    raise a TypeError before reaching the (always-first) disabled-toggle guard."""
    kwargs = {}
    for pname, p in inspect.signature(fn).parameters.items():
        if p.default is not inspect.Parameter.empty:
            continue
        kwargs[pname] = {bool: False, int: 0, float: 0.0}.get(p.annotation, "")
    return kwargs


def _check_disabled_tool_stub(registry):
    """7.4.1 "disabled-tool stub": every Tier-2 tool, called with its toggle
    forced off, must return core._disabled_msg's exact hint (naming the switch) —
    never raise, never return empty/silent. Patches core._ai_conf (not _tool_on
    itself — modules imported that name directly via `from core import
    _tool_on`, a live core.py-side patch is what every module actually observes,
    since _tool_on's own body still resolves _ai_conf through core.py's globals).

    Two-step "plan/apply" tools (w_system_update, w_sync_update) only guard the
    apply branch — a blind default call legitimately runs the read-only plan
    path instead of hitting the guard. For any gated tool with an `action`
    parameter, retry forcing action="apply" before concluding the guard is
    missing, instead of false-flagging that convention."""
    gated = []
    for r in registry:
        try:
            src = inspect.getsource(r["fn"])
        except (OSError, TypeError):
            continue
        m = _TOOL_ON_NAME_RE.search(src)
        if m:
            gated.append((r, m.group(1)))
    if not gated:
        return ["no Tier-2 gated tools discovered via _tool_on(\"...\") — guard regex or wiring broken?"]

    problems = []
    original_ai_conf = core._ai_conf
    try:
        core._ai_conf = lambda: {f"W_AI_TOOL_{switch}": "off" for _, switch in gated}
        for r, switch in gated:
            fn = r["fn"]
            expected = core._disabled_msg(r["name"], f"W_AI_TOOL_{switch}")
            attempts = [_placeholder_args(fn)]
            if "action" in inspect.signature(fn).parameters:
                attempts.append({**_placeholder_args(fn), "action": "apply"})
            results = []
            for kwargs in attempts:
                try:
                    results.append(fn(**kwargs))
                except Exception as e:  # noqa: BLE001 — a raise here IS the bug under test
                    results.append(f"(raised {e!r})")
            if expected not in results:
                problems.append(
                    f"{r['name']}: disabled call(s) returned {results!r}, expected {expected!r}"
                )
    finally:
        core._ai_conf = original_ai_conf
    return problems


# ── AGENTS.md structural lint ──────────────────────────────────────────────
# The generic (memory/tools/security/knowledge) section names from the original
# design draft don't match this AGENTS.md's actual headings — mapped to the real ones.
_REQUIRED_SECTIONS = ["## Identity", "## How to use your knowledge", "## Memory", "## Operating rules"]
_STALE_MARKERS = ("TODO", "FIXME", "<<<<<<<")
_TOOL_MENTION_RE = re.compile(r"`(w_[a-z0-9_]+)`")


def _check_agents_md(agents_path, registry):
    if not agents_path.is_file():
        return [f"AGENTS.md not found at {agents_path}"]
    text = agents_path.read_text(errors="replace")
    lines = text.splitlines()
    sections = {ln.strip(): i for i, ln in enumerate(lines) if ln.startswith("## ")}
    starts = sorted(sections.values())

    problems = []
    for want in _REQUIRED_SECTIONS:
        if want not in sections:
            problems.append(f"AGENTS.md: missing mandatory section '{want}'")
            continue
        start = sections[want]
        end = next((s for s in starts if s > start), len(lines))
        if not "\n".join(lines[start + 1:end]).strip():
            problems.append(f"AGENTS.md: section '{want}' is empty")

    for marker in _STALE_MARKERS:
        if marker in text:
            problems.append(f"AGENTS.md: stale marker '{marker}' present")

    names = {r["name"] for r in registry}
    for m in _TOOL_MENTION_RE.finditer(text):
        if m.group(1) not in names:
            problems.append(f"AGENTS.md: mentions `{m.group(1)}` — no such tool in the registry")

    opens, closes = text.count("{{"), text.count("}}")
    if opens != closes:
        problems.append(f"AGENTS.md: unbalanced template braces ({{{{={opens}, }}}}={closes})")
    return problems


# ── Combined entry points ─────────────────────────────────────────────────────
def collect_checks(registry, lib_dir, agents_path):
    """Run every check against an already-populated registry (the on-target
    `w-mcp --selftest` path — modules are already registered against the real
    mcp; never call discover_and_register again here, it would double-register)."""
    return {
        "schema-validity": _check_schema_validity(registry),
        "name-collision": _check_name_collision(registry),
        "profile-gate": _check_profile_gate(registry),
        "privilege-invariant": _check_privilege_invariant(Path(lib_dir)),
        "tier2-guard": _check_tier2_guard(registry),
        "disabled-tool-stub": _check_disabled_tool_stub(registry),
        "agents-md-lint": _check_agents_md(Path(agents_path), registry),
    }


def run_checks_standalone(lib_dir=None, agents_path=None):
    """Dev/CI entry point: discovers+registers every module itself against a
    throwaway recording mcp (nothing is loaded yet in this process), then runs
    collect_checks. Used by check.sh's bats suite and `python3 contract.py`."""
    lib_dir = Path(lib_dir) if lib_dir else LIB
    core.PROFILE = "full"
    loaded = discover_and_register(_RecordingMCP(), lib_dir)
    agents_path = Path(agents_path) if agents_path else core.SYS_ROOT / "AGENTS.md"
    return loaded, collect_checks(core.REGISTRY, lib_dir, agents_path)


def main():
    loaded, checks = run_checks_standalone()
    failed = {name: probs for name, probs in checks.items() if probs}
    print(f"contract: modules loaded ({len(loaded)}): {', '.join(loaded)}")
    for name, probs in checks.items():
        if probs:
            print(f"FAIL {name}:")
            for p in probs:
                print(f"  - {p}")
        else:
            print(f"OK   {name}")
    print(f"contract: {len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
