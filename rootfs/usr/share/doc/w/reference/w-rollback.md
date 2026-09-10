---
title: w-rollback
section: reference
order: 0
summary: Roll the system back to a btrfs snapshot, on either boot path.
---

`w-rollback` — Roll the system back to a btrfs snapshot, on either boot path.

## Usage

```
Usage: w-rollback <command> [options]

Info: Roll the system back to a btrfs snapshot, on either boot path.

Commands:
  status [--porcelain]  Where the system is booted from and what a rollback would do
  list [--porcelain]    Snapshots available to roll back to (--porcelain: number,
                        type, paired pre-ID, ISO date and description, one TSV line each)
  run [<number>]        Perform the rollback (interactive; asks before it changes anything)
  launch [<number>]     Open 'run' in a terminal window, asking for your password there
  help                  Show this help

Rolling back never deletes the system it replaces: the outgoing root is kept and
can be booted again. See /usr/share/doc/w/RECOVERY.md for the whole procedure,
including the case where the machine no longer boots at all.

Exit codes:
  0  Success
  1  Runtime error
  2  Usage error

Examples:
  w-rollback status
  sudo w-rollback run
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-rollback help`.
