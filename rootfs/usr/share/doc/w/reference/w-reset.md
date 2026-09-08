---
title: w-reset
section: reference
order: 0
summary: Force-restore any W module's or bundle's config to its default.
---

`w-reset` — Force-restore any W module's or bundle's config to its default..

## Usage

```
Usage: w-reset <module|bundle|--all> [file] [--user <name>]

Info: Force-restore any W module's or bundle's config to its default.

Force-restore a module's config to the W default (backs up the current copy
first). Recovery for a hand-broken config, without waiting for an update.
Installed W-Pack bundles work the same way, by bundle name.

Commands:
  <module>          Reset every path the module owns (see 'w-reset list')
  <module> <file>   Reset a single home-relative path from that module
  <bundle>          Reset an installed W-Pack bundle's config the same way
  --all             Reset every module and every installed bundle
  list              List modules and bundles that have a reset manifest
  check             Report which managed files drifted from the W default
                    (read-only; nothing is restored)
  status            Show which pristine sources are available

Options:
  --user <name>     Target another user's home (root only; default: the
                    invoking user, or SUDO_USER / the primary uid-1000 user)

Scope & privileges:
  Home config resets for your OWN home need no root. Resetting another user's
  home, or any system/override path (/etc, /usr, /etc/w), needs root (sudo).

Exit codes:
  0  Success
  1  Runtime error (missing source, privilege, unknown module)
  2  Usage error

Examples:
  w-reset check                       # what drifted from the W default
  w-reset shell                       # restore your shell config to default
  w-reset quickshell config/bar.json  # one file
  w-reset dev                         # a W-Pack bundle's config, your home
  sudo w-reset dns                    # system + /etc/w override, needs root
  sudo w-reset --all --user alice
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-reset help`.
