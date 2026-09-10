---
title: w-conf
section: reference
order: 0
summary: Read and write W's layered configuration (vendor → admin → user).
---

`w-conf` — Read and write W's layered configuration (vendor → admin → user).

## Usage

```
Usage: w-conf <command> [options]

Info: Read and write W's layered configuration (vendor → admin → user).

Commands:
  get <subsys> <key> [default]   Print the effective value
  origin <subsys> <key>          Print the layer that won (--path: its file)
  list [<subsys>]                Print KEY=VALUE (no subsys: list subsystems)
  cat <subsys>                   Annotated view: layers, files, winner per key
  layers <subsys>                Print the layer chain and which files exist
  scope <subsys> [<key>]         Who may set a key: system | user | both
                                 (no key: KEY<TAB>scope for the whole subsystem)
  set <subsys> <key> <value>     Write to the system layer (--user: user layer)
  unset <subsys> <key>           Drop the key from that layer (--user likewise)
  help                           Show this help

Options:
  --user            Act on the user layer (~/.config/w) instead of /etc/w
  --user-of <name>  Inspect/write THAT user's layer (root defaults to the
                    invoking user, matching what the subsystems read)
  --porcelain       list: KEY<TAB>VALUE<TAB>LAYER<TAB>locked<TAB>SCOPE (for GUIs)
  --prefix <P>      list/cat: only keys starting with P (e.g. NTP_)
  --path            origin: print the winning file instead of the layer name

Exit codes:
  0  Success
  1  Runtime error (unwritable layer, policy-locked key, bad value)
  2  Usage error

Examples:
  w-conf get power CHARGE_LIMIT
  w-conf origin ai HOST
  w-conf cat power
  w-conf list time --prefix NTP_
  sudo w-conf set power CHARGE_LIMIT 80
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-conf help`.
