# w-mcp domain: shared — cross-cutting privileged actuation that is not owned by a
# single subsystem skill: re-run any apply.sh module, set the locale, or (off by
# default) run an arbitrary root command. Tier 2, via com.w.ai.actuate.
import re
from typing import Annotated

from core import _actuate, _disabled_msg, _tool_on, desc, tool

DOMAIN = "shared"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_apply_module(
        module: Annotated[str, desc("bare module name without dashes, e.g. 'dns', 'firewall', 'style', 'quickshell'")],
    ) -> str:
        """Re-run one W apply.sh module to (re)configure a subsystem (Tier 2:
        privileged; polkit prompt) — `apply.sh --<module>` from the on-disk W
        source tree."""
        if not _tool_on("APPLY"):
            return _disabled_msg("w_apply_module", "W_AI_TOOL_APPLY")
        m = module.strip().lstrip("-")
        if not re.fullmatch(r"[a-z0-9-]+", m):
            return "(module must be a bare name like 'dns' or 'style')"
        return _actuate("apply-module", m, timeout=1800)

    @tool(mcp, domain=DOMAIN)
    def w_locale_set(
        locale: Annotated[str, desc("e.g. 'en_US.UTF-8', 'ru_RU.UTF-8'; must be enabled in locale.gen")],
    ) -> str:
        """Set the system locale / LANG (Tier 2: privileged; polkit prompt). Takes
        effect at the next login. Gated by W_AI_TOOL_LOCALE."""
        if not _tool_on("LOCALE"):
            return _disabled_msg("w_locale_set", "W_AI_TOOL_LOCALE")
        loc = locale.strip()
        if not re.fullmatch(r"[A-Za-z0-9@._-]+", loc):
            return "(invalid locale name, e.g. 'en_US.UTF-8')"
        return _actuate("locale-set", loc)

    @tool(mcp, domain=DOMAIN)
    def w_run(command: str) -> str:
        """Run an arbitrary shell command as root (Tier 2: privileged, DANGEROUS;
        polkit prompt on every call). Disabled by default — only usable once the user
        has set W_AI_TOOL_RUN=on in ai.conf. Prefer a specific tool
        (dns/firewall/pacman/apply) whenever one fits; reach for this only for one-off
        privileged operations no other tool covers."""
        if not _tool_on("RUN", default="off"):
            return _disabled_msg("w_run", "W_AI_TOOL_RUN")
        cmd = command.strip()
        if not cmd:
            return "(provide a command to run)"
        return _actuate("run", "/bin/sh", "-c", cmd, timeout=600)
