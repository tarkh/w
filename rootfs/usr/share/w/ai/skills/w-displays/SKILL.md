---
name: w-displays
description: >-
  Displays on W: the monitor layout (resolution, refresh, scale, rotation, placement,
  the primary output) via `w-monitor` and the Hub's Displays panel, the separate
  login-screen scope, and the night light / blue-light filter (`w-nightlight`,
  hyprsunset). Load this for anything about monitors, resolution or scaling, a black
  screen after a display change, or warming the screen in the evening.
sources:
  - path: .claude/library/w-monitor.md
    sha256: 1e4168494d14166436d8af5c591ee9d85b189a60daf96c9fb6e0341caf5c0fc5
  - path: .claude/library/w-nightlight.md
    sha256: 188429cc8a36233d3fa8b55fc0bcd8a16e56a1463ac04b78782d7b8cd447bd03
tools:
  - w_monitor_status
  - w_nightlight_status
  - w_nightlight_set
---

# W Displays

Two subsystems that answer the same question — *what the screen physically looks
like* — and share one Hub panel (**Displays**): the **monitor layout** (`w-monitor`)
and the **night light** (`w-nightlight`). Everything here is user-scope, with one
exception called out below: the login screen's own monitor layout needs root.

The compositor, the bar and the rest of the shell UI are the **w-desktop** skill;
reopening windows at login is **w-session**.

## Displays

Monitor layout — resolution/refresh, scale, rotation, on/off, native `auto-*`
placement (right/left/above/below the existing chain — no pixel math), and the
**primary monitor** (a W concept — which output carries the bar, and separately the
login card; Hyprland has no "primary"). Backed by `~/.config/hypr/monitors.lua` (the
fragment is the source of truth, not `hyprctl`) and managed by the `w-monitor` CLI /
the Hub's Displays panel (tab "Session"). A second, fully independent scope covers the
login screen (`w-monitor greeter ...`, root + polkit) — the Hub's "Login screen" tab.

Changing scale also resizes the **lock screen** (hyprlock): its widgets are scale-aware
and drawn only on the primary output, so a `w-monitor scale`/`primary` change lands at
the *next* lock (no reload — hyprlock rereads its config each time).

Read the current layout with **`w_monitor_status`** (Tier 0). There is deliberately no
monitor-mutation tool: a change is `w-monitor <cmd> <output> ...` in the shell (rootless
— the session is the user's own); the login screen's layout is a separate config
needing `sudo`/root. **Before a mutating
command, match what the user said to an output name `w_monitor_status` returned; if it
doesn't map unambiguously** (an unfamiliar name, "the left one" with two
candidates, a disconnected output) **ask which one they mean** — a
wrong `disable`/`primary` turns off a screen they may be looking at.

`disable` refuses the primary output and the last one still drawing, so it cannot black
the machine out. **A black screen after a display change** is a settings file, not a
broken system: from a text console (Ctrl+Alt+F2), `w-monitor reset --all` (+ `sudo
w-monitor greeter reset` for the login screen). Never a rollback.

## Night light (blue-light filter)

Warms the screen to cut blue light in the evening. The engine is **hyprsunset**, which
shifts the compositor's colour transform rather than drawing a shader — so the tint is
**not captured by screenshots or screen recording**, and it costs nothing per frame.

Managed by `w-nightlight` and the Hub's Displays panel, segment "Night light". Five
settings, all user-scope (no root, no polkit anywhere in this subsystem):

- **mode** — `off`, `schedule` (warm inside the night window), or `always`.
- **temperature** — kelvin for the night; lower is warmer. 4300 is the default, 3000 is
  clearly amber, 2000 is candlelight.
- **day temperature** — the other end of the transition, i.e. what the screen returns to
  when the window closes. Default **6600**, which is the value whose colour matrix comes
  closest to leaving the screen alone (6000, which W used to call "neutral", is a 7%
  cut on blue — a filter you can see). At exactly 6600 the daytime state drops the colour
  matrix outright; any other value is a real tint that stays on all day, which is the
  point for someone who wants a permanently warmer or cooler screen. It is **not** an off
  switch — `mode off` always means an untouched screen whatever this says.
- **the night window** — a start and an end time, `HH:MM`. Crossing midnight (21:00 →
  07:00) is normal and needs nothing special. The two must differ; a zero-length window
  is `mode always`, not a schedule. W uses fixed wall-clock times, not solar
  sunset/sunrise — hyprsunset has no notion of location and W ships no geolocation.
- **transition time** — how long the SCHEDULED change between day and night takes, in
  minutes (default 30, `0` = instant). Set it with `w-nightlight transition <minutes>`.
  It does not pace anything else: turning the filter on or off, changing a setting
  mid-transition, or catching up after a suspend all ease across in about two seconds, so
  a switch the user just flipped never makes them wait half an hour — and never jumps.

`off` does **not** stop the daemon; it pushes the identity matrix. So the filter can
always be toggled and previewed instantly, and there is only one place the state lives:
the config.

**Two user units, with different jobs.** `w-nightlight-tick.timer` re-evaluates once a
minute and notices that the screen and the schedule have parted company; the transition
itself belongs to `w-nightlight-ramp.service`, which is started on demand, steps the
temperature, and exits as soon as it has arrived. The ramp unit is deliberately never
enabled — seeing it inactive is normal and means nothing is in transition.

The timer is the first thing to check when a user says *"it does not turn on by itself"*
or *"it was still warm this morning although the window had closed"* — the settings can
be perfectly right while nothing is evaluating them:

```
systemctl --user is-active w-nightlight-tick.timer   # expect: active
systemctl --user list-timers w-nightlight-tick.timer # expect a NEXT time within a minute
```

If it is inactive, the schedule is simply not running and only manual changes (the Hub,
the `Super+Shift+N` toggle) will move the screen. Starting it (`systemctl --user start
w-nightlight-tick.timer`) fixes the current session; if it comes back inactive after the
next login, that is a bug worth reporting, not a user setting.

Two facts worth stating to the user rather than assuming they know them:

1. **"Mode is schedule" does not mean the screen is warm right now.** Setting `schedule`
   at 3pm changes nothing visible until the window opens. `w_nightlight_status` reports
   whether it is filtering *right now* — quote that, not just the mode. During a
   transition it also reports the value currently on screen, which is *between* neutral
   and the night temperature; report that rather than the destination.
2. **The login screen stays neutral.** The night light lives in the user's session; the
   greeter is a separate compositor. This is a known limitation, not a fault.

The keybinding `Super+Shift+N` runs `w-nightlight toggle` (off ↔ schedule).

## Display tools (via `w-mcp`)

When `w-mcp` is connected you can perceive and act inside the running session. These
are **user-scope** (no privilege — the same power the user's own shell has), so no
polkit prompt is involved; the host's tool-approval covers them.

- **`w_monitor_status`** *(read)* — full monitor layout: every output's live mode/
  scale/rotation/position, enabled/focused/primary, its saved `w-monitor` rule, and
  a handful of its available modes. Use it for "what monitors do I have" / "what's
  my resolution/scale" and before running any `w-monitor` command — see **Displays**
  above for the ask-before-guessing rule on output names.
- **`w_nightlight_status`** *(read)* — the night light: mode, night temperature, the
  window, and whether the screen is being tinted **right now**. Correct even with no
  session reachable from here (it is derived from the config, not asked of the daemon).
- **`w_nightlight_set`** — change it: any combination of `mode`, `temperature`,
  `start`+`end` (both together). Applies immediately and returns the resulting status.
  If the user asks for `schedule` outside the night window, tell them the screen will
  not change until it opens — otherwise "done" reads as "and nothing happened".
