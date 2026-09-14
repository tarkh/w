# w-mcp domain: w-maintenance — recovery/update tools: btrfs/snapper snapshots and
# the edge-channel update (w-sync). Snapshot list and rollback guidance are Tier 0
# (read-only); sync apply is a curated Tier 2 action.
#
# Rollback is startable here but never PERFORMED here, and the distinction is the whole
# design. It used to be actuable, via `snapper rollback`, and that never worked on W's
# layout: snapper's rollback only repoints the btrfs default subvolume, while W boots
# with an explicit rootflags=subvol=@ — so the call returned success and changed nothing
# (verified on the encrypted VM, 2026-09-02; the Limine vendor tool refuses the same
# method for the same reason).
#
# What replaced it is not a fixed non-interactive call either. A rollback takes the whole
# system to an earlier state, and the procedure differs per boot path, so w_snapshot_
# rollback_start only OPENS it: `w-rollback launch` puts a terminal in front of the user
# where W's password window and the 'yes' confirmation are theirs to answer. The agent can
# start that conversation and can describe it; it cannot finish it. That is the same
# window the snapshot notice's button opens, through the same one verb, so the two cannot
# drift apart.
import subprocess
from typing import Annotated, Literal

from core import _actuate, _disabled_msg, _tool_on, desc, run, tool

DOMAIN = "w-maintenance"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_snapshot_list(config: Literal["root", "home"] = "root") -> str:
        """List btrfs/snapper snapshots of the system (root) or home (Tier 0,
        read-only)."""
        return run(["snapper", "-c", config, "list"])

    @tool(mcp, domain=DOMAIN)
    def w_snapshot_rollback_plan() -> str:
        """Where this machine stands for a rollback (Tier 0, read-only): its boot
        path, whether it is currently running from a snapshot, and the command the
        user would run. Pair with w_snapshot_list; the rollback itself is opened by
        w_snapshot_rollback_start once the USER has chosen."""
        return run(["w-rollback", "status"]) + (
            "\n\nWhen the user has chosen a snapshot, call w_snapshot_rollback_start with\n"
            "its number — that opens the rollback in a terminal for them to confirm.\n\n"
            "If the machine no longer boots at all, the snapshot is chosen in the boot\n"
            "menu first — the full procedure is in /usr/share/doc/w/RECOVERY.md."
        )

    @tool(mcp, domain=DOMAIN)
    def w_snapshot_rollback_start(
        number: Annotated[int, desc("snapshot number from w_snapshot_list, chosen by the USER; omit (-1) when booted from a snapshot and that is the one to restore")] = -1,
    ) -> str:
        """Open a rollback for the user to confirm (Tier 1: user-scope). It does
        NOT roll anything back itself: a terminal opens, W asks for the password,
        shows what will happen and waits for 'yes'. Never pick the snapshot for
        the user — only they know what since then still matters. Tell them a window
        has opened. Details: the w-maintenance skill."""
        if number < -1:
            return "(number must be a snapshot number from w_snapshot_list)"
        cmd = ["w-rollback", "launch"] + ([str(number)] if number >= 0 else [])
        try:
            subprocess.Popen(
                cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, start_new_session=True,
            )
        except FileNotFoundError:
            return "(w-rollback not found)"
        target = f"snapshot #{number}" if number >= 0 else "the booted snapshot"
        return (
            f"A terminal window is opening to roll back to {target}. Tell the user to "
            "expect W's password prompt, then a summary and a 'yes' confirmation — and "
            "that nothing changes until they confirm."
        )

    @tool(mcp, domain=DOMAIN)
    def w_sync_update(
        action: Annotated[Literal["plan", "apply"], desc("plan = read-only: incoming commits + channel state, run it FIRST; apply = privileged (polkit): pull + selective apply.sh")] = "plan",
    ) -> str:
        """Update W itself on the edge channel (Tier 2 on apply; polkit prompt).
        Two-step: plan → if the commit list looks risky or large, get the user's
        go-ahead → apply. A stable-channel machine gets a no-op message. Never
        reboots on its own, only reports that one is due. Gated by W_AI_TOOL_SYNC."""
        act = action.strip().lower()
        if act in ("", "plan"):
            return run(["w-sync", "log"], timeout=60) + "\n\n" + run(["w-sync", "status"])
        if not _tool_on("SYNC"):
            return _disabled_msg("w_sync_update", "W_AI_TOOL_SYNC")
        return _actuate("sync-update", timeout=1800)
