# w-mcp domain: datetime — timezone / clock / NTP state (Tier 0) + the privileged
# timezone and NTP-toggle actuation (Tier 2, via com.w.ai.actuate). Backed by the
# w-time CLI (thin front over timedatectl + systemd-timesyncd). Changing the NTP
# server *set* is a rare, catalog-bound action left to the w-time CLI / Hub — the AI
# gets the two common actions (set the zone, turn sync on/off) plus a read. See the
# w-datetime skill / w-time.md.
import re
from typing import Annotated, Literal

from core import _actuate, _disabled_msg, _tool_on, desc, run, tool

DOMAIN = "w-datetime"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_time_status() -> str:
        """Date/time state: the current local time, timezone, RTC clock and whether
        NTP network time sync is on (via `w-time status`). Read-only. Use
        `w-time list-zones` from a shell to browse timezone names."""
        return run(["w-time", "status"])

    # ── Tier 2 — privileged, actuated through polkit (com.w.ai.actuate) ──────
    @tool(mcp, domain=DOMAIN)
    def w_timezone_set(
        timezone: Annotated[str, desc("IANA zone name, e.g. 'Europe/Moscow' (browse with `w-time list-zones`)")],
    ) -> str:
        """Set the system timezone (Tier 2: privileged; polkit prompt). Reversible.
        Gated by W_AI_TOOL_TIMEZONE."""
        if not _tool_on("TIMEZONE"):
            return _disabled_msg("w_timezone_set", "W_AI_TOOL_TIMEZONE")
        tz = timezone.strip()
        if not re.fullmatch(r"[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*", tz):
            return "(invalid timezone name, e.g. 'Europe/Moscow'; see `w-time list-zones`)"
        return _actuate("timezone-set", tz)

    @tool(mcp, domain=DOMAIN)
    def w_ntp_set(
        state: Annotated[Literal["on", "off"], desc("on = systemd-timesyncd keeps the clock synced; off = set manually")],
    ) -> str:
        """Enable or disable NTP network time sync (Tier 2: privileged; polkit
        prompt). Reversible. Gated by W_AI_TOOL_NTP."""
        if not _tool_on("NTP"):
            return _disabled_msg("w_ntp_set", "W_AI_TOOL_NTP")
        s = state.strip().lower()
        if s not in ("on", "off"):
            return "(state must be 'on' or 'off')"
        return _actuate("ntp-toggle", s)
