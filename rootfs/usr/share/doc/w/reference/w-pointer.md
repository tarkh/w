---
title: w-pointer
section: reference
order: 0
summary: Manage mouse, touchpad and swipe-gesture settings of the Wayland session.
---

`w-pointer` — Manage mouse, touchpad and swipe-gesture settings of the Wayland session.

## Usage

```
Usage: w-pointer <command> [args]

Info: Manage mouse, touchpad and swipe-gesture settings of the Wayland session.

Commands:
  status [--porcelain]   Show every setting (+ whether a touchpad is present)
  list [--porcelain]     List live pointer devices (mouse / touchpad)
  get <key>              Print one setting
  set <key> <value>      Change one setting (live + persisted)
  detect                 Re-scan touchpads and record their device names
  reset [<scope>|--all]  Restore defaults (scope: mouse | touchpad | gestures | cursor)
  keys                   List settable keys with their accepted values
  help                   Show this help

Config persisted to: $FRAG

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-pointer set mouse.sensitivity 0.3
  w-pointer set touchpad.tap_to_click on
  w-pointer set gestures.workspace_fingers 4
  w-pointer set cursor.menu_timeout 0.1
  w-pointer reset touchpad
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-pointer help`.
