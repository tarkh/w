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

from core import _actuate, _disabled_msg, _tool_on, run, tool

DOMAIN = "w-maintenance"


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_snapshot_list(config: str = "root") -> str:
        """List btrfs/snapper snapshots. `config` is 'root' (system) or 'home'
        (default: root). Read-only."""
        cfg = config.strip().lower()
        if cfg not in ("root", "home"):
            return "(config must be 'root' or 'home')"
        return run(["snapper", "-c", cfg, "list"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_snapshot_rollback_plan() -> str:
        """Explain how to roll this machine back to a snapshot. Read-only: it reports
        which boot path the machine has and whether it is currently running from a
        snapshot, then gives the command the user must run themselves.

        Use w_snapshot_list to show the available snapshots and their dates, and this
        to see where the machine currently stands. The rollback itself is started with
        w_snapshot_rollback_start once the user has chosen — it opens a terminal where
        they authenticate and confirm; it is never completed on their behalf."""
        return run(["w-rollback", "status"]) + (
            "\n\nWhen the user has chosen a snapshot, call w_snapshot_rollback_start with\n"
            "its number — that opens the rollback in a terminal for them to confirm.\n\n"
            "If the machine no longer boots at all, the snapshot is chosen in the boot\n"
            "menu first — the full procedure is in /usr/share/doc/w/RECOVERY.md."
        )

    @tool(mcp, domain=DOMAIN)
    def w_snapshot_rollback_start(number: int = -1) -> str:
        """Open a rollback for the user to confirm (Tier 1: user-scope, opens a window;
        it does NOT roll anything back by itself). `number` is a snapshot from
        w_snapshot_list; omit it when the machine is booted from a snapshot and that is
        the one to restore.

        A terminal opens in the session: W's password window asks the user to
        authenticate, then the rollback shows exactly what it will do and waits for them
        to type 'yes'. Nothing changes unless they do, and the system being replaced is
        kept either way.

        Workflow: w_snapshot_list to show what is available -> let the USER say which one
        -> call this with that number -> tell them a window has opened and what it will
        ask. Never pick the snapshot for them: rolling back takes the whole system to an
        earlier state, and only they know what since then still matters."""
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
    def w_sync_update(action: str = "plan") -> str:
        """Update W itself on the edge channel (git-checkout install), two-step like
        w_system_update:

          action='plan'  (read-only, no prompt) — fetches and shows incoming commits
                         plus the current channel/state. ALWAYS run this first. On a
                         'stable' channel machine this returns a clear no-op message
                         (edge-only feature) instead of doing anything.
          action='apply' (privileged; polkit prompt) — fetch, snapshot ~/home,
                         `git pull --ff-only`, then a selective `apply.sh` for only
                         the changed modules. Never reboots on its own even if the
                         pulled release requests one — it only reports that.

        Workflow: plan → if the commit list looks risky or large, tell the user and
        get a go-ahead → apply. Gated by W_AI_TOOL_SYNC."""
        act = action.strip().lower()
        if act in ("", "plan"):
            return run(["w-sync", "log"], timeout=60) + "\n\n" + run(["w-sync", "status"])
        if act != "apply":
            return "(action must be 'plan' or 'apply')"
        if not _tool_on("SYNC"):
            return _disabled_msg("w_sync_update", "W_AI_TOOL_SYNC")
        return _actuate("sync-update", timeout=1800)
