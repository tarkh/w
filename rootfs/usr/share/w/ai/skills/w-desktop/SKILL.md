---
name: w-desktop
description: >-
  The W Linux desktop: the Hyprland (Wayland) compositor with a Lua config, the
  uwsm-managed systemd session, the single Quickshell UI (bar, launcher, notifications,
  OSD, lock, greeter), key bindings, and screenshots. Load this for anything about
  the desktop, window management, keybindings, the bar/launcher, or the shell UI.
sources:
  - path: .claude/library/package-hyprland.md
    sha256: 8fcbce2ca1880119b352caba9f94b4048e8ff0e8ac3a8915ae326bdb9ec5f9fc
  - path: .claude/library/quickshell.md
    sha256: b6b033f37c6605ab5ec12ecbad15bef136f7334337d88aafaed06e0561b97376
  - path: .claude/library/quickshell-bar.md
    sha256: 172fcf47c0789b0b684968235fb741ff9c0de3cd09887d2a0648c5ba66c335ed
  - path: .claude/library/w-bar.md
    sha256: 6888e3edff28e8ee62198014579587888eccf481c218320a9993afd759238591
  - path: .claude/library/quickshell-assistant.md
    sha256: 4d3098dde3047c6d5b7057911ca6393be05627792968b4f46a3542b69f18bb33
  - path: .claude/library/w-monitor.md
    sha256: 0e6b20d604c4cca1d35244736eb74c21cd6b26652f6b54fba67530dc07b4d5bc
  - path: .claude/library/w-nightlight.md
    sha256: 46c8114641bb1f6416de5b40456885db58c359647759d827d802593c764c2072
  - path: .claude/library/w-session.md
    sha256: 94096911278f58e598efc2958ad21c49d508a39e442d94bbfb3a58807f367074
  - path: .claude/library/quickshell-layouts.md
    sha256: 61e8015efd56cad555527ac27253d8261731379c703b7e25f9b8799fab142149
  - path: .claude/library/quickshell-keyboard.md
    sha256: dc74f0589ce0eb8f24ebddd8f3c8bbb5aa1cd2b21ce63e2b5f6d3a472aa1b0c8
tools:
  - w_desktop_context
  - w_notify
  - w_screenshot
  - w_launch_app
  - w_hypr_windows
  - w_hypr_dispatch
  - w_monitor_status
  - w_bar_status
  - w_bar_set
  - w_nightlight_status
  - w_nightlight_set
  - w_session_status
  - w_session_set
  - w_layouts_list
  - w_layout_save
  - w_layout_apply
---

# W Desktop

The desktop is **Hyprland** (a Wayland compositor) driving a single **Quickshell** UI.
There is no widget zoo: the bar, launcher, notifications, on-screen display, lock screen,
and login greeter are all one `quickshell -c w` instance.

## Session

The user session is **systemd-managed via uwsm**: the compositor is the user service
`wayland-wm@hyprland.service`, with a proper `graphical-session.target` and logs in
journald. Diagnose it with `systemctl --user status wayland-wm@hyprland.service` and
`journalctl --user -b` (see the `w-diagnostics` skill).

## Hyprland configuration (Lua)

Since Hyprland 0.55 the compositor config is **Lua**, not the old hyprlang `.conf`:

- Main config: `~/.config/hypr/hyprland.lua`.
- Options are set with `hl.config({ category = { key = val } })`, binds with
  `hl.bind(...)`, rules with `hl.window_rule{...}` / `hl.layer_rule{...}`, autostart with
  `hl.on("hyprland.start", ...)`.
- ⚠️ The dispatch syntax changed: `hyprctl dispatch` now takes a Lua expression, e.g.
  `hyprctl dispatch 'hl.dsp.global("quickshell:launcher")'`. The old
  `dispatch global quickshell:launcher` form no longer works.
- Themed values (colors, geometry, effects, animations) are **not** hardcoded — they live
  in generated Lua fragments (`colors.lua`, `geometry.lua`, `effects.lua`,
  `animations.lua`) that `hyprland.lua` `require`s, rendered by `w-style` (see the
  `w-theming` skill). Editing those by hand will be overwritten on the next theme render.
