---
title: w-mirrors
section: reference
order: 0
summary: Keep the pacman mirrorlist fresh — rank mirrors on a schedule or on demand.
---

`w-mirrors` — Keep the pacman mirrorlist fresh — rank mirrors on a schedule or on demand..

## Usage

```
Usage: w-mirrors <command>

Info: Keep the pacman mirrorlist fresh — rank mirrors on a schedule or on demand.

Commands:
  status [--porcelain]  Show the policy, the current list and when it was ranked (default)
  check [--quiet]       Probe the head of the list; non-zero if nothing serves data
  rank [--scheduled]    Re-rank the mirrorlist now (--scheduled = the timer's entry point)
  set <key> <value>     Change one policy key (see the key list below)
  enable | disable      Turn the periodic ranking timer on/off
  apply                 Install the timer state from the config (used by apply.sh --mirrors)
  help                  Show this help

Policy source: /etc/w/mirrors.conf over /usr/share/w/defaults/mirrors.conf
Keys: COUNTRY PROTOCOL AGE SCORE COUNT THREADS CONNECT_TIMEOUT DOWNLOAD_TIMEOUT
      INTERVAL_DAYS SKIP_METERED   (`w-conf cat mirrors` shows the merged result)

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-mirrors status
  sudo w-mirrors rank
  sudo w-mirrors set COUNTRY Germany
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-mirrors help`.
