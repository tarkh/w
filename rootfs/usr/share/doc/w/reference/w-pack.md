---
title: w-pack
section: reference
order: 0
summary: Install and inspect optional W software bundles (packs).
---

`w-pack` — Install and inspect optional W software bundles (packs)..

## Usage

```
Usage: w-pack <command> [bundle] [--user <name>] [--porcelain]

Info: Install and inspect optional W software bundles (packs).

Optional software bundles (W-Packs) — opt-in add-ons on top of the base system.
A bundle has a MACHINE layer (packages, system config, services — installed once,
needs root) and a PER-USER layer (its tools and config in your home).

Commands:
  list                 List available bundles and their state
  install <bundle>     Install a bundle: machine layer, then your per-user layer
  setup <bundle>       Set up an already-installed bundle for YOUR account
                       (no root, no polkit — it only writes your own home)
  refresh [<bundle>]   Re-apply installed bundles from the staged tree, WITHOUT
                       touching packages (config + w-style + AI skill + setup)
  status [<bundle>]    Show what is installed (all, or one bundle)
  help                 Show this help

Options:
  --user <name>        Act for another account (root only; default: the invoking
                       user, or SUDO_USER / the primary uid-1000 user)
  --porcelain          Machine-readable `list`, one bundle per line:
                       <name> TAB <machine:yes|no> TAB <user:yes|no|n/a> TAB <desc>

Notes:
  install and refresh require root (packages + system paths); setup does not.
  Bundles are self-contained under $PACKS_DIR; machine state is recorded in
  $STATE, your own layer in ~/$USER_STATE_REL.
  A bundle someone else installed is NOT set up for you automatically — that
  would spend your disk and network on a choice you never made. `w-pack list`
  says so plainly, and `w-pack setup <bundle>` is the one command that fixes it.
  refresh is what an update calls: `w-sync update` runs it after an apply that
  touched the bundle tree, so a bundle's own idempotent setup (marker regions,
  drop-ins, legacy-layout cleanups) is replayed on every machine instead of
  waiting for someone to reinstall the bundle by hand. It replays the per-user
  layer for every account that already has it — and only those.
  remove is a later phase (shared pacman deps make automatic removal risky). To
  put a bundle's config back to the W default now, use `w-reset <bundle>`.

Exit codes:
  0  Success
  1  Runtime error (unknown bundle, missing source, privilege)
  2  Usage error

Examples:
  w-pack list
  sudo w-pack install containers
  w-pack setup ai-extra              # catch my own account up, no sudo
  sudo w-pack refresh
  w-pack status
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-pack help`.
