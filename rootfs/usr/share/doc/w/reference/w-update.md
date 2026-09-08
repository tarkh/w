---
title: w-update
section: reference
order: 0
summary: Update all system and AUR packages (repo + AUR in one pass).
---

`w-update` — Update all system and AUR packages (repo + AUR in one pass)..

## Usage

```
Usage: w-update [command]

Info: Update all system and AUR packages (repo + AUR in one pass).

Commands:
  (none) | upgrade   Interactive full upgrade: repo + AUR (yay -Syu --sudoloop),
                     then refresh status and offer a reboot if the kernel changed.
  plan [--porcelain] Preflight (read-only): what a repo upgrade would touch, pending
                     AUR, kernel/reboot, free disk. Backs the AI-driven upgrade.
  check              Refresh the update count + reboot flag (non-root, quiet).
                     Writes $STATE_FILE for the bar block.
  status             Print the last known update status + checker state.
  news               Show the latest Arch Linux news (read before upgrading).
  enable             Turn the periodic update checker ON for this user.
  disable            Turn the periodic update checker OFF for this user.
  interval [min]     Show, or set, the periodic-check interval (systemd user timer).
  help               Show this help.

Status file : $STATE_FILE   Timer: $TIMER_UNIT (default $DEFAULT_INTERVAL)

Exit codes:
  0  Success   1  Runtime error   2  Usage error
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-update help`.
