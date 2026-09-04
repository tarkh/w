# w-mcp domain: session — the graphical session's window layout: the automatic
# session memory (reopen what was open at the next login) and the named layouts a
# user saves on purpose. Tier 0 reads + Tier 1 user-scope actions, no privilege —
# w_layout_apply is the most destructive of them and defaults to dry_run.
# Split out of desktop.py 2026-09-04 when that skill hit the 32 KiB cap; the seam
# is the one --mcp already enforces (one domain module = one skill). See
# ai-integration.md / ai-authoring.md.
import os

from core import run, tool

DOMAIN = "w-session"


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_session_status() -> str:
        """Session memory (Tier 0, read-only): whether the graphical session's
        window layout is remembered across logins, and what is stored right now.
        Wraps `w-session status`. Reports the mode — `off` (nothing recorded),
        `save` (recorded, reopened only on request) or `restore` (recorded and
        reopened at every login) — the background-snapshot floor in seconds, how
        many windows the saved snapshot holds and when it was taken, and how many
        of those windows are a program running INSIDE a terminal.

        The snapshot count answers a question the mode alone does not: `restore`
        with an empty snapshot reopens nothing, which looks like a broken setting
        unless you say so. A graceful logout always saves exactly; the seconds
        figure is only how much an unclean shutdown may cost."""
        return run(["w-session", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_session_set(mode: str = "", autosave_seconds: int = -1,
                      terminal_apps: str = "",
                      save_now: bool = False, forget: bool = False) -> str:
        """Change the session memory (Tier 1: user-scope, reversible, no polkit).
        Pass any combination:
          mode              off | save | restore  (see w_session_status)
          autosave_seconds  background snapshot floor, 0-86400. 0 means snapshot
                            only on a graceful logout — no background writes, but
                            a power cut loses the session.
          terminal_apps     off | allowlist | all — reopen the program running
                            inside a terminal window, or just the terminal
          save_now          take a snapshot immediately
          forget            delete the saved session, so the next login is clean

        `forget` is destructive in the way that matters to the user: the saved
        layout is gone and the next login starts empty. Ask before using it
        unless they asked for exactly that. `save_now` is a no-op while the mode
        is `off` — set the mode first, or the user will think it failed.

        Turning `restore` ON does not reopen anything now; it takes effect at the
        next login. Say that rather than letting the user wait for windows.

        `terminal_apps` decides whether the program running inside a terminal
        window comes back too, or just the terminal: `allowlist` (the default —
        editors, pagers and monitors, from a curated list), `all` (whatever was
        in the foreground) or `off`. Treat `all` as a real choice with a
        consequence, not a "more complete" setting: it RE-EXECUTES the last
        foreground command of every terminal at login, which for a build, a
        deploy script or anything behind `sudo` is not what the user meant. Say
        so before setting it."""
        if mode and mode not in ("off", "save", "restore"):
            return "mode must be one of: off, save, restore"
        if autosave_seconds != -1 and not 0 <= autosave_seconds <= 86400:
            return "autosave_seconds must be between 0 and 86400"
        if terminal_apps and terminal_apps not in ("off", "allowlist", "all"):
            return "terminal_apps must be one of: off, allowlist, all"
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

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_layouts_list() -> str:
        """Saved window layouts (Tier 0, read-only): the named desktop
        arrangements this user has kept, newest first. Wraps `w-session layout
        list`. Each row is a slug (what you pass to w_layout_apply), a scope, how
        many windows it holds and when it was saved.

        Two scopes, and the difference decides what applying one destroys:
          layout      every workspace. Applying it replaces the WHOLE desktop.
          workspace   one workspace's arrangement, saved without a number, so it
                      applies onto whichever workspace is focused at the time.

        These are not the automatic session memory — that is one snapshot, taken
        behind the user's back, and w_session_status reports it. These are named
        and made on purpose, they survive `w-session forget`, and they exist
        whether or not the session memory is switched on."""
        return run(["w-session", "layout", "list"])

    @tool(mcp, domain=DOMAIN)
    def w_layout_save(name: str, workspace_only: bool = False) -> str:
        """Save the current windows as a named layout (Tier 1: user-scope, no
        polkit). `workspace_only` saves just the focused workspace, without its
        number, so it can later be applied onto any workspace; the default saves
        every workspace.

        Saving is additive and destroys nothing — it records what is on screen.
        Reusing an existing name REPLACES that layout, so check w_layouts_list
        first if the user did not mean to overwrite.

        What a layout can hold is what the session memory can reopen: a program
        that cannot be relaunched from its command line is not recorded, and
        whether the program running inside a terminal comes back depends on the
        user's `terminal_apps` setting (see w_session_status)."""
        if not name.strip():
            return "a layout needs a name"
        cmd = ["w-session", "layout", "save", name]
        if workspace_only:
            cmd.append("--workspace")
        out = run(cmd)
        return out if out and out != "(no output)" else run(["w-session", "layout", "list"])

    @tool(mcp, domain=DOMAIN)
    def w_layout_apply(slug: str, dry_run: bool = True) -> str:
        """Replace what is on screen with a saved layout (Tier 1: user-scope, no
        polkit — but the most destructive tool in this domain).

        THIS CLOSES THE USER'S WINDOWS. A `layout` scope closes every window on
        every workspace; a `workspace` scope closes the focused workspace's. Ask
        before running it with dry_run=False unless the user asked for exactly
        this layout by name, and say what it will close — `dry_run=True` (the
        default) answers that: it changes nothing and returns the number of
        windows that would be asked to close.

        What survives and what does not: every window is asked to close the way
        its X button does, so anything with unsaved work raises its own "Save
        changes?" dialog, and CANCELLING ANY ONE OF THEM ABANDONS THE WHOLE
        APPLY with nothing else touched. What gets no dialog is everything that
        never had one — browser tabs, a shell with a job running, a terminal
        (W turns ghostty's close confirmation off deliberately). Do not describe
        this as safe because the dialogs exist; they only cover unsaved files.

        The apply itself runs detached and returns immediately: it closes the
        terminal it was started from, so there is nothing left to report to. A
        refusal arrives as a desktop notification, not in this tool's output.
        Report it as started, not as finished, and use w_desktop_context to see what
        actually came back."""
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
