# w-mcp domain: desktop — perceive and act inside the running Hyprland session.
# Tier 0 context + Tier 1 user-scope actions (notify/capture/launch/dispatch). No
# privilege: exactly the power the invoking user already has, so no polkit — the
# host's own tool-approval covers them. See ai-integration.md.
import datetime
import json
import os
import re
import subprocess
from pathlib import Path

from core import run, tool, prompt

DOMAIN = "w-desktop"

# ── Hyprland dispatch — curated allowlist ─────────────────────────────────────
# In the 0.55 Lua protocol `hyprctl dispatch` takes a *Lua expression*, so passing
# model-authored text straight through would be arbitrary-Lua injection — as
# powerful as hl.dsp.exec_cmd (i.e. arbitrary command execution). Instead every
# action maps to a fixed Lua template; every argument (including the optional
# window `target`, below) is validated/escaped here — the model never supplies
# raw Lua, only a picked action + validated args interpolated as quoted literals.
# Deliberately excludes exec_cmd / exec_raw / global / submap — those launch
# commands or overlays, not window management (w_launch_app covers opening apps
# safely). Expressions mirror the live hotkeys catalog + the wiki
# (Configuring/Basics/Dispatchers).
_HYPR_DIR = ("left", "right", "up", "down")

# Fixed (no-arg) actions that Hyprland lets you aim at a specific window via its
# `window` field — action -> (Lua method, extra constant fields).
_HYPR_WINDOW_FIXED = {
    "close":      ("hl.dsp.window.close", {}),
    "kill":       ("hl.dsp.window.kill", {}),
    "center":     ("hl.dsp.window.center", {}),
    "pin":        ("hl.dsp.window.pin", {}),
    "cycle":      ("hl.dsp.window.cycle_next", {}),
    "fullscreen": ("hl.dsp.window.fullscreen", {"mode": "fullscreen", "action": "toggle"}),
    "maximize":   ("hl.dsp.window.fullscreen", {"mode": "maximized", "action": "toggle"}),
    "float":      ("hl.dsp.window.float", {"action": "toggle"}),
}

# Window-target selector prefixes Hyprland recognizes (Dispatchers.md "Window"
# parameter). `address`/`pid` are exact and get a strict format check; the rest
# are regexes Hyprland matches itself, so we accept free text but escape it.
_WINDOW_PREFIXES = ("address", "pid", "class", "title", "initialclass", "initialtitle")


def _hypr_window_sel(raw):
    """Validate a `target` string into a safe, already-quoted Lua string literal
    (e.g. '"address:0x55f..."'), or reject it.

    Returns (literal, None) on success, (None, None) if raw is empty (no target
    given — act on the focused window, unchanged legacy behaviour), or
    (None, error) if raw is malformed.

    Security model: the only injection surface is a value that closes the Lua
    string literal early and splices arbitrary Lua after it (this is otherwise the
    exact same class of risk as exec_cmd). `address:`/`pid:` are constrained to a
    strict character class (hex / digits) so there is nothing to escape. The
    remaining prefixes accept arbitrary text (Hyprland treats it as a regex to
    match class/title against), so instead of restricting shape we escape every
    backslash and double-quote before embedding it, and additionally reject
    control characters/newlines and cap the length — belt-and-braces, since the
    escaping alone already makes a quote-breakout impossible.
    """
    raw = raw.strip()
    if not raw:
        return None, None
    if ":" not in raw:
        return None, f"(target must be 'prefix:value' — one of {', '.join(p + ':' for p in _WINDOW_PREFIXES)})"
    prefix, value = raw.split(":", 1)
    prefix = prefix.strip().lower()
    if prefix not in _WINDOW_PREFIXES:
        return None, f"(unknown window selector '{prefix}:'; use one of {', '.join(p + ':' for p in _WINDOW_PREFIXES)})"
    if prefix == "address":
        if not re.fullmatch(r"0x[0-9a-fA-F]+", value):
            return None, "(address selector must look like address:0x55f...; get one from w_hypr_windows)"
        return f'"address:{value}"', None
    if prefix == "pid":
        if not re.fullmatch(r"[0-9]{1,10}", value):
            return None, "(pid selector must be a plain integer, e.g. pid:12345)"
        return f'"pid:{value}"', None
    if not value:
        return None, f"(target '{prefix}:' needs a value)"
    if len(value) > 200:
        return None, "(selector value too long; use w_hypr_windows to find an address: instead)"
    if any(ord(c) < 0x20 for c in value):
        return None, "(selector value cannot contain control characters or newlines)"
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{prefix}:{escaped}"', None


