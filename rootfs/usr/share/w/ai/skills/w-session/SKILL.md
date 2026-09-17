---
name: w-session
description: >-
  Session memory and named layouts on W: reopening the windows that were open at the
  next login (`w-session`, modes off/save/restore, programs inside terminals), and the
  arrangements a user saves on purpose and applies later (`Super+O`). Load this for
  "bring my windows back", "why did my session not restore", or saving/applying a
  named layout — not for the systemd/uwsm session itself, which is w-desktop.
sources:
  - path: .claude/library/w-session.md
    sha256: 63975e239ed7ccb8df0f22733888eb062da19c326dc258bfb34cc3cfe70bff59
  - path: .claude/library/quickshell-layouts.md
    sha256: 61e8015efd56cad555527ac27253d8261731379c703b7e25f9b8799fab142149
tools:
  - w_session_status
  - w_session_set
  - w_layouts_list
  - w_layout_save
  - w_layout_apply
---

# W Session Memory & Layouts

One subsystem (`w-session`) with two faces: **one automatic snapshot** taken behind
the user's back and replayed at login, and **named layouts** saved deliberately and
applied on demand. They share the recording machinery and nothing else — `forget`
clears the snapshot and leaves the layouts standing, and a layout can be saved while
the automatic memory is switched off.

**"Session" means two different things in W.** This skill is the *window* session.
The systemd/uwsm session (`wayland-wm@hyprland.service`, `graphical-session.target`,
logging out) is the **w-desktop** skill; diagnosing its units is **w-diagnostics**.

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
- **Window groups (tabbed windows)** — restored as groups, tabs in the saved order, the
  tab that was on top on top; the group takes its old tile of the split tree. Only on
  dwindle; the group's lock state is not restored, and a *floating* group comes back as
  separate floating windows.
- **Two windows of one single-instance program** — they share a pid and often a title,
  so nothing external tells them apart. Restore launches same-class windows one at a
  time precisely to keep them distinct, but a terminal's *contents* can still be matched
  to the wrong window of the pair. Say "best-effort" rather than claiming exactness.
- **Programs that keep their own session (Firefox)** are the exception to "one launch
  per window": flagged `own-session` in `session-apps.tsv`, they are launched ONCE and
  every window they bring back is put where a window with the same title was. Whether
  the tabs come back at all is the browser's own setting — Firefox: Settings → Home and startup →
  "Open previous windows and tabs" — and W does not switch it on. Without it, Firefox
  reopens one blank window and the other saved slots are simply dropped. At logout W closes
  Firefox's windows one by one and then finishes Firefox's own "closed in series" memory
  in its session file (Firefox's pass stops at any older closed pop-up), so every window
  comes back; a window opened seconds before logout may still be lost — that is Firefox's
  save interval, not W.
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
live in `~/.config/w/session-apps.tsv` (`<class regex>\t<command>[\t<flag>…]`, `-` meaning
never relaunch, `=` meaning keep the recorded command line; flag `own-session` — see above).

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
`w_desktop_context` (the **w-desktop** skill) for what came back; a refusal arrives
as a desktop notification.

The panel is `Super+O`, also on the Hub's Layouts tile.

## Session tools (via `w-mcp`)

When `w-mcp` is connected you can perceive and act inside the running session. These
are **user-scope** (no privilege — the same power the user's own shell has), so no
polkit prompt is involved; the host's tool-approval covers them.

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
  before `dry_run=false`. What the save dialogs do and do not cover, and why its output
  never means "finished", is in **Named layouts** above — read it before calling.
