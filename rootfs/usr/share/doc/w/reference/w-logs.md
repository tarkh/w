---
title: w-logs
section: reference
order: 0
summary: Set how long W keeps logs (journal + /var/log + W's own logs), one policy.
---

`w-logs` — Set how long W keeps logs (journal + /var/log + W's own logs), one policy.

## Usage

```
Usage: w-logs <command>

Info: Set how long W keeps logs (journal + /var/log + W's own logs), one policy.

Commands:
  status               Show usage + current retention across all log nodes (default)
  keep <days>          Keep <days> of history everywhere, then apply
  limit <size>|off     Cap size (journal total / logrotate per-file); off clears it
  vacuum time <span>   Trim the journal NOW to a kept span (e.g. 2w, 30d, 6month)
  vacuum size <size>   Trim the journal NOW to a max total size (e.g. 500M, 2G)
  apply                Re-render every node from $CONF (after hand-editing it)
  show [unit] [-p P] [-n N]   Read recent journal (passthrough to journalctl)
  help                 Show this help

Policy source: $CONF   (generated files carry a do-NOT-edit banner)

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-logs status
  sudo w-logs keep 14
  sudo w-logs limit 1G
  sudo w-logs vacuum time 7d
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-logs help`.
