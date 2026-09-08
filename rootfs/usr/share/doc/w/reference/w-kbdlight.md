---
title: w-kbdlight
section: reference
order: 0
summary: Keyboard backlight — level, media keys, and light at the LUKS prompt.
---

`w-kbdlight` — Keyboard backlight — level, media keys, and light at the LUKS prompt..

## Usage

```
Usage: w-kbdlight <command> [value]

Info: Keyboard backlight — level, media keys, and light at the LUKS prompt.

Commands:
  status              Show device, level and boot policy (default)
  get [--raw]         Print the level as a percentage (--raw: device units)
  set <N>[%]          Set the level (percent, or device units with no '%')
  up [N] / down [N]   Step the level by N percent (default: STEP from the config)
  toggle              Off <-> the last non-zero level
  off / restore       Stash-and-clear / put back — used by the idle listener
  device              Print the resolved backlight device name
  boot <N|off>        Level for the LUKS/boot prompt, then rebuild the initramfs
  help                Show this help

Config: /etc/w/kbdlight.conf   (vendor defaults: /usr/share/w/defaults/kbdlight.conf)
Idle-off is part of the idle policy: sudo w-power idle <ac|bat> kbdlight <seconds>

Exit codes:
  0  Success   1  Runtime error (no backlight on this machine)   2  Usage error

Examples:
  w-kbdlight status
  w-kbdlight up
  w-kbdlight set 40%
  sudo w-kbdlight boot 50
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-kbdlight help`.
