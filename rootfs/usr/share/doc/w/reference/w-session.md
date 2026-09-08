---
title: w-session
section: reference
order: 0
summary: Remember the graphical session (windows, workspaces, split layout) and
---

`w-session` — Remember the graphical session (windows, workspaces, split layout) and.

## Usage

```
Usage: w-session <command> [args]

Info: Remember the graphical session (windows, workspaces, split layout) and
      put it back at the next login.

Commands:
  status [--porcelain]        Show the mode and what is currently saved
  save                        Snapshot the session now
  restore [--dry-run]         Reopen the saved session (--dry-run just lists it)
  close [--workspace <name>] [--timeout <sec>] [--dry-run]
                              Ask every window to close and wait for it, leaving
                              any "Save changes?" dialog reachable. Exit 1 if a
                              window stayed open (the user cancelled a dialog).
                              --dry-run only prints how many would be asked.
  forget                      Delete the saved session
  layout list [--porcelain]   Show the saved named layouts
  layout save <name> [--workspace]
                              Save every workspace under <name>, or just the
                              focused one (--workspace), which then applies onto
                              whatever workspace is focused later
  layout apply <slug> [--dry-run] [--foreground]
                              Close what is open (save dialogs stay reachable,
                              cancelling one aborts) and reopen the layout. Runs
                              detached, because it closes the terminal it was
                              typed in; --foreground keeps it attached, for
                              watching it work over ssh.
                              --dry-run only prints how many windows would close
  layout delete <slug>        Delete a saved layout
  mode <off|save|restore>     off: record nothing · save: record only ·
                              restore: record and reopen at login
  autosave <seconds>          Background snapshot floor (0 = graceful exit only)
  terminal <off|allowlist|all>
                              Reopen the program running inside a terminal
  exclude list                Show the never-record class patterns
  exclude add <regex>         Never record windows of this class
  exclude remove <regex>      Drop a pattern again
  daemon                      Run the snapshot daemon (w-session-save.service)
  help                        Show this help

Snapshot: ~/.local/state/w/session.json   Settings: w-conf cat session
Named layouts: ~/.local/share/w/layouts/
Relaunch overrides: ~/.config/w/session-apps.tsv
Terminal allowlist: ~/.config/w/session-terminal.list

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-session mode restore
  w-session exclude add 'steam_app_.*'
  w-session restore --dry-run
  w-session layout save 'Работа'
  w-session layout save 'Чтение' --workspace
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-session help`.
