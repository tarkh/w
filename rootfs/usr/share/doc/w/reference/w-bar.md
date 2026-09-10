---
title: w-bar
section: reference
order: 0
summary: Choose which status-bar blocks show on which monitor (W Hub -> Appearance -> Bar).
---

`w-bar` — Choose which status-bar blocks show on which monitor (W Hub -> Appearance -> Bar).

## Usage

```
Usage: w-bar <command> [args]

Info: Choose which status-bar blocks show on which monitor (W Hub -> Appearance -> Bar).

Commands:
  status [--porcelain]                  Bar on/off per output + every block's state
  list [<output>] [--porcelain]         Block catalog (id, type, zone, parent); with an
                                        output, its effective on/off for that output
  monitor <output> <on|off>             Switch the whole bar on that output
  block <output> <id> <on|off|default>  Show/hide one block there; "default" drops the
                                        per-output override and follows bar.json again
  reset [<output>]                      Drop per-output overrides (one output, or all)
  help                                  Show this help

Blocks are addressed by their "id" in bar.json (unique file-wide, nested zone items
included). A block with no id renders normally but cannot be addressed here.

Config: $BAR_JSON
GUI: W Hub -> Appearance -> Bar

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-bar status
  w-bar block eDP-1 tray off
  w-bar monitor HDMI-A-1 on
  w-bar block HDMI-A-1 systemMonitors default
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-bar help`.
