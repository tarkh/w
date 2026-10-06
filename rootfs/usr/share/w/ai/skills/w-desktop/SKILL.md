---
name: w-desktop
description: >-
  The W Linux desktop: the Hyprland (Wayland) compositor with a Lua config, the
  uwsm-managed systemd session, the single Quickshell UI (bar, launcher, notifications,
  OSD, lock, greeter), key bindings, and screen capture (screenshots + recording).
  Load this for anything about the desktop, window management, keybindings, screen
  recording or screencasts, the bar/launcher, the shell UI, or an app's Open/Save
  dialog that opens too small, huge or tiled.
  Monitors and the night light are w-displays; reopening windows at login is w-session.
sources:
  - path: .claude/library/package-hyprland.md
    sha256: 85f6ab9f832fcc8a6f98530bcab0370dd2a4d226371915b22864c8526292d176
  - path: .claude/library/package-files.md
    sha256: 85da1d2fccfd07be804443763a7fdde37727878e1b6c85d3288413f72c23b504
  - path: .claude/library/quickshell.md
    sha256: da1b14d9d934188dd9b49ece41af8b58ab8d5abe06c6172e198e1c5ade171759
  - path: .claude/library/quickshell-bar.md
    sha256: a3f19c6d40c72a88088a144b1d2a179f809e1a8bc8027c52536053bf8d8b406e
  - path: .claude/library/w-bar.md
    sha256: 763c1acafab94122e8a18c1c3f0b149eef2e54978f352f7ec4162b8241bdd787
  - path: .claude/library/quickshell-assistant.md
    sha256: b296b0e3249a090498c07b6ccdcc39eb754df404119b9dd026a9584fd7abe185
  - path: .claude/library/quickshell-keyboard.md
    sha256: 0f132daff3b5514e1f520397d9489286c4fec4a03b654d94b6c7f564f0b1f0bc
  - path: .claude/library/w-screenshot.md
    sha256: cab923bc52e33ecc3604a6f4786103d095312a01a25b1b2a5ee893a41c67c3ae
  - path: .claude/library/w-record.md
    sha256: c7ff443860ecebfc73ec01be9a90b845d1a1110e79f9bdabfde1c5dcd7b0f625
tools:
  - w_desktop_context
  - w_notify
  - w_screenshot
  - w_record
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

