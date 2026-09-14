# w-mcp domain: w-automation — proactive/scheduled work: goose recipes
# (declarative task files, curated by convention to read-only tools + w_notify)
# triggered by systemd user timers. Tier 0 read + Tier 1 user-scope (no privilege,
# no polkit — scheduling a timer is exactly as reversible as editing a crontab).
# The real logic lives in `w-ai recipe/run-recipe/schedule`; these tools are thin
# fronts so the model can drive it without a shell. See ai-integration.md, Этап 4.
import re
from typing import Annotated

from core import desc, run, tool

DOMAIN = "w-automation"

_NAME_RE = re.compile(r"^[a-z0-9-]+$")


def _valid_recipe_name(name):
    """Mirror w-ai's RECIPE_NAME_RE: a bare catalog name, never a path — this is
    what keeps a scheduled recipe confined to the two curated recipe directories
    instead of an arbitrary file. Exposed at module level so it is unit-testable
    without an MCP server (see ai-automation.bats)."""
    return bool(_NAME_RE.fullmatch(name.strip()))


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_recipe_list() -> str:
        """List available automation recipes (Tier 0, read-only): the system
        catalog plus any user-added overlay recipe. Each is a goose task file
        restricted by convention to read-only tools plus a final notification —
        call this before w_schedule_add to see valid recipe names."""
        return run(["w-ai", "recipe", "list"])

    @tool(mcp, domain=DOMAIN)
    def w_schedule_add(
        recipe: Annotated[str, desc("a name from w_recipe_list")],
        oncalendar: Annotated[str, desc("systemd OnCalendar expression: 'daily', '*-*-* 09:00:00', 'Mon *-*-* 09:00:00', '*:0/30'")],
    ) -> str:
        """Run a recipe periodically on a systemd user timer (Tier 1: user-scope,
        reversible like a crontab entry). One schedule per recipe — adding again
        replaces the time. Only when the user explicitly asks for a recurring
        task; never create one unprompted."""
        if not _valid_recipe_name(recipe):
            return "(recipe must be a bare name like 'morning-digest' — see w_recipe_list)"
        cal = oncalendar.strip()
        if not cal:
            return "(provide an OnCalendar expression, e.g. 'daily' or '*:0/30')"
        return run(["w-ai", "schedule", "add", recipe.strip(), cal], timeout=30)

    @tool(mcp, domain=DOMAIN)
    def w_schedule_list() -> str:
        """List active recipe schedules (Tier 0, read-only): recipe name plus
        next/last run time, via systemd user timers."""
        return run(["w-ai", "schedule", "list"], timeout=30)

    @tool(mcp, domain=DOMAIN)
    def w_schedule_rm(recipe: str) -> str:
        """Remove a recipe's schedule (Tier 1: user-scope, reversible). `recipe` is
        the name previously passed to w_schedule_add."""
        if not _valid_recipe_name(recipe):
            return "(recipe must be a bare name — see w_schedule_list)"
        return run(["w-ai", "schedule", "rm", recipe.strip()], timeout=30)
