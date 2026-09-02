# w-mcp domain: software — install/remove official-repo packages (Tier 2, com.w.ai.actuate).
import re

from core import _actuate, _disabled_msg, _tool_on, tool

DOMAIN = "w-software"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_pacman_install(packages: str) -> str:
        """Install one or more official-repo packages (Tier 2: privileged; polkit
        prompt). `packages` is a space-separated list of repo package names — no AUR,
        no flags. Uses `pacman -S --needed`."""
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
    def w_pacman_remove(packages: str) -> str:
        """Remove one or more installed packages, with their unneeded dependencies and
        config files (Tier 2: privileged; polkit prompt). `packages` is a
        space-separated list of package names. Uses `pacman -Rns` (snap-pac takes a
        pre-transaction snapshot, so this is rollback-safe). Gated by
        W_AI_TOOL_PACMAN."""
        if not _tool_on("PACMAN"):
            return _disabled_msg("w_pacman_remove", "W_AI_TOOL_PACMAN")
        pkgs = [p for p in packages.split() if p.strip()]
        if not pkgs:
            return "(name at least one package to remove)"
        bad = [p for p in pkgs if not re.fullmatch(r"[A-Za-z0-9@._+-]+", p)]
        if bad:
            return f"(invalid package name(s): {' '.join(bad)})"
        return _actuate("pacman-remove", *pkgs, timeout=600)
