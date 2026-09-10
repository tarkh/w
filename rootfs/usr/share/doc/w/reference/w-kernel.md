---
title: w-kernel
section: reference
order: 0
summary: Select the active kernel and toggle the hardening profile.
---

`w-kernel` — Select the active kernel and toggle the hardening profile.

## Usage

```
Usage: w-kernel <command> [options]

Info: Select the active kernel and toggle the hardening profile.

Commands:
  list [--porcelain]        Show the known kernels, which are installed, the default
                            and the running one
  set <zen|vanilla|lts>     Install the kernel (+paired headers) and make it default
  remove <zen|vanilla|lts>  Uninstall a kernel (+headers); refuses the running or
                            the default one
  harden <on|off|status>    Toggle the whole hardening profile (sysctl + cmdline)
                            (status takes --porcelain)
  help                      Show this help

Porcelain:
  list --porcelain          TSV, header + one row per kernel:
                            name  pkg  version  installed  default  running
  harden status --porcelain TSV, header + one row: state(on|off|mixed)  pending(yes|no)

Exit codes:
  0  Success
  1  Runtime error
  2  Usage error

Examples:
  sudo w-kernel set lts
  sudo w-kernel harden on
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-kernel help`.
