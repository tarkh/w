# w-mcp domain: displays — what the screen looks like. Two subsystems that share
# one Hub panel: the monitor layout (w-monitor) and the night light (w-nightlight).
# Tier 0 reads + one Tier 1 user-scope setter. No privilege: exactly the power the
# invoking user already has, so no polkit — the host's own tool-approval covers it.
# Split out of desktop.py 2026-09-04 when that skill hit the 32 KiB cap; the seam
# is the one --mcp already enforces (one domain module = one skill). See
# ai-integration.md / ai-authoring.md.
from core import run, tool

DOMAIN = "w-displays"


def register(mcp):
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
