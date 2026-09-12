---
name: w-desktop
description: >-
  The W Linux desktop: the Hyprland (Wayland) compositor with a Lua config, the
  uwsm-managed systemd session, the single Quickshell UI (bar, launcher, notifications,
  OSD, lock, greeter), key bindings, and screenshots. Load this for anything about
  the desktop, window management, keybindings, the bar/launcher, or the shell UI.
  Monitors and the night light are w-displays; reopening windows at login is w-session.
sources:
  - path: .claude/library/package-hyprland.md
    sha256: 39aff302ce90ea1ea2ed24607f8476586bed1980cb1f5533b9c9b7897df3db62
  - path: .claude/library/quickshell.md
    sha256: 1ddc54593c92571de2d2b8658b376e7ecb2dc44b2292ca77da3ec07a3717bbe2
  - path: .claude/library/quickshell-bar.md
    sha256: 535ef9874fedc06b73a9f2224283306e498bbdcde4d892a292f5b7b4c9263e6c
  - path: .claude/library/w-bar.md
    sha256: 32f85bd9637a23ce14e911d48ab0586ac0c569cc27f750bcdca25e3fdf5c75f6
  - path: .claude/library/quickshell-assistant.md
    sha256: 4d3098dde3047c6d5b7057911ca6393be05627792968b4f46a3542b69f18bb33
  - path: .claude/library/quickshell-keyboard.md
    sha256: dc74f0589ce0eb8f24ebddd8f3c8bbb5aa1cd2b21ce63e2b5f6d3a472aa1b0c8
tools:
  - w_desktop_context
  - w_notify
  - w_screenshot
  - w_launch_app
  - w_hypr_windows
  - w_hypr_dispatch
  - w_bar_status
  - w_bar_set
---

# W Desktop

The desktop is **Hyprland** (a Wayland compositor) driving a single **Quickshell** UI.
There is no widget zoo: the bar, launcher, notifications, on-screen display, lock screen,
and login greeter are all one `quickshell -c w` instance.

Three neighbours, split off so a question about one does not drag in the others:
**w-displays** (monitors, resolution and scale, the night light), **w-session**
(reopening windows at login, named layouts), **w-input** (keyboard layouts and the
`w-hotkeys` catalog behind the bindings below).

## Session

The user session is **systemd-managed via uwsm**: the compositor is the user service
`wayland-wm@hyprland.service`, with a proper `graphical-session.target` and logs in
journald. Diagnose it with `systemctl --user status wayland-wm@hyprland.service` and
`journalctl --user -b` (see the `w-diagnostics` skill).

This is the *systemd* session. Remembering which **windows** were open and reopening
them at the next login is a different subsystem — the **w-session** skill.

## Hyprland configuration (Lua)

Since Hyprland 0.55 the compositor config is **Lua**, not the old hyprlang `.conf`:

- Main config: `~/.config/hypr/hyprland.lua`.
- Options are set with `hl.config({ category = { key = val } })`, binds with
  `hl.bind(...)`, rules with `hl.window_rule{...}` / `hl.layer_rule{...}`, autostart with
  `hl.on("hyprland.start", ...)`.
- **Per-app window rules are drop-in files, not lines in `hyprland.lua`.** W's own
  (satty, a bundle's app such as Bitwarden) live in `/usr/share/w/hypr/rules.d/<app>.lua`;
  the user's go in `~/.config/hypr/rules.d/<app>.lua` — a self-applying file that just
  calls `hl.window_rule({ match = { class = "^(foo)$" }, float = true, ... })`, then
  `hyprctl reload`. Loaded after W's, and the last value of a property wins, so re-declaring
  a rule for the same class overrides W's property by property (`tile = true` cancels a
  W float). A broken file shows in `hyprctl configerrors` and does not affect the rest.
  Find an app's class with `hyprctl clients -j` (it often differs from the binary name).
  For a dialog-sized float use `size = { "min(800, monitor_w * 0.9)", "min(790, monitor_h * 0.9)" }`
  — Hyprland does not clamp a too-large floating window to the monitor.
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
  the fix — the **w-displays** skill has the night light itself).

> For precise, up-to-date Hyprland config syntax (options, binds, rules, animations,
> layouts, hyprctl/IPC), consult the **`hyprland` skill** — a navigator over a local copy
> of the official Hyprland wiki. Do not rely on memorized syntax; the Lua API changes
> quickly.

## Key bindings (`$mod` = Super)

These are the **default** chords; bindings are data-driven and user-remappable, so a
given machine may differ. For *configuring* input — remapping keys and profiles
(`w-hotkeys`), keyboard layouts (`w-keyboard`), the system locale (`w-locale`) and
the language profile behind it (`w-langpack` — why part of the UI can stay English
after a language switch) — see the **`w-input`** skill; the table below is just a
quick reference.

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
| `Super+Shift+N` | Night light on/off (off ↔ scheduled) — **w-displays** |
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

- **Bar** — a layer-shell panel with data-driven blocks (workspaces — the scratchpad
  shows there as a glyph button, click toggles it — clock, volume, battery, network, updates, notifications/DND, system monitors, tray, …). Its live config
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
  workspace), active workspace, and monitors (their full layout, modes and saved rules
  are `w_monitor_status`, in the **w-displays** skill). Call it to ground desktop help in what
  the user is actually doing, instead of assuming. It returns a note (not an error)
  if there is no reachable Hyprland session.
- **`w_bar_status`** *(read)* — which outputs carry a status bar and every block's
  on/off state there. **`w_bar_set`** — show/hide one block, or the whole bar, on ONE
  output (no "all monitors" form: this setting is per-monitor by design). See **The
  Quickshell UI** above for what is composition and what is theme.
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