def _lua_call(method, fields, window_lit):
    """Build `method({ k = "v", ..., window = <lit> })` (or `method()` if there are
    no fields at all). `fields` values are constants owned by this module (never
    model input) and get quoted as-is; `window_lit` is already a safe, quoted Lua
    literal from _hypr_window_sel."""
    parts = [f'{k} = "{v}"' for k, v in fields.items()]
    if window_lit:
        parts.append(f"window = {window_lit}")
    return f"{method}()" if not parts else f"{method}({{ {', '.join(parts)} }})"


def _hypr_expr(action, arg, window_lit):
    """Map a validated (action, arg, window_lit) to a Lua dispatch expression.
    window_lit is a safe quoted Lua literal from _hypr_window_sel, or None to act
    on the focused window (legacy behaviour). Returns (expr, None) on success,
    (None, error) on a bad arg/target combination, or (None, None) for an unknown
    action."""
    a = arg.strip()
    if action in _HYPR_WINDOW_FIXED:
        if a:
            return None, f"(action '{action}' takes no argument)"
        method, fields = _HYPR_WINDOW_FIXED[action]
        return _lua_call(method, fields, window_lit), None
    if action == "focus-window":
        if a:
            return None, "(action 'focus-window' takes no argument — pass the window via `target`)"
        if not window_lit:
            return None, "(action 'focus-window' needs `target` — get an address from w_hypr_windows)"
        return f"hl.dsp.focus({{ window = {window_lit} }})", None
    if action in ("focus", "move", "swap"):
        if window_lit:
            return None, (f"(action '{action}' always acts on the focused window; use "
                          "'move-to-workspace' or 'focus-window' with `target` for a specific window)")
        if a not in _HYPR_DIR:
            return None, f"(action '{action}' needs a direction: {', '.join(_HYPR_DIR)})"
        tpl = {
            "focus": 'hl.dsp.focus({{ direction = "{d}" }})',
            "move":  'hl.dsp.window.move({{ direction = "{d}" }})',
            "swap":  'hl.dsp.window.swap({{ direction = "{d}" }})',
        }[action]
        return tpl.format(d=a), None
    if action in ("workspace", "move-to-workspace"):
        if action == "workspace" and window_lit:
            return None, "(action 'workspace' switches the active workspace and has no window target)"
        if not (a.isdigit() and 1 <= int(a) <= 99) and a not in ("e+1", "e-1"):
            return None, (f"(action '{action}' needs a workspace: a number 1-99, or "
                          "e+1 / e-1 for the next/previous open workspace)")
        if action == "workspace":
            return f'hl.dsp.focus({{ workspace = "{a}" }})', None
        return _lua_call("hl.dsp.window.move", {"workspace": a}, window_lit), None
    if action in ("focus-monitor", "move-to-monitor"):
        if action == "focus-monitor" and window_lit:
            return None, "(action 'focus-monitor' moves focus and has no window target)"
        if a not in ("+1", "-1"):
            return None, f"(action '{action}' needs a monitor: +1 or -1)"
        if action == "focus-monitor":
            return f'hl.dsp.focus({{ monitor = "{a}" }})', None
        return _lua_call("hl.dsp.window.move", {"monitor": a}, window_lit), None
    return None, None


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_desktop_context() -> str:
        """The live desktop context — what the user is doing right now: the focused
        window (app, title, workspace), the active workspace, and the connected
        monitors, via hyprctl. Read-only and compact by design. Use it to ground
        desktop help in the real session instead of assuming; returns a note if no
        Hyprland session is reachable from here."""
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            return "(no Hyprland session reachable — the assistant is not running inside the graphical session)"

        def _j(*sub, default):
            try:
                return json.loads(run(["hyprctl", "-j", *sub]) or "")
            except ValueError:
                return default

        out = []
        w = _j("activewindow", default={})
        if w.get("class") or w.get("title"):
            ws = (w.get("workspace") or {}).get("name", "?")
            size = "x".join(map(str, w.get("size", []))) or "?"
            out.append(
                f"Focused window: {w.get('class', '?')} — {w.get('title', '')!r} "
                f"[ws {ws}, {'floating' if w.get('floating') else 'tiled'}, {size}]"
            )
        else:
            out.append("Focused window: (none — empty or unfocused workspace)")
        aws = _j("activeworkspace", default={})
        if aws:
            out.append(
                f"Active workspace: {aws.get('name', '?')} "
                f"({aws.get('windows', '?')} window(s) on monitor {aws.get('monitor', '?')})"
            )
        mons = _j("monitors", default=[])
        if mons:
            out.append(
                "Monitors: "
                + "; ".join(
                    f"{m.get('name', '?')} {m.get('width', '?')}x{m.get('height', '?')}"
                    f"@{round(m.get('refreshRate', 0))}Hz{' *focused' if m.get('focused') else ''}"
                    for m in mons
                )
            )
        return "\n".join(out)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_monitor_status() -> str:
        """Monitor layout (Tier 0, read-only): every connected output with its live
        mode/scale/rotation/position, whether it is enabled/focused/primary (the W
        concept of "where the bar and login card live"), its saved `w-monitor` rule
        if one exists, and a handful of its available modes. Wraps `w-monitor list`/
        `status`/`modes` — the same fragment-backed source of truth the CLI and the
        Hub Displays panel use. Modes are capped to the top 5 (by resolution then
        refresh rate) per output, not the full list, to stay compact.

        Read-only: there is no monitor-mutation tool here on purpose. Changing a
        setting means running `w-monitor <cmd> <output> ...` yourself (rootless,
        the session is the user's own — no polkit needed), or `w-monitor greeter
        ...` for the login-screen scope (root). Before mutating, match the output
        the user means against the names listed here; if the wording doesn't map
        unambiguously to one output (e.g. "the left one" with two similarly placed
        monitors, or a name you're not sure of), ask which one they mean instead of
        guessing — a wrong `disable`/`primary` can strand the desktop on a dark
        screen. Returns a note (not an error) if no display is reachable from here."""
        list_out = run(["w-monitor", "list", "--porcelain"])
        if list_out.startswith("(command not found") or list_out.startswith("(exit") or list_out.startswith("(timed out"):
            return list_out

        status_out = run(["w-monitor", "status", "--porcelain"])
        primary = ""
        rules = {}
        for line in status_out.splitlines():
            if line.startswith("primary="):
                primary = line[len("primary="):]
            elif line.startswith("rule="):
                parts = line[len("rule="):].split("\t")
                if len(parts) == 6:
                    rules[parts[0]] = parts[1:]

        if list_out == "(no output)":
            body = "(no live displays detected — is a Hyprland session reachable from here?)"
        else:
            entries = []
            for line in list_out.splitlines():
                parts = line.split("\t")
                if len(parts) != 9:
                    continue
                name, desc, mode, scale, transform, pos, enabled, focused, configured = parts
                flags = ["primary" if name == primary else None,
                         "enabled" if enabled == "1" else "disabled",
                         "focused" if focused == "1" else None]
                flags = [f for f in flags if f]
                entry = (f"{name} ({desc}): {mode}, scale={scale}, transform={transform}°, "
                         f"pos={pos} [{', '.join(flags)}]")
                if configured == "1" and name in rules:
                    r_mode, r_scale, r_transform, r_pos, r_dis = rules[name]
                    entry += (f"\n  saved rule: mode={r_mode} scale={r_scale} "
                              f"transform={r_transform} pos={r_pos} disabled={r_dis}")
                modes_out = run(["w-monitor", "modes", name, "--porcelain"])
                if not modes_out.startswith("("):
                    top = [m.split("\t", 1)[0] for m in modes_out.splitlines()[:5] if m]
                    if top:
                        entry += f"\n  top modes: {', '.join(top)}"
                entries.append(entry)
            body = "\n".join(entries) if entries else "(no live displays detected)"
        return f"Primary: {primary or '(none set)'}\n{body}"

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_bar_status() -> str:
        """Status bar composition (Tier 0, read-only): which outputs carry a bar
        and, for each one, every block's on/off state. Wraps `w-bar status`.
        Composition is PER MONITOR — the same block can be on here and off there
        — so always name the output when reporting, never "the bar". Blocks are
        addressed by their id (the ids come straight out of this listing; `w-bar
        list` also gives their type and which zone they sit in). Read this before
        changing anything: a block that is already off looks identical to one that
        does not exist in the config, and only this tells the two apart."""
        return run(["w-bar", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_bar_set(output: str, block: str = "", state: str = "") -> str:
        """Show or hide a status-bar block, or the whole bar, on ONE output
        (Tier 1: user-scope, reversible, no polkit).
          output  the monitor's connector name, e.g. eDP-1 / HDMI-A-1 (from
                  w_bar_status). Required — there is no "all monitors" form,
                  because the whole point of this setting is per-monitor.
          block   a block id from w_bar_status. Omit it to switch the WHOLE bar
                  on that output.
          state   on | off, or `default` (blocks only) to drop the per-monitor
                  override and follow the config's own value again.
        Applies live — the bar redraws immediately, no restart. Switching a bar
        off KEEPS that output's per-block choices, so switching it back on
        restores exactly what was there; say so rather than warning about losing
        settings. Geometry, colours and the bar's position are NOT here: position
        is `w-appearance bar-position`, everything else about the bar's shape
        belongs to the active theme (see the w-theming skill)."""
        if not output:
            return "output is required — name the monitor (see w_bar_status)"
        allowed = ("on", "off", "default") if block else ("on", "off")
        if state not in allowed:
            return f"state must be one of: {', '.join(allowed)}"
        cmd = ["w-bar", "block", output, block, state] if block \
            else ["w-bar", "monitor", output, state]
        out = run(cmd)
        # Both setters are quiet on success; a refusal (unknown id, bad value) is
        # the only thing they print, so pass it through and otherwise show the
        # resulting composition — what the user actually asked about.
        if out and out != "(no output)":
            return out
        return run(["w-bar", "status"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_nightlight_status() -> str:
        """Night light / blue-light filter (Tier 0, read-only): the mode
        (off | schedule | always), the night and day colour temperatures in
        kelvin, the night window, and whether the screen is being tinted RIGHT
        NOW (plus the value actually on screen, which mid-transition sits
        between the two — report that, not the destination). Wraps
        `w-nightlight status`. The engine is hyprsunset, driven by a config W
        renders — so this answers correctly even with no session reachable from
        here, and "mode is schedule" does not by itself mean the filter is on."""
        return run(["w-nightlight", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_nightlight_set(mode: str = "", temperature: int = 0,
                         start: str = "", end: str = "",
                         day_temperature: int = 0) -> str:
        """Change the night light (Tier 1: user-scope, reversible, no polkit).
        Pass any combination:
          mode        off | schedule | always
          temperature NIGHT colour temperature in kelvin, 1000-20000. Lower is
                      warmer; 4300 is W's default, 3000 is clearly amber.
          day_temperature
                      the DAY end of the transition, same range. 6600 (the
                      default) means the screen is left completely untouched;
                      anything else is a real tint that stays on all day. Use it
                      when the user wants a permanently warmer/cooler screen, or
                      when the start of a transition shows a visible step on
                      their panel. It is NOT an off switch — `mode off` always
                      means an untouched screen whatever this is set to.
          start / end "HH:MM" — both are needed to move the window, and they
                      must differ (a zero-length window is `mode always`).
        Applies immediately and SMOOTHLY: the screen eases to the new value over
        a couple of seconds rather than jumping, so "nothing happened yet" for a
        moment is normal. Omitted arguments are left alone. Note that setting
        `schedule` outside the night window changes nothing on screen until the
        window opens — say so rather than letting the user think it failed."""
        if mode and mode not in ("off", "schedule", "always"):
            return "mode must be one of: off, schedule, always"
        if bool(start) != bool(end):
            return "start and end must be given together (both 'HH:MM')"
        if not (mode or temperature or start or day_temperature):
            return ("nothing to change: pass mode, temperature, "
                    "day_temperature and/or start+end")
        out = []
        if mode:
            out.append(run(["w-nightlight", "mode", mode]))
        if temperature:
            out.append(run(["w-nightlight", "temp", str(temperature)]))
        if day_temperature:
            out.append(run(["w-nightlight", "day", str(day_temperature)]))
        if start:
            out.append(run(["w-nightlight", "schedule", start, end]))
        # Every setter is quiet on success, so echo the resulting state instead of
        # a bare "ok" — the user's real question is what the night light does now.
        failures = [o for o in out if o and o != "(no output)"]
        if failures:
            return "\n".join(failures)
        return run(["w-nightlight", "status"])

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
        Report it as started, not as finished, and use w_hypr_context to see what
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

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_notify(summary: str, body: str = "", urgency: str = "normal") -> str:
        """Show a desktop notification in W's notification stack (Tier 1: user-scope,
        harmless). `summary` is the title, `body` optional detail. Use it to surface a
        result or a heads-up in the desktop itself — it does not replace your reply in
        the chat. Goes through `w-notify send`, W's own entry point, so the alert obeys
        the user's notification settings like any other app's.

        Choose `urgency` by what the user must DO, not by how pleased you are with the
        result — it decides how the alert looks and how long it stays:

        - `critical` — the user must act, and missing it has a real cost: a reboot is
          required to finish an upgrade, the disk is nearly full, a backup failed.
          Critical alerts are red, never auto-dismiss, and are the only ones that pass
          through Do Not Disturb. Use it sparingly; every needless critical trains the
          user to ignore the next one.
        - `normal` (default) — worth knowing, no action owed: a long task finished, a
          digest is ready.
        - `low` — background chatter the user may never look at.

        Notifications sent while DND is on (or from a muted app) are recorded in the
        history rather than shown — see the w-notifications skill."""
        s = summary.strip()
        if not s:
            return "(provide a summary line for the notification)"
        u = urgency.strip().lower()
        if u not in ("low", "normal", "critical"):
            u = "normal"
        out = run(["w-notify", "send", "-u", u, "-a", "W Assistant", s, body.strip()])
        return f"notified: {s}" if out == "(no output)" else out

    @tool(mcp, domain=DOMAIN)
    def w_screenshot(mode: str = "full") -> str:
        """Capture the screen to ~/Pictures/Screenshots and return the saved path
        (Tier 1: user-scope). `mode` is 'full' (all outputs), 'output' (the focused
        monitor), or 'window' (the focused window) — interactive region select is
        intentionally not exposed to the model. Wraps `w-screenshot <mode> --save`.

        Capturing does NOT imply analyzing: this tool only saves the file and returns
        its path. Do not read back or describe the image unless the user explicitly
        asks you to — reading it costs vision tokens and sends the screen's contents to
        the provider, which the user did not request by asking for a screenshot."""
        m = mode.strip().lower()
        if m not in ("full", "output", "window"):
            return "(mode must be one of: full, output, window)"
        err = run(["w-screenshot", m, "--save"], timeout=30)
        # w-screenshot --save notifies but does not print the path; report the newest
        # capture so the model gets the concrete file it just created.
        shots = Path(os.path.expanduser("~/Pictures/Screenshots"))
        newest = max(shots.glob("*.png"), key=lambda p: p.stat().st_mtime, default=None) if shots.is_dir() else None
        if newest and datetime.datetime.now().timestamp() - newest.stat().st_mtime < 60:
            return f"saved: {newest}"
        return err if err != "(no output)" else "(capture ran but no file was found — is a Wayland session active?)"

    @tool(mcp, domain=DOMAIN)
    def w_launch_app(command: str) -> str:
        """Launch a desktop application into the running session (Tier 1: user-scope,
        no privilege — the same power the user's own shell has). `command` is a program
        name and optional simple arguments (e.g. 'firefox', 'ghostty', 'code /home/u/p');
        no shell syntax (pipes, redirects, globs, quotes). Started detached via `uwsm
        app` so it joins the session cleanly. Prefer this over w_run for opening apps."""
        parts = command.split()
        if not parts:
            return "(name a program to launch)"
        bad = [p for p in parts if not re.fullmatch(r"[A-Za-z0-9@._+:=,/-]+", p)]
        if bad:
            return f"(unsupported characters in: {' '.join(bad)}; no shell syntax allowed)"
        try:
            subprocess.Popen(
                ["uwsm", "app", "--", *parts],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, start_new_session=True,
            )
        except FileNotFoundError:
            return "(uwsm not found — cannot launch into the session)"
        return f"launched: {command.strip()}"

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_hypr_windows() -> str:
        """List every open window in the running Hyprland session (Tier 0,
        read-only): address, app class, title, workspace, monitor, floating/tiled,
        and whether it is focused, via `hyprctl clients`.

        Call this BEFORE w_hypr_dispatch whenever the user refers to a window that
        might not be the focused one ("move the browser to workspace 3", "swap the
        windows on workspace 1 and 2", "focus the terminal"). Match the request to
        a window here by its class/title, then pass that window's `address` as
        w_hypr_dispatch's `target` (e.g. `address:0x55f...`) — address is exact and
        the safest choice. If more than one window could plausibly match what the
        user asked for (e.g. two Firefox windows), or the request is ambiguous in
        any other way, do not guess: ask the user which one they mean, or which
        workspace/window to use."""
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            return "(no Hyprland session reachable — the assistant is not running inside the graphical session)"
        try:
            clients = json.loads(run(["hyprctl", "-j", "clients"]) or "")
        except ValueError:
            return "(could not read the window list from hyprctl)"
        if not clients:
            return "(no open windows)"
        lines = []
        for c in clients:
            ws = (c.get("workspace") or {}).get("name", "?")
            title = c.get("title", "")
            if len(title) > 60:
                title = title[:57] + "..."
            lines.append(
                f"{c.get('address', '?')}  {c.get('class', '?')!r} {title!r} "
                f"[ws {ws}, mon {c.get('monitor', '?')}, "
                f"{'floating' if c.get('floating') else 'tiled'}"
                f"{', focused' if c.get('focusHistoryID') == 0 else ''}]"
            )
        return "\n".join(lines)

    @tool(mcp, domain=DOMAIN)
    def w_hypr_dispatch(action: str, arg: str = "", target: str = "") -> str:
        """Control windows and workspaces in the running Hyprland session (Tier 1:
        user-scope, no privilege — the same power the user's own keybindings have).
        Pick an `action` from this allowlist; some take an `arg`, and most accept an
        optional `target` to act on a specific window instead of the focused one:

          close | kill | center | pin | cycle | fullscreen | maximize | float
                                             act on `target` window, or the focused one
          focus-window                      focus `target` window (target required)
          focus <left|right|up|down>        move keyboard focus (focused window only)
          move <left|right|up|down>         move the focused window (focused window only)
          swap <left|right|up|down>         swap the focused window (focused window only)
          workspace <1-99|e+1|e-1>          switch the active workspace (e±1 = next/prev open)
          move-to-workspace <1-99|e+1|e-1>  move `target` window (or focused) to a workspace
          focus-monitor <+1|-1>             move focus to the next/previous monitor
          move-to-monitor <+1|-1>           move `target` window (or focused) to a monitor

        `target` selects a specific window instead of the focused one — call
        w_hypr_windows first and pass its `address` (e.g. `address:0x55f...`), the
        exact and safest choice. `class:...`/`title:...`/`initialclass:...`/
        `initialtitle:...`/`pid:...` are also accepted, but class/title match as a
        regex, so prefer address when more than one window could match. If the
        request is ambiguous in any way (multiple candidate windows, an unclear
        destination), ask the user to clarify instead of guessing which one to act on.

        To move several windows in one request (e.g. "browser to 3, terminal to 4")
        or swap the windows on two workspaces, call this tool once per window with
        its own `target` — there is no bulk/multi-window action. Only these curated
        dispatchers are allowed and every argument (including `target`) is
        validated/escaped, so it cannot run arbitrary commands or Lua — use
        w_launch_app to open apps. Returns a note (not an error) if no Hyprland
        session is reachable from here."""
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            return "(no Hyprland session reachable — the assistant is not running inside the graphical session)"
        act = action.strip().lower()
        if not act:
            return "(name an action; see the tool description for the allowlist)"
        window_lit, werr = _hypr_window_sel(target)
        if werr:
            return werr
        expr, err = _hypr_expr(act, arg, window_lit)
        if err:
            return err
        if expr is None:
            return f"(unknown action '{act}'; see the tool description for the allowlist)"
        out = run(["hyprctl", "dispatch", expr])
        if out.strip().lower() in ("ok", "", "(no output)"):
            detail = act
            if arg.strip():
                detail += f" {arg.strip()}"
            if target.strip():
                detail += f" (target: {target.strip()})"
            return f"dispatched: {detail}"
        return out

    @prompt(mcp, domain=DOMAIN)
    def organize_windows() -> str:
        """Recipe: move/arrange multiple windows across workspaces or monitors from
        a single request (e.g. "put the browser on 3 and the terminal on 4", "swap
        the windows on workspace 1 and 2", "focus the terminal")."""
        return (
            "1. Call w_hypr_windows to see every open window (address, class, "
            "title, workspace, monitor).\n"
            "2. Match each window the user mentioned to one entry by class/title. "
            "If more than one window could match, or the request is ambiguous in "
            "any other way, ask the user to clarify before acting — do not guess.\n"
            "3. For each window to move, call w_hypr_dispatch once with "
            "target=\"address:<its address>\" and the right action/arg "
            "(move-to-workspace / move-to-monitor / focus-window / etc.) — there is "
            "no bulk action, one call per window.\n"
            "4. To swap the windows between two workspaces: after steps 1-2, issue "
            "two move-to-workspace calls, one per window, each with `target` set to "
            "that window's address and `arg` set to the *other* workspace.\n"
            "5. Report back which window ended up where."
        )