- Per-subsystem settings live in their own `require`d fragments, each owned by one CLI
  and rewritten by it: `keyboard.lua` (layouts + auto-repeat, `w-keyboard`),
  `pointer.lua` (mouse/touchpad/swipe gestures + cursor idle-hide timeouts, `w-pointer`), `monitors.lua`
  (`w-monitor`), `hotkeys.lua` (`w-hotkeys`). Each fragment — not the live compositor —
  is the source of truth, so the CLIs are correct even from a TTY; hand-edits are
  overwritten. Use the CLI (see the `w-input` skill), never a hand edit.
- The rest of the hypr* ecosystem (`hyprlock.conf`, `hypridle.conf`, `hyprpaper.conf`,
  `hyprsunset.conf`, `xdph.conf`) stays on hyprlang. Two of those are **generated** and
  must not be hand-edited: `hypridle.conf` (by `w-power`) and `hyprsunset.conf` (by
  `w-nightlight`) — `hypridle.conf` is rewritten wholesale on every setter, but
  `hyprsunset.conf` deliberately ships with no profile at all and is only rewritten when
  the daemon itself (re)starts; every night-light value change goes out live over
  `hyprctl hyprsunset` IPC instead (hyprsunset has its own internal scheduler that can
  silently reassert whatever it parsed at startup, so giving it nothing to reassert is
  the fix — see the `w-nightlight.md` library entry if you need the full story).

> For precise, up-to-date Hyprland config syntax (options, binds, rules, animations,
> layouts, hyprctl/IPC), consult the **`hyprland` skill** — a navigator over a local copy
> of the official Hyprland wiki. Do not rely on memorized syntax; the Lua API changes
> quickly.

## Key bindings (`$mod` = Super)

These are the **default** chords; bindings are data-driven and user-remappable, so a
given machine may differ. For *configuring* input — remapping keys and profiles
(`w-hotkeys`), keyboard layouts (`w-keyboard`), and the system locale (`w-locale`) —
see the **`w-input`** skill; the table below is just a quick reference.

| Binding | Action |
|---|---|
| `Super+Return` | Terminal (Ghostty) |
| `Super+D` | Launcher |
| `Super+Space` | W Hub (settings + control center) |
| `Super+W` | Ask W — the assistant palette |
| `Super+V` | Clipboard history |
| `Super+A` | Volume control |
| `Super+Backspace` | Power menu (lock/logout/suspend/reboot/shutdown) |
| `Super+L` | Lock screen |
| `Super+E` / `Super+B` | Files (Nemo) / Browser (Firefox) |
| `Super+Q` / `Super+Shift+Q` | Close window / force-kill |
| `Super+F` / `Super+M` | Fullscreen / maximize |
| `Super+Shift+Space` | Toggle floating |
| `Super+1..0` | Switch workspace (1–10) |
| `Super+Shift+1..0` | Move window to workspace |
| `Super+arrows` / `Super+Shift+arrows` | Move focus / move window |
| `Super+I` / `Super+Shift+I` / `Super+Ctrl+I` | Screenshot output / region / window |
| `Super+Shift+D` | Do Not Disturb on/off |
| `Super+Shift+N` | Night light on/off (off ↔ scheduled) |
| `Super+S` / `Super+Shift+S` | Scratchpad toggle / send window |

### Keyboard navigation inside menus/popups

