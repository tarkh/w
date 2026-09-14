# w-mcp domain: updates — pending-update checks (Tier 0) + the two-step system
# upgrade (Tier 2 apply, via com.w.ai.actuate).
from typing import Annotated, Literal

from core import _actuate, _disabled_msg, _tool_on, desc, prompt, run, tool

DOMAIN = "w-updates"


def register(mcp):
    @prompt(mcp, domain=DOMAIN)
    def update_system() -> str:
        """Recipe: the safe two-step system update (plan → review → apply)."""
        return (
            "Update this machine's official-repo packages safely, in two steps:\n"
            "1. Call w_system_update('plan') and read it: pending repo/AUR counts, whether a "
            "kernel bump forces a reboot, and free disk.\n"
            "2. If anything looks risky — a kernel change, low disk, an unusually large or odd "
            "set, or fresh Arch news (check `w-update news`) — summarize it for the user and get "
            "an explicit go-ahead.\n"
            "3. On go-ahead, call w_system_update('apply') (polkit will prompt the user). Relay "
            "any package conflict verbatim and advise resolving it in a terminal, not forcing it.\n"
            "4. Report whether a reboot is now needed and whether any AUR updates remain (those "
            "are a manual `w-update` job). Never reboot for the user."
        )

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_updates_check() -> str:
        """Check for available package updates (repo + AUR), refresh the status file
        the bar reads, and return the fresh counts. Non-privileged: never runs
        `pacman -Sy`."""
        # `w-update check` only rewrites the state file (silent, by design — it feeds
        # the bar). Read it back via `status` so the model gets the just-refreshed
        # numbers instead of an empty reply and falling back to a stale cached count.
        run(["w-update", "check"], timeout=120)
        return run(["w-update", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_system_update(
        action: Annotated[Literal["plan", "apply"], desc("plan = read-only preflight (pending repo/AUR, kernel change → reboot, free disk), run it FIRST; apply = privileged (polkit) `pacman -Syu`, snap-pac protected")] = "plan",
    ) -> str:
        """Update the official-repo packages (Tier 2 on apply; polkit prompt).
        Two-step: plan → if anything looks risky (kernel change, low disk, odd set,
        Arch news) get the user's go-ahead → apply. Never reboots on its own —
        report a reboot as owed. AUR is not applied here (the user runs `w-update`
        in a terminal). Workflow: the w-updates skill. Gated by W_AI_TOOL_UPDATE."""
        act = action.strip().lower()
        if act in ("", "plan"):
            return run(["w-update", "plan", "--porcelain"], timeout=120)
        if not _tool_on("UPDATE"):
            return _disabled_msg("w_system_update", "W_AI_TOOL_UPDATE")
        result = _actuate("system-upgrade", timeout=1800)
        # Post-apply, back as the user: refresh the bar's status and assemble a short
        # report — is a reboot now needed, are there .pacnew files to merge, is any AUR
        # still pending (a manual/terminal job)?
        run(["w-update", "check"], timeout=120)
        plan = run(["w-update", "plan", "--porcelain"], timeout=120)
        pacnew = run(["sh", "-c", "find /etc -name '*.pacnew' 2>/dev/null | wc -l"]).strip()
        return f"{result}\n\n--- post-update ---\nstatus: {plan}\n.pacnew files to review: {pacnew}"
