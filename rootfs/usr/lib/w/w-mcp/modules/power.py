# w-mcp domain: power — the W power subsystem (w-power). Read state (Tier 0),
# switch the power-profiles-daemon profile (Tier 1, user D-Bus — no privilege), and
# the privileged knobs: charge threshold, lid action, laptop/desktop mode (Tier 2,
# via com.w.ai.actuate → the single `power-set` capability). Backed by the w-power
# CLI (thin front over PPD + hypridle + systemd-logind + sysfs). Rarer knobs
# (auto-profile toggle, power-key, critical action) stay CLI/Hub-only. See the
# w-power skill / w-power.md.
from typing import Annotated, Literal

from core import _actuate, _disabled_msg, _tool_on, conf_policy_block, desc, run, tool

DOMAIN = "w-power"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_power_status() -> str:
        """Power state (via `w-power status`): machine mode (laptop/desktop) and live
        power source, the power-profiles-daemon profiles with the active one and the
        AC/battery auto-switch, the idle timers as a cascade — lock, then display-off,
        then suspend, each relative to the previous link firing (AC vs battery) — the
        lid + power-key actions, the charge threshold, and — on a laptop — the upower
        battery summary (percentage, charging, time-to-full/empty). It also reports
        whether hypridle is running. Read-only; use it to ground every battery,
        charging, idle, suspend, profile, lid, and mode answer."""
        return run(["w-power", "status"])

    # ── Tier 1 — user-scope, reversible, no privilege ────────────────────────
    @tool(mcp, domain=DOMAIN)
    def w_power_profile(profile: Literal["performance", "balanced", "power-saver"]) -> str:
        """Switch the power-profiles-daemon profile (Tier 1: user D-Bus, no
        prompt). Immediate, reversible; w_power_status shows what is available
        and active. The AC/battery auto-switch is a system setting (`w-power
        profile auto`), not this."""
        p = profile.strip().lower()
        if p not in ("performance", "balanced", "power-saver"):
            return "(profile must be 'performance', 'balanced', or 'power-saver')"
        return run(["w-power", "profile", p])

    # ── Tier 2 — privileged, actuated through polkit (com.w.ai.actuate) ──────
    @tool(mcp, domain=DOMAIN)
    def w_power_charge_limit(
        percent: Annotated[int, desc("where the firmware stops charging: typically 80 to cap wear, 100 for full capacity")],
    ) -> str:
        """Set the battery charge threshold (Tier 2: privileged; polkit prompt).
        Only where the firmware supports it (otherwise a no-op); reversible. Gated
        by W_AI_TOOL_POWER."""
        if not _tool_on("POWER"):
            return _disabled_msg("w_power_charge_limit", "W_AI_TOOL_POWER")
        if not 0 <= percent <= 100:
            return "(percent must be 0..100; typically 80 or 100)"
        blocked = conf_policy_block("power", "CHARGE_LIMIT", "The charge threshold")
        return blocked or _actuate("power-set", "charge-limit", str(percent))

    @tool(mcp, domain=DOMAIN)
    def w_power_lid(
        action: Literal["suspend", "lock", "ignore", "poweroff", "hibernate"],
        source: Annotated[Literal["battery", "ac", "docked"], desc("when it applies: on battery, on wall power, or with an external display attached — logind keeps the three independent")] = "battery",
    ) -> str:
        """Set the laptop lid-close action (Tier 2: privileged; polkit prompt).
        Reversible. Gated by W_AI_TOOL_POWER."""
        if not _tool_on("POWER"):
            return _disabled_msg("w_power_lid", "W_AI_TOOL_POWER")
        a = action.strip().lower()
        s = source.strip().lower()
        if a not in ("suspend", "lock", "ignore", "poweroff", "hibernate"):
            return "(action must be suspend|lock|ignore|poweroff|hibernate)"
        if s not in ("battery", "ac", "docked"):
            return "(source must be 'battery', 'ac', or 'docked')"
        key = {"battery": "LID_ON_BATTERY", "ac": "LID_ON_AC", "docked": "LID_DOCKED"}[s]
        blocked = conf_policy_block("power", key, f"The lid action on {s}")
        return blocked or _actuate("power-set", f"lid-{s}", a)

    @tool(mcp, domain=DOMAIN)
    def w_power_mode(
        mode: Annotated[Literal["laptop", "desktop", "auto"], desc("laptop = AC≠battery idle timers, auto-profile, lid suspends; desktop = one gentle idle set, lid ignored; auto = detect from chassis/battery")],
    ) -> str:
        """Set the machine power mode (Tier 2: privileged; polkit prompt). Reseeds
        EVERY power knob from the mode's preset, overriding individual tweaks — use
        deliberately. Reversible. Gated by W_AI_TOOL_POWER."""
        if not _tool_on("POWER"):
            return _disabled_msg("w_power_mode", "W_AI_TOOL_POWER")
        m = mode.strip().lower()
        if m not in ("laptop", "desktop", "auto"):
            return "(mode must be 'laptop', 'desktop', or 'auto')"
        blocked = conf_policy_block("power", "MODE", "The machine mode")
        return blocked or _actuate("power-set", "mode", m)