Once a Quickshell surface is open, it is keyboard-first: arrows (or the `i3-vim`
profile's `h`/`j`/`k`/`l`) move a roving-focus cursor, `Enter`/`Space` activates,
`Esc` closes. This runs on the same rebindable "menu" hotkeys category
(`menu_up/down/left/right/confirm/back/delete` — see the **`w-input`** skill) as
the Hub itself, and covers **every** popup outside it — volume, brightness, auth
prompt, calendar, infobox, file picker, launcher, clipboard, assistant, layouts.

A hidden pointer (`cursor.menu_timeout`) stops highlighting what is under it, so it
never competes with the roving focus.

**In a panel with a text field** (launcher, clipboard, assistant, layouts, the
Hub's search pickers, the password prompt) **the same chords act with Ctrl** —
`Ctrl+j`/`Ctrl+k` on `i3-vim`, since a bare letter would be typed into the field;
arrows, Enter and Esc stay bare on every profile, and deleting is `Shift+Del`. A
profile switched from a terminal is picked up live by every open panel.

Three deliberate exceptions keep their own scheme: the **Power Menu** has a fixed
single-letter mnemonic per tile (`L`/`E`/`R`/`S`, `Ctrl+S`=shutdown) — migrating
would collide with `i3-vim`'s `menu_right=L`, so it stays hardcoded on purpose;
the **tray context menu** (right-click applet menus like nm-applet) is mouse-only
by nature, opening only from a tray-icon click; the **login greeter** runs its own
independent scheme — no user is authenticated yet, so there is no profile to read.

## The Quickshell UI

Everything shell-side is one Quickshell instance:

- **Bar** — a layer-shell panel with data-driven blocks (workspaces, clock, volume,
  battery, network, updates, notifications/DND, system monitors, tray, …). Its live config
  is `~/.config/quickshell/w/config/bar.json` (user-owned) — that file holds *which blocks
  exist, what they do, and their colors*. Its **shape and translucency belong to the
  theme**, not to that file: height, corner radii, margins, padding, gaps and outlines from
  `W_GEO_BAR_*` in the active theme's `geometry.conf` (`w-style apply geometry`), the
  background plaque and outline from `W_FX_BAR_OPACITY`/`W_FX_BAR_BORDER_OPACITY` in its
  `effects.conf` — dropping both to `0.0` leaves the blocks floating as separate islands
  without thinning menus or popups. See **w-theming**. So "make the bar square / taller /
  transparent" is a theme edit; writing such a key into bar.json anyway pins that element
  out of the theme until the key is deleted.
  The clock block left-click opens a calendar; right-click cycles clock
  faces. The bell block shows and toggles Do Not Disturb (`Super+Shift+D` does the same) —
  see **w-notifications**.
- **Which blocks are shown is PER MONITOR**, and it is the one part of the bar you can
  change directly: read **`w_bar_status`**, change **`w_bar_set`** (Tier 1, user-scope,
  live). Blocks are addressed by `id`, and the same block can be on one output and off
  another — so never say "the bar shows X" without naming the output. `w_bar_set` with no
  `block` switches the whole bar on that output, the primary one included; switching a bar
  off **keeps** its per-block choices, so switching it back on restores them (nothing is
  lost, don't warn). Behind it: the `w-bar` CLI and a `monitors.<output>.{enabled,show}`
  map in the same `bar.json`. GUI: Hub → Appearance → **Bar**. Four ship OFF — the
  cpu/ram/temp/disk group, network, brightness, keyboard backlight — so "no network
  indicator on my bar" is the default, not a fault: switch it on for that output.
  Three different axes, three different answers: "remove the clock" → `w_bar_set`; "move
  the bar down" → `w-appearance bar-position` (same tab in the GUI); "make the bar
  thinner/rounder/transparent" → the theme, above.
- **Ask W palette** (`Super+W`, or the robot button on the bar) — the shell entry point
  to *this* assistant. It is a thin one-line prompt box, not a chat: on Enter it hands the
  question to `w-ai ask` in a terminal, where the session actually runs (streaming, tool
  approvals, the polkit password prompt). An empty prompt just opens a bare session. So the
  real conversation always lives in the terminal; the palette only captures the question.
  Which runtime opens there is whatever the active AI profile selects — goose, or a
  provider CLI like Claude Code with W's tools, skills and memory already attached
  (see the `w-ai` skill). If the active AI config isn't launch-ready (missing
  provider/model/key, or a host CLI that isn't installed or signed in — checked via
  `w-ai ready`), it shows an infobox card ("AI is not configured" + a link to Hub → AI)
  instead of the prompt.
- The shell config tree lives under `~/.config/quickshell/w/`. Theme colors/geometry/effects
  come from `w-style` (live); per-component behavior lives in JSON config files there.
- Those `config/*.json` files are **user-owned**: an update never overwrites them. So a bar
  block W starts shipping after the machine was installed does **not** appear by itself —
  if a user asks why a new indicator is missing, that is the reason. `w-reset quickshell
  .config/quickshell/w/config/bar.json` restores the shipped default (it backs the current
  file up first), or they can add the block by hand.

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

## Session memory (reopen windows at login)

Remembers which programs were open, on which workspace and monitor, where the floating
ones sat and which had focus — and reopens them at the next login. Managed by
`w-session` and the Hub's System panel, section "Session". All keys are user-scope: no
root, no polkit anywhere in this subsystem.

**Wayland does not do this for us.** The protocol that would (`xdg-session-management-v1`,
which Qt 6.10, Mutter and SDL already speak) is **not implemented by Hyprland**, so W
reconstructs the session from the outside: `hyprctl clients` for the layout,
`/proc/<pid>/cmdline` and `/proc/<pid>/cwd` for how to start each program again. Say this
plainly if a user asks why in-app state does not come back — it is a protocol gap, not a
W bug.

Three modes:

- **`off`** (the shipped default) — nothing recorded, every login is clean.
- **`save`** — the snapshot is kept current, but nothing reopens by itself;
  `w-session restore` does it on demand.
- **`restore`** — kept *and* replayed at login.

Two things save a snapshot, and the difference matters when you explain staleness:

1. **A graceful logout/reboot/shutdown is exact.** `w-session-exit` (the Power Menu path)
   saves *before* it starts closing windows, which is the last instant the window list is
   whole.
2. **The background daemon covers the rest.** `w-session-save.service` watches Hyprland's
   event socket and writes at most once per `AUTOSAVE_SEC` (default 60, `0` = graceful
   exit only). That number is how much an unclean shutdown may cost — nothing else.

What it restores well, and what it cannot:

- **Workspaces, monitors, floating geometry, pinned and fullscreen state** — accurate.
  Windows arrive *silently* (`no_initial_focus` + `workspace "N silent"`), so focus never
  jumps while the session fills in.
- **Tiling splits** — restored exactly, including split direction and ratio, on
  **dwindle**. The compositor does not expose its split tree, so W recovers it from the
  saved rectangles (a tiled workspace is a guillotine partition, so the tree follows from
  the leaves) and replays it with `preselect` + `splitratio … exact`. Under **master or
  scrolling** there are no such layout messages: windows are dealt in saved spatial order
  and the arrangement is approximate. Check which layout is in force before promising
  exactness.
- **In-app content** — each program's own persistence does that work (browsers reopen
  tabs, editors reopen files named on the command line). Scrollback and unsaved edits do
  not come back.
- **Two windows of one single-instance program** — they share a pid and often a title,
  so nothing external tells them apart. Restore launches same-class windows one at a
  time precisely to keep them distinct, but a terminal's *contents* can still be matched
  to the wrong window of the pair. Say "best-effort" rather than claiming exactness.
- **Terminals** restore through `w-term` (W's single terminal entry point), not through
  whichever binary they happened to be, so a later terminal switch does not strand the
  saved session.

Placing a window on another workspace means focusing it there first, so the replay walks
the workspaces. It happens **behind a curtain** — a frozen frame of the
desktop with a card reading "Restoring your session" over it, lifted when the last window
has landed. That is the expected look of a login with session memory on, not a fault. If
the shell or the wallpaper is not up yet, the restore waits a moment for them and then
goes ahead regardless — uncovered, or over a darker frame.

### Programs inside a terminal

A terminal window belongs to the terminal; the editor or monitor inside it is a child
process. Without help a workspace of work comes back as a workspace of empty shells, so
`w-session` looks inside — structurally, since a terminal is a process with a child on a
pty — and reopens the program with `w-term -e <program>` **in the directory it was
running in** (the program's own cwd, not the terminal's).

`TERMINAL_APPS` gates it: `allowlist` (default), `all`, or `off`.

Which program a terminal window is running is read from its **title** when the terminal
runs every window in one process (ghostty, W's default) — the title names the program
even when the program renamed the window (`Yazi: ~/src` is still yazi). Two windows
running the *same* program, or a program whose title never names it, come back as an
empty terminal **in the right directory** rather than as a guess. Worth saying when
someone asks why one of their terminals came back bare.

**The allowlist is a safety boundary, not a convenience list.** Reopening a program means
re-executing it, unattended, at login. Editors, pagers, viewers and monitors are safe —
they show you what you were reading and touch nothing. A build, a migration, a deploy
script or anything behind `sudo` is not, and neither is anything W has never heard of.
Programs off the list still get their terminal back in the right directory, which is
inert. `/usr/share/w/defaults/session-terminal.list` ships the vendor set; personal
additions go in `~/.config/w/session-terminal.list`. Before setting `all` for someone,
tell them what it means.

`tmux` and `screen` are deliberately absent: they restore their own sessions better than
this could, and reattaching from here would fight them.

### Other settings

In `w-conf cat session`: `EXCLUDE_CLASSES` (space-separated anchored regexes of window
classes never to record — installers, one-shot wizards, a game) and `MAX_WINDOWS` (cap;
over it, the least recently focused windows are dropped). Personal relaunch overrides
live in `~/.config/w/session-apps.tsv` (`<class regex>\t<command>`, `-` meaning never
relaunch).

```sh
w-session status                  # mode, autosave floor, what is stored
w-session mode restore            # reopen at every login (takes effect NEXT login)
w-session restore --dry-run       # list what would be reopened, launch nothing
w-session exclude add 'steam_app_.*'
systemctl --user status w-session-save.service
```

**The trap to warn about:** turning `restore` on does **not** reopen anything now, and
`restore` with an empty snapshot reopens nothing at the next login either. Check the
window count in `w_session_status` before telling the user it is working.

## Named layouts

Beside the one automatic snapshot there are **named layouts** in
`~/.local/share/w/layouts/`: arrangements the user saved on purpose. Same recording,
kept under a name. Two consequences that are easy to get wrong — `w-session forget`
does **not** delete them (it clears only the automatic snapshot), and saving one is
**not** gated on `MODE`.

Scope decides how much applying one destroys: `layout` holds every workspace and closes
every window on all of them; `workspace` holds the focused one **without its number**,
closes only that workspace's windows, and opens onto whichever workspace is focused
then — not the one it was saved from.

```sh
w-session layout list                   # slug, scope, window count, when, name
w-session layout save 'Работа'          # every workspace ( --workspace = this one )
w-session layout apply работа --dry-run # how many windows this would close
w-session layout delete работа
```

**Applying is destructive; say so first.** Every window is asked to close the way its X
button does, so unsaved work raises its own "Save changes?" dialog and cancelling any
one of them abandons the whole apply, nothing touched. That is not the same as safe:
browser tabs, a shell with a job running and terminals get no dialog at all (W turns
ghostty's close confirmation off deliberately). `--dry-run` answers "how much" without
changing anything — lead with it.

The apply **detaches** and returns at once, because it closes the terminal it was
started from: its output cannot tell you it worked. Report it as started and read
`w_hypr_context` for what came back; a refusal arrives as a desktop notification.

The panel is `Super+O`, also on the Hub's Layouts tile.

## Screenshots

`w-screenshot` is the capture tool (region/window/output/full × annotate/copy/save).
By default `Super+Shift+I` takes a region screenshot and opens the annotator
(`Super+I` the whole output, `Super+Ctrl+I` the focused window); saved images go to
`~/Pictures/Screenshots`.

## Desktop tools (via `w-mcp`)

When `w-mcp` is connected you can perceive and act inside the running session. These
are **user-scope** (no privilege — the same power the user's own shell has), so no
polkit prompt is involved; the host's tool-approval covers them.

- **`w_desktop_context`** *(read)* — the live context: focused window (app, title,
  workspace), active workspace, and monitors. Call it to ground desktop help in what
  the user is actually doing, instead of assuming. It returns a note (not an error)
  if there is no reachable Hyprland session.
- **`w_monitor_status`** *(read)* — full monitor layout: every output's live mode/
  scale/rotation/position, enabled/focused/primary, its saved `w-monitor` rule, and
  a handful of its available modes. Use it for "what monitors do I have" / "what's
  my resolution/scale" and before running any `w-monitor` command — see **Displays**
  above for the ask-before-guessing rule on output names.
- **`w_bar_status`** *(read)* — which outputs carry a status bar and every block's
  on/off state there. **`w_bar_set`** — show/hide one block, or the whole bar, on ONE
  output (no "all monitors" form: this setting is per-monitor by design). See **The
  Quickshell UI** above for what is composition and what is theme.
- **`w_nightlight_status`** *(read)* — the night light: mode, night temperature, the
  window, and whether the screen is being tinted **right now**. Correct even with no
  session reachable from here (it is derived from the config, not asked of the daemon).
- **`w_nightlight_set`** — change it: any combination of `mode`, `temperature`,
  `start`+`end` (both together). Applies immediately and returns the resulting status.
  If the user asks for `schedule` outside the night window, tell them the screen will
  not change until it opens — otherwise "done" reads as "and nothing happened".
- **`w_session_status`** *(read)* — session memory: the mode (`off`/`save`/`restore`),
  the background-snapshot floor, and **how many windows the snapshot actually holds**.
  Check the count before confirming that reopening works — `restore` over an empty
  snapshot reopens nothing, and the mode alone does not reveal that.
- **`w_session_set`** — change it. `terminal_apps: all` re-executes the last foreground command of
  every terminal window at login — a real consequence, not a completeness upgrade; say
  so before setting it.
  `forget` throws the saved layout away and makes the next login clean — ask first
  unless that is exactly what was requested. `save_now` does nothing while the mode is
  `off`. Turning `restore` on takes effect at the **next** login, so say that instead of
  leaving the user waiting for windows to appear.
- **`w_layouts_list`** *(read)* — the named layouts, newest first; its slug is what
  `w_layout_apply` takes. Separate from `w_session_status`'s automatic snapshot, and
  they survive `forget`.
- **`w_layout_save`** — record the current windows under a name; `workspace_only` saves
  just the focused workspace, number-free. Additive and destroys nothing, but reusing a
  name REPLACES that layout — check `w_layouts_list` when the user did not say to
  overwrite.
- **`w_layout_apply`** — **the most destructive tool in this domain: it closes the
  user's windows.** `dry_run` defaults to true; lead with its number and get agreement
  before `dry_run=false`. Its description carries the rest (what the save dialogs do and
  do not cover, why its output never means "finished") — read it before calling.
- **`w_notify`** — surface a notification on the desktop; it does not replace your chat
  reply. Pick `urgency` by what the user must DO, not by how the result pleased you —
  every needless `critical` teaches them to ignore the next one; the tool's description
  has the per-level rule. Managing the notification system itself (DND, history, per-app
  mute) is the **w-notifications** skill.
- **`w_screenshot`** — capture to `~/Pictures/Screenshots` and get the file path.
  Interactive region select (`Super+Ctrl+S`) is deliberately not exposed here.
  **Capturing is not analyzing:** take the shot, report the path, and do not read the
  image back unless asked to look at it.
- **`w_launch_app`** — open an application into the session via `uwsm app` (e.g.
  `firefox`, `ghostty`). Program name + simple args only, no shell syntax. Prefer
  this over a raw privileged command for launching apps.
- **`w_hypr_windows`** *(read)* — list every open window: address, class, title,
  workspace, monitor, floating/tiled, and which one is focused, via `hyprctl
  clients`. Call this first whenever the request touches a window that might not
  be the focused one — it is how you find the `address` to hand to
  `w_hypr_dispatch`'s `target`.
- **`w_hypr_dispatch`** — control windows and workspaces (the same power the user's
  keybindings have). Pick an `action` from a curated allowlist, some with an `arg`,
  and most accept an optional `target` to aim at a specific window instead of the
  focused one. The exact allowlist is in the tool's own description — read it there
  rather than from a second copy that can go stale.

  **Multi-window requests need one call per window** — there is no bulk/swap
  action. Workflow: call `w_hypr_windows`, match each window the user mentioned to
  an entry by class/title, then call `w_hypr_dispatch` once per window with
  `target="address:0x..."` (the exact, unambiguous form — `class:...`/`title:...`
  also work but match as a regex, so prefer address once you have it). For
  example "move the browser to workspace 3 and the terminal to workspace 4" is two
  `move-to-workspace` calls, each with a different `target` and `arg`; "swap the
  windows on workspace 1 and 2" is also two `move-to-workspace` calls — one per
  window, each targeting the *other* workspace. The `organize_windows` MCP
  Prompt spells out this recipe for hosts that support prompts.

  **If more than one window could plausibly match** (e.g. two Firefox windows), or
  the request is ambiguous in any other way (unclear which workspace, which
  window, what "swap" should mean here) — **ask the user to clarify instead of
  guessing.** Only these dispatchers are allowed and every argument (including
  `target`) is validated/escaped — it **cannot** run arbitrary commands or Lua, so
  use `w_launch_app` to open apps. Prefer it over telling the user to run
  `hyprctl` by hand. For anything outside the allowlist (window rules, resize
  submap, layout tweaks), describe the Lua config / keybinding instead (see the
  `hyprland` skill for exact dispatch syntax, including the full window-selector
  reference in `Configuring/Basics/Dispatchers.md` if you need a selector form
  beyond `address:`/`class:`/`title:`).
