# w-mcp domain: packs — optional software bundles (W-Packs): list/status (Tier 0)
# + install and engine upgrade (Tier 2, via com.w.ai.actuate).
import re
from typing import Annotated, Literal

from core import _actuate, _disabled_msg, _tool_on, desc, run, tool

DOMAIN = "w-packs"


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_pack_list() -> str:
        """The optional software bundles (W-Packs) and each one's state (Tier 0,
        read-only). Three states: `[installed]` = ready for this account;
        `[machine]` = on the machine but this account's half is not set up (fix:
        unprivileged `w-pack setup <bundle>`, never report it as "installed");
        `[ ]` = absent, needs an administrator. To operate an installed bundle,
        read its own skill."""
        return run(["w-pack", "list"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_pack_status(
        bundle: Annotated[str, desc("one bundle; omit for every installed one")] = "",
    ) -> str:
        """W-Pack install state (Tier 0, read-only): whether the machine has it, when
        it was installed, and whether this account has been through its per-user
        layer."""
        cmd = ["w-pack", "status"]
        if bundle.strip():
            cmd.append(bundle.strip())
        return run(cmd)

    @tool(mcp, domain=DOMAIN)
    def w_pack_install(
        bundle: Annotated[str, desc("one bundle name from w_pack_list, e.g. 'containers'")],
    ) -> str:
        """Put an optional software bundle (W-Pack) on the machine — packages,
        config, setup (Tier 2: privileged; polkit prompt). Idempotent; AUR-heavy
        bundles take a while. Not for a bundle already `[machine]` — that account
        only needs unprivileged `w-pack setup <bundle>`."""
        if not _tool_on("PACKS"):
            return _disabled_msg("w_pack_install", "W_AI_TOOL_PACKS")
        b = bundle.strip()
        if not b:
            return "(name a bundle to install; see w_pack_list)"
        if not re.fullmatch(r"[a-z0-9-]+", b):
            return "(bundle must be a bare name like 'containers')"
        return _actuate("pack-install", b, timeout=1800)

    @tool(mcp, domain=DOMAIN)
    def w_pack_upgrade(
        action: Annotated[Literal["plan", "apply"], desc("plan = read-only: installed vs target engine version per bundle, run it FIRST; apply = privileged (polkit) `w-pack upgrade <bundle>`")] = "plan",
        bundle: Annotated[str, desc("one bundle; plan may omit it (all), apply requires it")] = "",
    ) -> str:
        """Upgrade a pack's engine installed outside pacman (comfyui, invokeai) —
        Tier 2 on apply (polkit prompt). Two-step: plan → tell the user the move
        and its cost, get an explicit go-ahead → apply. Apply stops the engine
        (minutes, may download GBs) and rolls back by itself on failure; a busy
        engine refuses. Workflow: the w-packs skill. Gated by W_AI_TOOL_PACKS."""
        b = bundle.strip()
        if b and not re.fullmatch(r"[a-z0-9-]+", b):
            return "(bundle must be a bare name like 'comfyui')"
        act = action.strip().lower()
        if act in ("", "plan"):
            return run(["w-pack", "outdated", *([b] if b else [])], timeout=120)
        if not _tool_on("PACKS"):
            return _disabled_msg("w_pack_upgrade", "W_AI_TOOL_PACKS")
        if not b:
            return "(name the bundle to upgrade; see w_pack_upgrade('plan'))"
        return _actuate("pack-upgrade", b, timeout=3600)
