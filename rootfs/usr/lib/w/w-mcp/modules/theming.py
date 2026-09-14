# w-mcp domain: theming — active theme (Tier 0 read + Tier 1 user-scope switch).
from typing import Annotated, Literal

from core import desc, prompt, run, tool

DOMAIN = "w-theming"


def register(mcp):
    @prompt(mcp, domain=DOMAIN)
    def apply_theme(name: str = "") -> str:
        """Recipe: switch the desktop theme (lists the choices first if none is named)."""
        target = name.strip()
        if target:
            return (
                f"The user wants to switch the W desktop theme to '{target}'.\n"
                "1. Call w_theme_status to note the current theme (so the change is reversible).\n"
                f"2. Call w_theme_set('{target}') — user-scope, reversible, applied with a crossfade.\n"
                "3. Confirm the new active theme and remind the user they can revert with "
                "`w-theme reset`. If the name was not found, run `w-theme list` and offer the "
                "valid options."
            )
        return (
            "The user wants to change the desktop theme but did not name one.\n"
            "1. Read w_theme_status for the current theme, and run `w-theme list` (host shell) to "
            "show the available themes.\n"
            "2. Ask the user which theme to apply.\n"
            "3. Once chosen, call w_theme_set(<name>) and confirm the result."
        )

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_theme_status() -> str:
        """The active W theme (per-user pointer, falling back to system)."""
        return run(["w-theme", "current"])

    # Tier 1: safe, reversible, user-scope (no privilege, no polkit).
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_theme_set(name: Annotated[str, desc("a theme from `w-theme list` / w_theme_status")]) -> str:
        """Switch the active W theme for the current user (Tier 1: user-scope,
        reversible). The system/boot theme needs root and is not offered here."""
        if not name.strip():
            return "(provide a theme name; see w_theme_status or `w-theme list`)"
        return run(["w-theme", "set", name])

    @tool(mcp, domain=DOMAIN)
    def w_theme_new(
        name: str,
        wallpaper: Annotated[str, desc("path to the image; its palette becomes the theme")],
        appearance: Literal["dark", "light"] = "dark",
        contrast: Annotated[Literal["low", "medium", "high"], desc("medium = calibrated default, low = soft pastel (tinted canvas), high = crisp; none lowers legibility")] = "medium",
        seed_index: Annotated[int, desc("which dominant colour to build around, 0 = most dominant")] = 0,
    ) -> str:
        """Build a personal theme from an image (Tier 1: writes only
        ~/.config/w/themes). Undo with w_theme_rm; a SYSTEM theme needs root and is
        not offered. Takes tens of seconds, so tell the user it is running."""
        if not name.strip() or not wallpaper.strip():
            return "(provide a theme name and the path to an image)"
        if seed_index < 0:
            return "(seed_index counts from 0, the most dominant colour)"
        return run(
            ["w-theme", "new", name, "--wallpaper", wallpaper, "--appearance", appearance,
             "--contrast", contrast, "--seed-index", str(seed_index)],
            timeout=180,
        )

    @tool(mcp, domain=DOMAIN)
    def w_theme_rm(name: Annotated[str, desc("a personal theme; system themes are refused")]) -> str:
        """Delete one of this user's personal themes (Tier 1: touches only
        ~/.config/w/themes). NOT reversible — confirm with the user. If it is the
        active theme the session falls back to the system one first."""
        if not name.strip():
            return "(provide a theme name; see `w-theme list`)"
        return run(["w-theme", "rm", name])
