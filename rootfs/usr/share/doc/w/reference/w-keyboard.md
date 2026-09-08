---
title: w-keyboard
section: reference
order: 0
summary: Manage the keyboard-layout ring of the Wayland session (XKB).
---

`w-keyboard` — Manage the keyboard-layout ring of the Wayland session (XKB)..

## Usage

```
Usage: w-keyboard <command> [args]

Info: Manage the keyboard-layout ring of the Wayland session (XKB).

Commands:
  status [--porcelain]        Show the current ring (layout / variant / options)
  list [--porcelain]          List selectable layouts (code + description)
  variants <code> [--porcelain]   List variants of a layout
  add <code[:variant]>        Add a layout to the ring (live + persisted)
  remove <code>               Remove a layout from the ring (min 1 kept)
  set-toggle <grp:*>          Set the layout-switch key (XKB grp:* option; live + persisted)
  set-default <code>          Make a layout the login default (move it to ring front)
  set-repeat <rate> <delay>   Key auto-repeat: repeats/second (1-100) + delay in ms (100-2000)
  set-numlock <on|off>        Engage NumLock at login
  help                        Show this help

Ring persisted to: $FRAG   Catalog: $LST

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-keyboard add de
  w-keyboard add us:dvorak
  w-keyboard remove ru
  w-keyboard set-toggle grp:ctrl_shift_toggle
  w-keyboard set-repeat 30 400
  w-keyboard set-numlock on
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-keyboard help`.
