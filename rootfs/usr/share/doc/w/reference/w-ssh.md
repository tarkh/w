---
title: w-ssh
section: reference
order: 0
summary: Choose the session's SSH agent and generate per-host key selectors from it.
---

`w-ssh` — Choose the session's SSH agent and generate per-host key selectors from it..

## Usage

```
Usage: w-ssh <command>

Info: Choose the session's SSH agent and generate per-host key selectors from it.

Commands:
  status            Active agent, socket state, generated selectors
  list              List known agent backends (* = active)
  use <name>        Switch the SSH agent (see list; 'none' = no agent)
  link              Re-point the stable socket at the active backend (login hook)
  sync              Regenerate per-host key selectors from the agent's keys
  include           Add the config.d Include line to $USER_CONFIG
  help              Show this help

Catalog & selection: layered ssh.conf (origin: w-conf cat ssh)
Generated (do NOT edit): $GEN + $KEYS_DIR/

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-ssh use bitwarden
  w-ssh sync
  w-ssh status
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-ssh help`.