A Hyprland `SIGSEGV` coredump **at exit** with more than one monitor — the greeter's on
every login, the user's on some logouts; stack `exit` → `~CDRMBackend` →
`flushAsyncCommitEvents` — is a known upstream aquamarine bug (hyprwm/aquamarine#383).
It fires after Hyprland has finished, loses nothing, and is not a W fault; don't disable
coredumps over it. A crash *during* a session is a different matter — investigate it.

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
  — Hyprland does not clamp a too-large floating window to the monitor. `max_size` and
  `min_size` take the same expressions (the wiki says only `move`/`size` do, but they do):
  a rule with `max_size` and no `size` lets the app keep the size it asked for and only
  caps it — satty's rule caps at 90% of the monitor, and w-screenshot asks satty for the
  exact size (`--resize`) itself.
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

### Open / Save dialogs of an app (too small, huge, or tiled)

W's standard for every "pick a file" window is **1000x640 logical px, floating, centred**.
W's own apps and bundles already comply; an app the user (or you) installed later may
not. Diagnose before writing anything: have the user open the dialog, then
`w_hypr_windows` (or `hyprctl clients -j`) → its `class`, `initialTitle`, `floating`,
`size`. Then match it to one case:

1. **class `xdg-desktop-portal-gtk`, or the app's own class with a GTK3 dialog**
   (GIMP-like) — GTK owns the size, shared by all GTK apps and kept across reboots.
   Floating but huge/odd in every app → a stale saved size: `gsettings reset
   org.gtk.Settings.FileChooser window-size`, reopen. Never put `size` on these — it
   would override the size the user drags. Nothing else to do.
2. **Dialog is tiled** (`floating: false`; the app opened it without a parent window) →
   a user rule with `float = true, center = true` matching that dialog, no `size` (if
   it is a GTK dialog, also reset the saved size above — a tiled open saves its tile).
3. **Nothing remembers its size** — Qt apps (`QFileDialog`; W's qt6ct has no portal
   dialog), GTK4 apps on the old in-process chooser, apps drawing their own browser
   window (Blender) — it opens tiny every time → a user rule that gives the W size.

Rules for cases 2–3 go in `~/.config/hypr/rules.d/<app>.lua`, then `hyprctl reload`,
then reopen the dialog and confirm with `w_hypr_windows`. The class is the APP's, so
also match the dialog by `initial_title` — otherwise the main window is resized too.
Titles are translated: list every UI language the user runs (e.g. Russian and English):

```lua
hl.window_rule({
  match    = { class = "^(org\.example\.App)$",
               initial_title = "^(Open|Save As|Открыть|Сохранить как)( — App)?$" },
  float = true, size = { 1000, 640 }, min_size = { 600, 420 }, center = true,
})
```

- Qt appends ` — <App name>` to every window title — include it in the pattern.
- Do **not** match `modal = true`: Qt also marks message boxes modal, and `size` would
  blow every "Are you sure?" up to 1000x640.
- Cases 2–3 do not remember a manual resize (each open is 1000x640); case 1 does.

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
| `Super+Alt+I` / `Super+Ctrl+Alt+I` | Screenshot output / window, saved straight to a file |
| `Super+Ctrl+R` / `Super+Alt+R` / `Super+Ctrl+Alt+R` | Record output / region / window — each a start/stop toggle |
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
`Super+Shift+I` takes a region screenshot, `Super+I` the whole output, `Super+Ctrl+I`
the focused window; all three open the annotator, whose Save button asks where.
Adding `Alt` skips the annotator and writes the PNG immediately, no dialog:
`Super+Alt+I` (output) and `Super+Ctrl+Alt+I` (window) — tokens
`screenshot_screen_save` / `screenshot_window_save`, rebindable and unbindable like
any other (skill **w-desktop** → hotkeys, `w-hotkeys set <token> ""`). The "Saved"
notification previews the shot; clicking it opens the file in the default viewer (a
finished recording's notification likewise opens the video). Saved images go
to `Screenshots/` inside the user's Pictures folder — `$(xdg-user-dir
PICTURES)/Screenshots`, never a literal `~/Pictures`: the folder is named in the
system language (`~/Изображения` on a Russian system) and follows a language change
(`w-userdirs`, skill **w-input**).

The annotator is **Flameshot**: one frozen full-monitor overlay where the region is
both selected and drawn on, with the toolbar beside the selection — no second window.
On Wayland it captures through the XDG screenshot portal (here
`xdg-desktop-portal-hyprland`, which shells out to `grim`), so it rides the same
wlr-screencopy path as the rest of W. Its overlay palette/font are the w-style
`flameshot` axis; its window rules are `/usr/share/w/hypr/rules.d/flameshot.lua`.

**Satty**, the previous annotator, is still installed as the rollback:
`screenshot ANNOTATOR` (`flameshot` | `satty`) decides, is read at the moment of each
capture, and needs no reload or relogin. Set it with `w-screenshot set ANNOTATOR satty`
(back: `… flameshot`) or in Hub → Displays → Screen capture → Editor; the key is
**user-scope**, so a plain `w-conf set` (which targets /etc/w) is the wrong tool. If a user reports the overlay misbehaving (wrong monitor,
decorated window, slow to appear), that key is the first thing to try. Satty opens the
capture at its on-screen size (up to 90% of the monitor; larger ones are fitted), and a
`region` capture opens right over the selected spot, toolbars around it.

**Window shot outline.** A `window` capture taken with `--copy`/`--save` or opened in
Satty gets transparent rounded corners (radius = live window rounding + border) and,
with `screenshot WINDOW_SHADOW=yes` (default; `w-screenshot set WINDOW_SHADOW no`, or
Hub → Screen capture → Add window shadow), a soft macOS-style drop shadow on a
transparent margin. **Flameshot never gets it** — it takes and saves its own frame, so
for a dressed window shot use `window --save`/`--copy` or switch to Satty. A translucent
window still shows what is behind it: the capture is the composited monitor.

Two details that look like bugs and are not. **The bar drops below the windows**
while a region or window capture is open — no window can draw above a `top` layer,
so otherwise the bar would cover the selection and eat clicks in its strip;
w-screenshot asks for it via the `quickshell:barlower` global shortcut and the bar
restores itself when the overlay closes. A whole-monitor capture skips this (its
selection never reaches past the bar, and moving the layer there is a visible
flicker). **The shortcut cheat-sheet does not appear for a window capture** —
Flameshot centres it on the monitor with no say in the matter, where it would land
on the toolbar beside the preselected window, so `showHelp` is turned off for that
mode only.

On the first-ever capture w-screenshot writes the XDG screenshot permission
(`PermissionStore` table `screenshot`, host row) to `yes`, so the one-time GTK
"allow screenshots?" dialog never interrupts. It only ever writes an ABSENT row —
a user who revoked the permission on purpose keeps that, and their captures will
fail until they allow it again. One exception the key does not cover: `full --annotate` — a canvas
across ALL monitors — always uses satty, because a Flameshot overlay is one window on
one monitor by construction. `--copy` and `--save` never open either tool.

## Screen recording

`w-record` is the video half of the same subsystem, and a separate CLI because a
recording is a *state* the machine is in: `w-record <region|window|output>` (default
action `--toggle`), plus `w-record stop` and `w-record status [--porcelain]`. The
binds are on **R**: `Super+Ctrl+R` (output), `Super+Alt+R` (region),
`Super+Ctrl+Alt+R` (window) — tokens `record_screen` / `record_region` /
`record_window`. Each is a toggle: the chord that started the take ends it; the
launcher entry **Screen Recording** (`w-record region`) toggles the same way. They do
not mirror the I-family ladder because `Super+R` is `resize_mode` and
`Super+Shift+R` is `reload`. Files go to `Screencasts/` inside `$(xdg-user-dir
VIDEOS)`, named `W-<date>_<time>.<FORMAT>`.

The backend is **wf-recorder** — the video twin of `grim`, on the same
wlr-screencopy path, so no portal, no PipeWire session, no privileged helper.
`gpu-screen-recorder` is deliberately NOT installed (its `gsr-kms-server` carries a
`cap_sys_admin` file capability); `RECORDER=gsr` is reserved for a future pack and
errors cleanly today. `wl-screenrec` is AUR-only.

Settings are the `record` w-conf subsystem, all **user-scope**, read when a recording
STARTS — a running one keeps what it started with. Change them with `w-record set KEY
VALUE` (it validates, and refuses `ENCODER=vaapi` + `FORMAT=webm` in either order);
`w-record get` prints them all plus `BACKENDS`. The GUI is **Hub → Displays → Screen
capture**, which a right-click on the bar's recording dot opens directly:

| Key | Default | Notes |
| --- | --- | --- |
| `AUDIO` | `system` | the default sink's monitor — everything audible. `mic` swaps in the microphone, `none` is silent. One track, one source: system + mic together is not offered. |
| `ENCODER` | `auto` | GPU (VAAPI) when a render node exists, falling back to the CPU with a notification if the driver cannot actually encode. `vaapi` set explicitly is not second-guessed; `cpu` is the escape hatch. |
| `FORMAT` | `mp4` | `mp4`/`mkv` are h264; `webm` is VP9 + Opus and always encodes on the CPU (`ENCODER=vaapi` with `webm` is refused). |
| `FRAMERATE` | `30` | constant, not VFR — editors and browsers handle VFR mp4 unevenly. 1–240; the Hub offers 15/24/30/60/120. |
| `WINDOW_MASK` | `no` | `yes` paints the rounded corners of a `window` recording black (a video has no alpha) instead of the wallpaper. Only matters when the theme rounds windows (`W_GEO_WINDOW_ROUNDING` > 0). Needs a CPU filter, so `window` then always encodes on the CPU, even past `ENCODER=vaapi`. |
| `RECORDER` | `wf` | see above. |

If a user asks why their recording has no sound, `AUDIO` is the key; if they ask why
the room is audible instead of the desktop, they are on `mic`.

Four things that look like bugs and are not. **There is no all-monitors mode** —
wlr-screencopy works one output at a time, the same reason `full --annotate` has no
Flameshot form. **Recording a window records the rectangle it occupied at the start**
and does not follow it: wlr-screencopy captures a screen region, not a window
surface, so tell the user to record the monitor if the layout will change. **The
cursor is always in the recording** — wf-recorder hardcodes it, there is no flag.
And **the file is unplayable until the recording is stopped properly**: only
`w-record stop` (or the keybind) lets ffmpeg write the container trailer, so
`kill -9` on the backend truncates the take. `stop` waits up to 10s and never
escalates to `SIGKILL` for exactly that reason.

State lives in `$XDG_RUNTIME_DIR/w/record.state` (`PID`, `MODE`, `FILE`, `STARTED`,
`AUDIO`, `ENCODER`) with `record.log` beside it — that log is where the backend
explains a failed start. Liveness is PID **and** `/proc/<pid>/comm`, so a state file
left behind by a killed session reads as "not recording" rather than stopping
whatever inherited the PID.

While a take runs, the bar shows a **recording block** — a pulsing red dot and the
elapsed time — just left of the Do Not Disturb button; left-clicking it stops the
recording, right-clicking opens the capture settings. It exists only while something records, so "no dot" means nothing is
recording. On an install older than the block it is missing from the user's
`bar.json` (see the bar section above for `w-reset`).

A recording that looks washed out, as if under a pale haze, is the colour-range bug
W already fixes on the CPU path (explicit limited-range BT.709 conversion + matching
tags); if a user reports it, check they are on the current `w-record`.

`w-record` and `w-screenshot` share `/usr/lib/w/w-capture-lib.sh` (save folders,
window/output geometry, the `slurp` selection). The selection is drawn like
Flameshot's: a 1 px frame in the live theme's accent, nothing over the selected
area, and plain black at 65 % around it for BOTH tools, because
Flameshot's overlay cannot be tinted (its dim colour is hardcoded, only the depth is
configurable) — so the dim can not be made to follow the theme, by design.

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
- **`w_screenshot`** — capture to `<Pictures>/Screenshots` (`xdg-user-dir PICTURES`) and get the file path.
  Interactive region select (`Super+Ctrl+S`) is deliberately not exposed here.
  **Capturing is not analyzing:** take the shot, report the path, and do not read the
  image back unless asked to look at it.
- **`w_record`** — `status` / `start` / `stop` for a screen RECORDING (output or
  window; interactive region select is not exposed, it would block on a selection
  nobody is there to drag). A recording runs until stopped and takes the desktop's
  audio with it, so never start one unasked and say plainly when one is running.
  `start` uses `--start`, not the toggle, so "begin" can never silently end a take
  the user is in the middle of. `status` and `stop` are always safe — `stop` on an
  idle session is a no-op, and it is the answer when someone says they are recording
  by accident.
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
