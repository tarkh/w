# w-mcp domain: notifications — W's notification subsystem (w-notify). Read the DND
# state and the history of what arrived (Tier 0), silence the desktop for a while and
# mute a noisy app (Tier 1). Everything here is user-scope: the notification stack is
# the invoking user's own session, so there is no polkit and no capability — exactly
# the power the user already has at their own shell.
#
# Sending a notification lives in the desktop domain (w_notify), not here: this module
# is about the notification SYSTEM, that tool is about surfacing one message.
# See the w-notifications skill / quickshell-notifications.md + w-notify.md.
from typing import Annotated, Literal

from core import desc, run, tool

DOMAIN = "w-notifications"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_notifications_status() -> str:
        """Notification state (Tier 0, read-only): DND on/off and until when,
        whether critical passes it, auto-DND while fullscreen, popup timeouts and
        stacking, the OSD switch, muted apps, history size. Ground every "am I
        muted / why didn't I see X / did I miss anything" question here first."""
        return run(["w-notify", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_notifications_history(
        limit: Annotated[int, desc("how many to return")] = 20,
        missed_only: Annotated[bool, desc("only alerts suppressed by DND or a mute")] = False,
    ) -> str:
        """Recent notifications, newest first, as `HH:MM <app> <summary>` (Tier 0,
        read-only); `·` marks one that never reached the screen (still recorded —
        that is what answers "what did I miss?"). Records only: their actions died
        with the popup, so report them but never "click" or dismiss them."""
        n = max(1, min(int(limit), 200))
        if not missed_only:
            return run(["w-notify", "history", "-n", str(n)])
        # Porcelain is TSV (ts, app, urgency, suppressed, summary, body) — filter on the
        # suppressed column rather than making the model eyeball the `·` marker.
        raw = run(["w-notify", "history", "--porcelain", "-n", str(n)])
        out = []
        for line in raw.splitlines():
            parts = line.split("\t")
            if len(parts) >= 5 and parts[3] == "1":
                out.append(f"{parts[1]}: {parts[4]}")
        return "\n".join(out) if out else "(nothing was suppressed)"

    # ── Tier 1 — user-scope, reversible, no privilege ────────────────────────
    @tool(mcp, domain=DOMAIN)
    def w_notifications_dnd(
        state: Literal["on", "off", "toggle"],
        minutes: Annotated[int, desc("with state=on: deadline after which DND lapses by itself; use it whenever the user names a duration, an indefinite DND is the one they forget")] = 0,
    ) -> str:
        """Turn Do Not Disturb on or off (Tier 1: user-scope, no polkit). DND hides
        popups but drops nothing — everything lands in the history, and critical
        alerts still come through unless that was switched off."""
        s = state
        if s == "on" and minutes > 0:
            return run(["w-notify", "dnd", "for", f"{int(minutes)}m"])
        return run(["w-notify", "dnd", s])

    @tool(mcp, domain=DOMAIN)
    def w_notifications_mute(
        app: Annotated[str, desc("the name the app announces itself under — take it from w_notifications_history, apps spell it their own way")],
        muted: Annotated[bool, desc("false = unmute")] = True,
    ) -> str:
        """Mute or unmute one app's notifications (Tier 1: user-scope, no polkit).
        A mute is absolute and lasting: no deadline, and critical does NOT bypass it.
        Muted alerts are still recorded in the history."""
        name = app.strip()
        if not name:
            return "(name the app to mute — see w_notifications_history)"
        return run(["w-notify", "mute" if muted else "unmute", name])
