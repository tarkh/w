# w-mcp domain: software — install/remove official-repo packages (Tier 2, com.w.ai.actuate).
import re
from typing import Annotated

from core import _actuate, _disabled_msg, _tool_on, desc, tool

DOMAIN = "w-software"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_pacman_install(
        packages: Annotated[str, desc("space-separated official-repo package names — no AUR, no flags")],
    ) -> str:
        """Install official-repo packages with `pacman -S --needed` (Tier 2:
        privileged; polkit prompt)."""
        if not _tool_on("PACMAN"):
            return _disabled_msg("w_pacman_install", "W_AI_TOOL_PACMAN")
        pkgs = [p for p in packages.split() if p.strip()]
        if not pkgs:
            return "(name at least one package to install)"
        bad = [p for p in pkgs if not re.fullmatch(r"[A-Za-z0-9@._+-]+", p)]
        if bad:
            return f"(invalid package name(s): {' '.join(bad)})"
        return _actuate("pacman-install", *pkgs, timeout=600)

    @tool(mcp, domain=DOMAIN)
    def w_pacman_remove(
        packages: Annotated[str, desc("space-separated installed package names")],
    ) -> str:
        """Remove packages with their unneeded dependencies and config files,
        `pacman -Rns` (Tier 2: privileged; polkit prompt). snap-pac snapshots
        first, so it is rollback-safe. Gated by W_AI_TOOL_PACMAN."""
        if not _tool_on("PACMAN"):
            return _disabled_msg("w_pacman_remove", "W_AI_TOOL_PACMAN")
        pkgs = [p for p in packages.split() if p.strip()]
        if not pkgs:
            return "(name at least one package to remove)"
        bad = [p for p in pkgs if not re.fullmatch(r"[A-Za-z0-9@._+-]+", p)]
        if bad:
            return f"(invalid package name(s): {' '.join(bad)})"
        return _actuate("pacman-remove", *pkgs, timeout=600)
