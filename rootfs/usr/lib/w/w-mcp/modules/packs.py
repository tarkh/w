# w-mcp domain: packs — optional software bundles (W-Packs): list/status (Tier 0)
# + install (Tier 2, via com.w.ai.actuate).
import re

from core import _actuate, _disabled_msg, _tool_on, run, tool

DOMAIN = "w-packs"


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_pack_list() -> str:
        """List the optional software bundles (W-Packs) available on this machine and
        the state of each (via `w-pack list`). Bundles are opt-in add-ons by direction
        — containers, dev, gaming, … — on top of the base system.

        A bundle has two layers, so there are THREE states, not two: `[installed]` =
        ready for this account; `[machine]` = on the machine but this account's own
        half (its tools in ~/.local/bin, its home config) is not set up — the fix is
        the un-privileged `w-pack setup <bundle>`, no sudo; `[ ]` = not on the machine
        at all, which needs an administrator. Never report `[machine]` as simply
        "installed". To operate an installed bundle, load its own skill (curated under
        skills/<bundle>)."""
        return run(["w-pack", "list"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_pack_status(bundle: str = "") -> str:
        """Show W-Pack install state (via `w-pack status`). With `bundle`, report just
        that one — whether the machine has it, when it was installed, and whether the
        invoking account has been through its per-user layer; without, list all
        installed bundles, flagging any the account is not set up for. Read-only."""
        cmd = ["w-pack", "status"]
        if bundle.strip():
            cmd.append(bundle.strip())
        return run(cmd)

    @tool(mcp, domain=DOMAIN)
    def w_pack_install(bundle: str) -> str:
        """Install an optional software bundle (W-Pack) — packages + config + w-style +
        setup (Tier 2: privileged; polkit prompt). `bundle` is a single bundle name
        from w_pack_list (e.g. 'containers'). Idempotent; heavy bundles (AUR builds)
        can take a while. After it installs, the bundle's own skill is curated into the
        knowledge base.

        Use this only to put a bundle ON THE MACHINE. If w_pack_list already reports
        it as `[machine]`, the machine half is done and installing again is the wrong
        move — that account just needs `w-pack setup <bundle>` in a shell, which needs
        no privilege and no prompt."""
        if not _tool_on("PACKS"):
            return _disabled_msg("w_pack_install", "W_AI_TOOL_PACKS")
        b = bundle.strip()
        if not b:
            return "(name a bundle to install; see w_pack_list)"
        if not re.fullmatch(r"[a-z0-9-]+", b):
            return "(bundle must be a bare name like 'containers')"
        return _actuate("pack-install", b, timeout=1800)
