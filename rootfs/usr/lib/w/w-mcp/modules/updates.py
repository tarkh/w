# w-mcp domain: updates — pending-update checks (Tier 0) + the two-step system
# upgrade (Tier 2 apply, via com.w.ai.actuate).
from core import _actuate, _disabled_msg, _tool_on, prompt, run, tool

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
    def w_system_update(action: str = "plan") -> str:
        """Update the system's official-repo packages (Tier 2). Two-step by design so
        problems surface to the user instead of a blind auto-apply:

          action='plan'   (read-only, no prompt) — preflight: pending repo + AUR counts
                          and package lists, whether a kernel bump means a reboot, and
                          free disk. ALWAYS run this first and read it.
          action='apply'  (privileged; polkit prompt) — run the repo upgrade
                          non-interactively (`pacman -Syu`). snap-pac snapshots it, so
                          it is rollback-protected. It never reboots on its own.

        Workflow: plan → if anything looks risky (a kernel change, low disk, an unusually
        large/odd set, or fresh Arch news — check `w-update news`) tell the user and get
        a go-ahead → apply. If apply fails on a package conflict it returns the error;
        relay it and advise resolving it in a terminal rather than forcing it. If the
        result says a reboot is needed, tell the user — do not reboot for them.

        AUR packages are NOT applied here: yay must build them as the user and their
        PKGBUILD diffs deserve review. If the plan lists AUR updates, tell the user to
        run `w-update` in a terminal for those. Gated by W_AI_TOOL_UPDATE."""
        act = action.strip().lower()
        if act in ("", "plan"):
            return run(["w-update", "plan", "--porcelain"], timeout=120)
        if act != "apply":
            return "(action must be 'plan' or 'apply')"
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
