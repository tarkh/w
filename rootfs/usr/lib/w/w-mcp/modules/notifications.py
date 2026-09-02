# w-mcp domain: notifications — W's notification subsystem (w-notify). Read the DND
# state and the history of what arrived (Tier 0), silence the desktop for a while and
# mute a noisy app (Tier 1). Everything here is user-scope: the notification stack is
# the invoking user's own session, so there is no polkit and no capability — exactly
# the power the user already has at their own shell.
#
# Sending a notification lives in the desktop domain (w_notify), not here: this module
# is about the notification SYSTEM, that tool is about surfacing one message.
# See the w-notifications skill / quickshell-notifications.md + w-notify.md.
from core import run, tool

DOMAIN = "w-notifications"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_notifications_status() -> str:
        """Notification state (via `w-notify status`): whether Do Not Disturb is on and
        until when, whether critical alerts pass through it, auto-DND while fullscreen,
        the per-urgency popup timeouts, how many popups may stack, whether the volume /
        brightness OSD is enabled, which apps are muted, and how many notifications are
        recorded. Read-only. Ground every 'am I muted / why didn't I see X / did I miss
        anything' question here before answering."""
        return run(["w-notify", "status"])

    @tool(mcp, domain=DOMAIN)
    def w_notifications_history(limit: int = 20, missed_only: bool = False) -> str:
        """Recent notifications, newest first (via `w-notify history`), as
        `HH:MM <app> <summary>`. A `·` marks an alert that never reached the screen
        because DND or a per-app mute suppressed it — suppressed alerts are still
        recorded, which is what makes 'what did I miss?' answerable. `limit` caps how
        many are returned; `missed_only` keeps just the suppressed ones. Read-only.

        These are RECORDS, not live notifications: their actions died with the popup, so
        you can report and summarize them but never 'click' or dismiss them."""
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
    def w_notifications_dnd(state: str, minutes: int = 0) -> str:
        """Turn Do Not Disturb on or off (Tier 1: user-scope, no polkit). `state` is
        'on', 'off', or 'toggle'. With `state='on'`, a non-zero `minutes` sets a deadline
        after which DND lapses on its own — always prefer a deadline when the user names
        a duration ('for an hour', 'while I'm in the meeting'), because an indefinite DND
        is the one people forget they left on.

        DND hides popups; it never drops notifications — everything still lands in the
        history, and critical alerts keep coming through unless that was turned off. Use
        w_notifications_status to report what is currently set."""
        s = state.strip().lower()
        if s not in ("on", "off", "toggle"):
            return "(state must be 'on', 'off', or 'toggle')"
        if s == "on" and minutes > 0:
            return run(["w-notify", "dnd", "for", f"{int(minutes)}m"])
        return run(["w-notify", "dnd", s])

    @tool(mcp, domain=DOMAIN)
    def w_notifications_mute(app: str, muted: bool = True) -> str:
        """Mute or unmute one app's notifications by its app name (Tier 1: user-scope,
        no polkit). `app` must match the name the app announces itself under — take it
        from w_notifications_history rather than guessing, since apps spell it their own
        way. `muted=False` unmutes.

        A mute is absolute and lasting: unlike DND it has no deadline and critical alerts
        do NOT bypass it, because muting an app is a deliberate choice rather than a
        temporary mood. Muted alerts are still recorded in the history."""
        name = app.strip()
        if not name:
            return "(name the app to mute — see w_notifications_history)"
        return run(["w-notify", "mute" if muted else "unmute", name])
