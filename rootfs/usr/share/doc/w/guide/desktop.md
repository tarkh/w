---
title: The desktop
section: guide
order: 4
summary: Windows, workspaces, popups, notifications, screenshots and session restore.
sources:
  - path: .claude/library/package-hyprland.md
    sha256: ab8c62f0ff8e9573e02a1e88ca5e65dc364decfcc6d645dcd9280c8b3795eb9c
  - path: .claude/library/quickshell.md
    sha256: da1b14d9d934188dd9b49ece41af8b58ab8d5abe06c6172e198e1c5ade171759
  - path: .claude/library/w-screenshot.md
    sha256: 24a2008239b8083d729aa3a1e26f220d1d5a1d448f8f5825c5275ee38b7f88eb
---

W desktop = the Hyprland compositor with the Quickshell UI on top. Both are
configured by W's theme; the tools you touch day to day are the ones below.

## Windows and workspaces

Hyprland is a tiling compositor: windows tile automatically, and dragging a
window's titlebar into another turns them into a resizable split. The basics:

- Move focus with <kbd>Super+Arrow</kbd>, move windows with
  <kbd>Super+Shift+Arrow</kbd>, switch or move windows between the first ten
  workspaces with <kbd>Super+(Shift+)1..0</kbd>.
- **Window groups**: <kbd>Super+G</kbd> groups two windows into a tabbed group
  (W styles the group's tab bar); <kbd>Super+Tab</kbd> cycles inside one.
- <kbd>Super+F</kbd> / <kbd>Super+Shift+F</kbd> fullscreen (real and
  fake-fullscreen), <kbd>Super+M</kbd> maximize, <kbd>Super+Shift+Space</kbd>
  float/untile, <kbd>Super+Shift+C</kbd> center a floating window,
  <kbd>Super+P</kbd> pin it above everything.
- <kbd>Super+R</kbd> resize mode, <kbd>Super+S</kbd> the scratchpad (a parked
  window you summon back on the current workspace).
- **Per-app window rules** (always float this app, open it centred at a fixed
  size…) are drop-in files: W's own live in `/usr/share/w/hypr/rules.d/`, yours go
  in `~/.config/hypr/rules.d/<app>.lua` and win over W's for the same app —
  a file that calls `hl.window_rule({ match = { class = "^(app)$" }, float = true })`,
  then `hyprctl reload`.
- The full, rebindable list lives in **Hub → Hotkeys**.

## The shell surfaces

- **The bar** at the top: workspaces, active window, tray, clock, and status
  blocks (updates, network, audio). Which blocks it shows — and on which
  monitor — is set in **Hub → Appearance → Bar**.
- **The launcher** (<kbd>Super+D</kbd>) starts apps and carries W actions
  (lock, screenshot, calendar).
- **The Hub** (<kbd>Super+Space</kbd>) is the control center — see the other
  guides.
- **Clipboard history** (<kbd>Super+V</kbd>) searches what you copied; entries
  persist across reboots.
- **Notifications** appear in the top-right; **Hub → Notifications** (and the
  `w-notify` command) manage do-not-disturb and per-app muting.
- **Volume and brightness** popups open from their keys; they show levels
  live like any desktop's OSD.

## Sessions that come back

When W's session memory is on (default for new installs), logging out — or
locking for longer than the configured interval — parks your windows and
brings back the same layout at the next login, including files open in the
terminal. **Hub → System → Session** chooses: always restore, always start
fresh, or off. **Super+O** saves or applies a named, reusable layout.

Do-not-reopen apps (e.g. a password manager you want empty after every login)
are excluded in the session settings; see `w-session` for the details.

Window groups (tabbed windows) come back as groups, tabs in order. What is
*inside* a window is each program's own memory: browser tabs return only if
the browser restores them itself — in Firefox, **Settings → Home and startup → "Open
previous windows and tabs"**; W does not switch that on for you.

## Screenshots

Three keys, all of which land you in the same place — a frozen copy of the
screen you can draw on straight away, with the toolbar next to your selection.
Nothing else opens: copy, save or pin the result from that toolbar and it is
gone again.

| Key | Captures |
| --- | --- |
| <kbd>Super+I</kbd> | the monitor you are on, already selected |
| <kbd>Super+Shift+I</kbd> | nothing yet — drag the area you want |
| <kbd>Super+Ctrl+I</kbd> | the focused window, already selected |

The editor's Save button asks where and under what name, opening on the
`Screenshots` folder inside your pictures folder. Two more keys skip the editor
entirely and write the file straight there, no questions asked:

| Key | Saves |
| --- | --- |
| <kbd>Super+Alt+I</kbd> | the focused monitor |
| <kbd>Super+Ctrl+Alt+I</kbd> | the focused window |

Files are named `W-<date>_<time>.png`. The annotation colours and font follow
your theme, and every key here is rebindable in **Hub → Hotkeys** — including
unbinding the two you do not want.

The editor is Flameshot. W also ships the older one, Satty, for the case where
Flameshot misbehaves on your hardware — `w-conf set --user screenshot ANNOTATOR
satty` switches over for the next capture, and `w-conf unset --user screenshot
ANNOTATOR` switches back. Whichever is
set, `w-screenshot` carries the full set of modes for scripts and the CLI,
including the ones with no editor at all (`--copy`, `--save`).
