---
title: w-style
section: reference
order: 0
summary: Render the active theme across all themed subsystems.
---

`w-style` — Render the active theme across all themed subsystems..

## Usage

```
Usage: w-style <command> [options]

Info: Render the active theme across all themed subsystems.

Commands:
  apply [<subsystem>|user|all]   Re-render the active theme (default: all)
  set <TOKEN> <#hex>             Patch one token in the system theme and re-apply
  status                         Show key resolved colors (system theme)

Subsystems (in apply order — [scope] user | system | dual):
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-style help`.
