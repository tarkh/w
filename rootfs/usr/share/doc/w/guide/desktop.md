---
title: The desktop
section: guide
order: 4
summary: Windows, workspaces, popups, notifications, screenshots and session restore.
sources:
  - path: .claude/library/package-hyprland.md
    sha256: 39aff302ce90ea1ea2ed24607f8476586bed1980cb1f5533b9c9b7897df3db62
  - path: .claude/library/quickshell.md
    sha256: 1ddc54593c92571de2d2b8658b376e7ecb2dc44b2292ca77da3ec07a3717bbe2
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

## Screenshots

<kbd>Super+PrintScreen</kbd> opens the region picker; the result lands in the
notifications with a one-click copy. `w-screenshot` carries the full set of
modes (window, monitor, delayed) for scripts and the CLI.
