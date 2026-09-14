# w-mcp domain: session — the graphical session's window layout: the automatic
# session memory (reopen what was open at the next login) and the named layouts a
# user saves on purpose. Tier 0 reads + Tier 1 user-scope actions, no privilege —
# w_layout_apply is the most destructive of them and defaults to dry_run.
# Split out of desktop.py 2026-09-04 when that skill hit the 32 KiB cap; the seam
# is the one --mcp already enforces (one domain module = one skill). See
# ai-integration.md / ai-authoring.md.
import os
from typing import Annotated, Literal

from core import desc, run, tool

DOMAIN = "w-session"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_session_status() -> str:
        """Session memory (Tier 0, read-only): whether the graphical session's
        window layout is remembered across logins (mode off/save/restore), the
        background-snapshot floor, and what the snapshot holds right now — window
        count, age, how many are programs inside a terminal. `restore` over an
        empty snapshot reopens nothing, so read the count, not just the mode."""
        return run(["w-session", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_session_set(
        mode: Annotated[Literal["", "off", "save", "restore"], desc("off = nothing recorded; save = recorded, reopened on request; restore = reopened at every login (takes effect at the NEXT login). Empty = unchanged")] = "",
        autosave_seconds: Annotated[int, desc("background snapshot floor 0-86400; 0 = snapshot only on graceful logout (a power cut loses the session). -1 = unchanged")] = -1,
        terminal_apps: Annotated[Literal["", "off", "allowlist", "all"], desc("reopen the program running inside a terminal: allowlist (curated: editors, pagers, monitors), all (RE-EXECUTES every terminal's last command at login — warn first), off. Empty = unchanged")] = "",
        save_now: Annotated[bool, desc("take a snapshot now (no-op while mode is off)")] = False,
        forget: Annotated[bool, desc("delete the saved session so the next login is clean — ask first")] = False,
    ) -> str:
        """Change the session memory (Tier 1: user-scope, reversible, no polkit).
        Pass any combination; omitted arguments stay as they are. Returns the
        resulting status. Details and consequences: the w-session skill."""
        if autosave_seconds != -1 and not 0 <= autosave_seconds <= 86400:
            return "autosave_seconds must be between 0 and 86400"
        if not (mode or autosave_seconds != -1 or terminal_apps or save_now or forget):
            return ("nothing to change: pass mode, autosave_seconds, "
                    "terminal_apps, save_now and/or forget")
        if forget and save_now:
            return "save_now and forget contradict each other — pick one"
        out = []
        # Order matters: the mode gates whether a save records anything at all,
        # so it is applied before the one-shot actions below.
        if mode:
            out.append(run(["w-session", "mode", mode]))
        if autosave_seconds != -1:
            out.append(run(["w-session", "autosave", str(autosave_seconds)]))
        if terminal_apps:
            out.append(run(["w-session", "terminal", terminal_apps]))
        if forget:
            out.append(run(["w-session", "forget"]))
        if save_now:
            out.append(run(["w-session", "save"]))
        failures = [o for o in out if o and o != "(no output)"]
        if failures:
            return "\n".join(failures)
        # The setters are quiet on success; the user's real question is what the
        # session memory holds now, so answer that instead of "ok".
        return run(["w-session", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_layouts_list() -> str:
        """Saved window layouts (Tier 0, read-only): the named arrangements this
        user kept on purpose, newest first — slug (what w_layout_apply takes),
        scope (`layout` = every workspace, `workspace` = one, applied onto
        whichever is focused), window count, date. Separate from the automatic
        session memory (w_session_status); they survive `forget`."""
        return run(["w-session", "layout", "list"])

    @tool(mcp, domain=DOMAIN)
    def w_layout_save(
        name: Annotated[str, desc("layout name; reusing an existing one REPLACES it — check w_layouts_list first")],
        workspace_only: Annotated[bool, desc("save just the focused workspace, number-free, so it applies onto any workspace")] = False,
    ) -> str:
        """Save the current windows as a named layout (Tier 1: user-scope, no
        polkit). Additive, destroys nothing. Records what the session memory can
        reopen (see the w-session skill for what a terminal brings back)."""
        if not name.strip():
            return "a layout needs a name"
        cmd = ["w-session", "layout", "save", name]
        if workspace_only:
            cmd.append("--workspace")
        out = run(cmd)
        return out if out and out != "(no output)" else run(["w-session", "layout", "list"])

    @tool(mcp, domain=DOMAIN)
    def w_layout_apply(
        slug: Annotated[str, desc("layout slug from w_layouts_list")],
        dry_run: Annotated[bool, desc("true = change nothing, return how many windows would be asked to close")] = True,
    ) -> str:
        """Replace what is on screen with a saved layout (Tier 1: user-scope) —
        THIS CLOSES THE USER'S WINDOWS (all of them for a `layout` scope). Run
        the dry run first and get the user's agreement before dry_run=False. Only
        unsaved-work dialogs protect anything; browser tabs and terminals get
        none. The apply runs detached: report it as started, not finished, and
        check w_desktop_context afterwards. Details: the w-session skill."""
        if not slug.strip() or slug != os.path.basename(slug) or slug.startswith("."):
            return "not a layout name"
        cmd = ["w-session", "layout", "apply", slug]
        if dry_run:
            out = run(cmd + ["--dry-run"]).strip()
            if not out.isdigit():
                return out
            return (f"dry run: applying '{slug}' would ask {out} window(s) to close, "
                    "then reopen the saved arrangement. Nothing has changed. Confirm "
                    "with the user before calling again with dry_run=false.")
        return run(cmd)
