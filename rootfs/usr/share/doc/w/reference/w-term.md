---
title: w-term
section: reference
order: 0
summary: Launch or query the configured terminal (single entry point).
---

`w-term` — Launch or query the configured terminal (single entry point)..

## Usage

```
Usage: w-term [command]

Info: Launch or query the configured terminal (single entry point).

Commands:
  (none)          Open a new terminal window
  -e CMD [ARGS…]  Run CMD in a new terminal window
  get             Print the active terminal name
  list            List known terminals (* = active)
  set <name>      Set the active terminal (writes user override)
  help            Show this help

Config: $SYS_CONF (vendor default) + $USER_CONF (user override)

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-term
  w-term -e btop
  w-term set ghostty
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-term help`.
