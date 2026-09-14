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
from typing import Annotated, Literal, get_args

from core import desc, prompt, run, tool

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
_HYPR_ACTIONS = Literal["close", "kill", "center", "pin", "cycle", "fullscreen", "maximize",
                        "float", "focus-window", "focus", "move", "swap", "workspace",
                        "move-to-workspace", "focus-monitor", "move-to-monitor"]

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

    @tool(mcp, domain=DOMAIN)
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
    def w_bar_set(
        output: Annotated[str, desc("connector name from w_bar_status, e.g. eDP-1; one output per call — the setting is per-monitor")],
        state: Annotated[Literal["on", "off", "default"], desc("`default` (blocks only) drops the per-monitor override")],
        block: Annotated[str, desc("block id from w_bar_status; omit to switch the whole bar on that output")] = "",
    ) -> str:
        """Show or hide a status-bar block, or the whole bar, on ONE output (Tier 1:
        user-scope, live, reversible). Switching a bar off keeps its per-block
        choices, so nothing is lost. Position, geometry and colours are not here —
        see the w-desktop skill."""
        if not output:
            return "output is required — name the monitor (see w_bar_status)"
        if state == "default" and not block:
            return "state 'default' applies to a block only; use on/off for the whole bar"
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
    def w_notify(
        summary: Annotated[str, desc("title line")],
        body: Annotated[str, desc("optional detail")] = "",
        urgency: Annotated[Literal["low", "normal", "critical"], desc("critical only when the user must act and missing it costs (reboot needed, disk nearly full, backup failed): it never auto-dismisses and passes DND. low = background chatter")] = "normal",
    ) -> str:
        """Show a desktop notification (Tier 1: user-scope, harmless). Surfaces a
        result in the desktop itself; it does not replace your reply in the chat.
        Under DND or a per-app mute it goes to history instead of the screen
        (w-notifications skill)."""
        s = summary.strip()
        if not s:
            return "(provide a summary line for the notification)"
        out = run(["w-notify", "send", "-u", urgency, "-a", "W Assistant", s, body.strip()])
        return f"notified: {s}" if out == "(no output)" else out

    @tool(mcp, domain=DOMAIN)
    def w_screenshot(
        mode: Annotated[Literal["full", "output", "window"], desc("full = all outputs, output = focused monitor, window = focused window")] = "full",
    ) -> str:
        """Capture the screen to ~/Pictures/Screenshots and return the saved path
        (Tier 1: user-scope). Capturing is not analyzing: only save and report the
        path — do not read the image back unless the user explicitly asks (vision
        tokens + the screen's contents go to the provider)."""
        err = run(["w-screenshot", mode, "--save"], timeout=30)
        # w-screenshot --save notifies but does not print the path; report the newest
        # capture so the model gets the concrete file it just created.
        shots = Path(os.path.expanduser("~/Pictures/Screenshots"))
        newest = max(shots.glob("*.png"), key=lambda p: p.stat().st_mtime, default=None) if shots.is_dir() else None
        if newest and datetime.datetime.now().timestamp() - newest.stat().st_mtime < 60:
            return f"saved: {newest}"
        return err if err != "(no output)" else "(capture ran but no file was found — is a Wayland session active?)"

    @tool(mcp, domain=DOMAIN)
    def w_launch_app(
        command: Annotated[str, desc("program name + simple arguments, e.g. 'firefox' or 'code /home/u/p'; no shell syntax (pipes, redirects, globs, quotes)")],
    ) -> str:
        """Launch a desktop application into the running session, detached via
        `uwsm app` (Tier 1: user-scope — the same power the user's own shell has).
        Prefer this over w_run for opening apps."""
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
        read-only): address, class, title, workspace, monitor, floating/tiled,
        focused. Call it before w_hypr_dispatch whenever the request may concern a
        window other than the focused one, then pass the chosen window's
        `address:…` as `target`. If more than one window could match, ask the user
        instead of guessing."""
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
    def w_hypr_dispatch(
        action: Annotated[_HYPR_ACTIONS, desc("focus/move/swap: arg = left/right/up/down (focused window only). workspace, move-to-workspace: arg = 1-99, e+1 or e-1. focus-monitor, move-to-monitor: arg = +1 or -1. Others take no arg")],
        arg: Annotated[str, desc("the action's argument, see `action`")] = "",
        target: Annotated[str, desc("act on this window instead of the focused one: `address:0x…` from w_hypr_windows (exact, preferred) or class:/title:/initialclass:/initialtitle:/pid: (class/title are regexes)")] = "",
    ) -> str:
        """Control windows and workspaces in the running Hyprland session (Tier 1:
        user-scope — the power of the user's own keybindings; only this curated
        allowlist, never arbitrary commands). One call per window, there is no
        bulk action; if the request is ambiguous (several matching windows, an
        unclear destination) ask the user instead of guessing. Use w_launch_app to
        open apps."""
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            return "(no Hyprland session reachable — the assistant is not running inside the graphical session)"
        act = action.strip().lower()
        window_lit, werr = _hypr_window_sel(target)
        if werr:
            return werr
        expr, err = _hypr_expr(act, arg, window_lit)
        if err:
            return err
        if expr is None:
            return f"(unknown action '{act}'; allowed: {', '.join(get_args(_HYPR_ACTIONS))})"
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
