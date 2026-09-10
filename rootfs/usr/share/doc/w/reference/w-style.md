---
title: w-style
section: reference
order: 0
summary: Render the active theme across all themed subsystems.
---

`w-style` — Render the active theme across all themed subsystems.

## Usage

```
Usage: w-style <command> [options]

Info: Render the active theme across all themed subsystems.

Commands:
  apply [<subsystem>|user|all]   Re-render the active theme (default: all)
  set <TOKEN> <#hex>             Patch one token in the system theme and re-apply
  status                         Show key resolved colors (system theme)

Subsystems (in apply order — [scope] user | system | dual):
$SUBSYSTEMS

  user   = all user-scope axes into $HOME (or /etc/skel as root); login render, no system work
  all    = user-scope (skel) + system axes; requires root (install-time)

Scope: user axes → invoking user's effective theme; system axes → system fallback
       (/etc/w/active-theme); dual axes → user channels + system channels when root.

Exit codes:
  0  Success
  1  Runtime error
  2  Usage error

Examples:
  w-style apply hyprland
  w-style apply all
  w-style set W_PALETTE_ACCENT "#9d6fa8"
  w-style status
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-style help`.
