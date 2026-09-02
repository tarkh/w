# w-mcp domain: security — firmware metadata refresh (Tier 2, via com.w.ai.actuate).
from core import _actuate, _disabled_msg, _tool_on, tool

DOMAIN = "w-security"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_fwupd_refresh() -> str:
        """Refresh firmware update metadata from LVFS (Tier 2: privileged; polkit
        prompt). Only downloads metadata — flashes nothing. Follow with
        `fwupdmgr get-updates` to see what is available."""
        if not _tool_on("FWUPD"):
            return _disabled_msg("w_fwupd_refresh", "W_AI_TOOL_FWUPD")
        return _actuate("fwupd-refresh")
