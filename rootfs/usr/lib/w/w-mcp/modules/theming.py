# w-mcp domain: theming — active theme (Tier 0 read + Tier 1 user-scope switch).
from core import prompt, run, tool

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
    def w_theme_set(name: str) -> str:
        """Switch the active W theme for the current user (Tier 1: user-scope,
        reversible, no root — wraps `w-theme set`). Changing the system/boot theme
        needs root and is out of scope for this tool. List choices with
        `w-theme list` or w_theme_status."""
        if not name.strip():
            return "(provide a theme name; see w_theme_status or `w-theme list`)"
        return run(["w-theme", "set", name])

    @tool(mcp, domain=DOMAIN)
    def w_theme_new(
        name: str,
        wallpaper: str,
        appearance: str = "dark",
        contrast: str = "medium",
        seed_index: int = 0,
    ) -> str:
        """Build a personal theme from an image (Tier 1: writes only
        ~/.config/w/themes, no root — wraps `w-theme new`). The wallpaper is
        cover-cropped to every resolution tier and its palette becomes the theme;
        `appearance` is dark or light. Undo with w_theme_rm. Building a SYSTEM
        theme needs root and is deliberately not offered here.

        `contrast` is low, medium or high: medium is the calibrated default, low
        is the soft pastel end (it tints the canvas, which is what makes a light
        theme readable as tinted paper rather than a white sheet), high is crisp.
        No level lowers legibility. `seed_index` picks which of the image's
        dominant colours the theme is built around, 0 being the most dominant;
        an image with one hue only has 0.

        Takes tens of seconds (image conversion), so tell the user it is running."""
        if not name.strip() or not wallpaper.strip():
            return "(provide a theme name and the path to an image)"
        if appearance not in ("dark", "light"):
            return "(appearance must be 'dark' or 'light')"
        if contrast not in ("low", "medium", "high"):
            return "(contrast must be 'low', 'medium' or 'high')"
        if seed_index < 0:
            return "(seed_index counts from 0, the most dominant colour)"
        return run(
            ["w-theme", "new", name, "--wallpaper", wallpaper, "--appearance", appearance,
             "--contrast", contrast, "--seed-index", str(seed_index)],
            timeout=180,
        )

    @tool(mcp, domain=DOMAIN)
    def w_theme_rm(name: str) -> str:
        """Delete one of this user's personal themes (Tier 1: touches only
        ~/.config/w/themes — wraps `w-theme rm`). If it is the active theme the
        session falls back to the system one first. System themes are refused;
        removing those needs root on the CLI. This is NOT reversible — the theme
        would have to be rebuilt from its wallpaper, so confirm with the user."""
        if not name.strip():
            return "(provide a theme name; see `w-theme list`)"
        return run(["w-theme", "rm", name])
