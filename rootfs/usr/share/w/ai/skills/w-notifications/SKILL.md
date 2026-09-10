---
name: w-notifications
description: >-
  Desktop notifications on W Linux: Do Not Disturb (including timed "quiet for an
  hour"), the history of what arrived — and of what was hidden — per-app muting,
  popup timeouts and the volume/brightness OSD. Load this for anything about being
  disturbed or not disturbed, notifications that did or did not appear, "what did I
  miss", silencing a noisy app, or how long a popup stays on screen.
sources:
  - path: .claude/library/w-notify.md
    sha256: 6f1eba564188c4f3b28b3b2d4d48924c3015136f7f8f2ec895f0e72a8806fa7c
  - path: .claude/library/quickshell-notifications.md
    sha256: 6e5b84c107724c7c5d8737cc4801bb9f43a9bd275deaecb2bfb250aa35516a31
tools:
  - w_notifications_status
  - w_notifications_history
  - w_notifications_dnd
  - w_notifications_mute
---

# W Notifications

W's shell **is** the freedesktop notification server (no dunst/mako). The subsystem is
driven by one CLI, **`w-notify`**, which the Hub panel, the bar indicator, the
`Super+Shift+D` hotkey and your tools all go through.

Start with **`w_notifications_status`** — it prints the whole live state (DND and its
deadline, whether critical passes through, auto-DND while fullscreen, the per-urgency
timeouts, muted apps, history size). Ground every answer there instead of guessing.

## What DND actually does

**It hides popups. It never drops notifications.** Everything that arrives while DND is
on is still written to the history, flagged as suppressed — so "what did I miss?" is
always answerable (`w_notifications_history(missed_only=True)`).

- `critical` alerts still come through by default (`dnd critical off` changes that).
- A **per-app mute** is stricter than DND: it has no deadline and critical does **not**
  bypass it, because muting an app is a deliberate choice rather than a temporary mood.
- Turning DND on does not clear popups already on screen — it applies to incoming ones.

**Prefer a deadline over an open-ended DND.** When the user names a duration ("for an
hour", "until the meeting ends"), pass `minutes` to `w_notifications_dnd` — an
indefinite DND is the one people forget they left on and then miss things for days. If
they ask for silence with no duration, it is fair to say how to end it (the bar's bell
glyph, `Super+Shift+D`, or asking you again).

## History is a record, not a live inbox

Entries carry time, app, urgency, summary/body and the suppressed flag. Their actions
died with the popup, and the notification's image is a temporary pixmap whose path is
already stale — so you can summarize and report history, but you can never re-open,
click or dismiss an entry. Do not offer to.

`w_notifications_history` takes `limit` and `missed_only`. For "did anything happen
while I was away", `missed_only=True` is usually the honest answer, not the whole list.

In **Hub → Notifications** the same records are listed grouped by day — a divider reads
"Today" / "Yesterday" / the date, and each row carries only the time. Worth mentioning
when you point someone at the list to find something older than today.

## Muting an app

Take the app name from the history (`w_notifications_history`) rather than inventing it
— apps announce themselves under their own spelling and change it between releases.
Matching is case-insensitive. `w_notifications_mute(app, muted=False)` unmutes.

Mute is the right answer for "this app keeps bothering me"; DND is the right answer for
"not right now". Do not reach for `timeout` changes to make something less annoying —
that is a global setting and affects every app.

## Sending a notification

That is `w_notify` in the **w-desktop** skill (it routes through `w-notify send`). The
one rule worth repeating here: `urgency="critical"` is only for an alert the user must
act on — a reboot owed after an upgrade, a nearly full disk, a failed backup. Critical
is red, never auto-dismisses, and is the only level that pierces DND. Every needless
critical trains the user to ignore the next one.

## What is deliberately not there

No notification **sound** (W is silent by design for now), no scheduled quiet hours, no
grouping/threading, and no inline replies or action buttons on cards. If a user asks,
say it is not implemented rather than improvising a workaround.

## Beyond the tools

Everything else is CLI-only and belongs to the user: `w-notify timeout <level> <ms>`
(0 = never auto-dismiss), `w-notify max <n>` (how many popups stack), `w-notify osd
on|off` (the volume/brightness indicator), `w-notify dnd fullscreen on|off`, and
`w-notify history clear`. Tell the user the command, or point them at **Hub →
Notifications**, which exposes all of it.
