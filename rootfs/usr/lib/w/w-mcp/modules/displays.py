# w-mcp domain: displays — what the screen looks like. Two subsystems that share
# one Hub panel: the monitor layout (w-monitor) and the night light (w-nightlight).
# Tier 0 reads + one Tier 1 user-scope setter. No privilege: exactly the power the
# invoking user already has, so no polkit — the host's own tool-approval covers it.
# Split out of desktop.py 2026-09-04 when that skill hit the 32 KiB cap; the seam
# is the one --mcp already enforces (one domain module = one skill). See
# ai-integration.md / ai-authoring.md.
from typing import Annotated, Literal

from core import desc, run, tool

DOMAIN = "w-displays"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_monitor_status() -> str:
        """Monitor layout (Tier 0, read-only): every connected output with its
        live mode/scale/rotation/position, enabled/focused/primary flags, its
        saved `w-monitor` rule, top-5 available modes and the scale factors the
        compositor accepts (pick only from `valid scales`). There is no mutation
        tool on purpose — changes are `w-monitor <cmd> <output> …` in the shell;
        when the wording does not map to exactly one output, ask which one before
        touching it (a wrong disable/primary strands the desktop). See the
        w-displays skill."""
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
                scales_out = run(["w-monitor", "scales", name, "--porcelain"])
                if not scales_out.startswith("("):
                    valid = [l.split("\t", 1)[0] for l in scales_out.splitlines() if l[:1].isdigit()]
                    if valid:
                        entry += f"\n  valid scales: {', '.join(valid)}"
                entries.append(entry)
            body = "\n".join(entries) if entries else "(no live displays detected)"
        return f"Primary: {primary or '(none set)'}\n{body}"

    @tool(mcp, domain=DOMAIN)
    def w_nightlight_status() -> str:
        """Night light / blue-light filter (Tier 0, read-only): mode
        (off/schedule/always), night and day colour temperatures, the night
        window, and whether the screen is tinted RIGHT NOW with the value actually
        on screen (mid-transition it sits between the two — report that). "mode is
        schedule" does not by itself mean the filter is on."""
        return run(["w-nightlight", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_nightlight_set(
        mode: Annotated[Literal["", "off", "schedule", "always"], desc("empty = unchanged")] = "",
        temperature: Annotated[int, desc("NIGHT colour temperature in kelvin, 1000-20000; lower is warmer (4300 = W default, 3000 clearly amber). 0 = unchanged")] = 0,
        start: Annotated[str, desc("night window start, HH:MM — give start and end together, they must differ")] = "",
        end: Annotated[str, desc("night window end, HH:MM")] = "",
        day_temperature: Annotated[int, desc("DAY end of the transition, 1000-20000; 6600 = screen untouched by day, anything else is an all-day tint (not an off switch). 0 = unchanged")] = 0,
    ) -> str:
        """Change the night light (Tier 1: user-scope, reversible, no polkit).
        Pass any combination; omitted arguments stay. Applies at once but eases
        over a couple of seconds, and `schedule` set outside the night window
        changes nothing on screen until it opens — say so rather than letting the
        user think it failed. Returns the resulting status."""
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
