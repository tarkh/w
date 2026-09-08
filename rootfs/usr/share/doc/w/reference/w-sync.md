---
title: w-sync
section: reference
order: 0
summary: Track the W dev repo (edge channel) and apply updates, keeping user config intact.
---

`w-sync` — Track the W dev repo (edge channel) and apply updates, keeping user config intact..

## Usage

```
Usage: w-sync [command]

Info: Track the W dev repo (edge channel) and apply updates, keeping user config intact.

Commands:
  (none) | update   Fetch, show incoming commits, then pre-snapshot home →
                    git pull --ff-only → selective apply.sh. Needs sudo for apply.
  check             Refresh the machine-wide behind-count (quiet). Maintained by
                    the checkout owner and root; a no-op for anyone else. Writes
                    $STATE_FILE; on any refusal it records behind:-1 + err
                    rather than a false 0.
  log               Show the commits that an update would pull in — fetched live
                    for the owner and root, read from the last recorded check
                    for every other user.
  status            Print the last known sync status + channel.
  help              Show this help.

Options:
  --yes             With 'update': skip the pull/apply confirmation prompt and
                    never auto-reboot (only reports if one is needed). For
                    non-interactive callers (the AI actuation path); a human
                    running w-sync in a terminal should not need it.

Channel : $CHANNEL   Ref: $REF   Checkout: $REPO
Status  : $STATE_FILE

Exit codes:
  0  Success   1  Runtime error   2  Usage error
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-sync help`.
