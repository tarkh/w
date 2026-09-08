---
title: w-wallpaper
section: reference
order: 0
summary: Select the wallpaper for the current resolution tier.
---

`w-wallpaper` — Select the wallpaper for the current resolution tier..

## Usage

```
Usage: w-wallpaper <command> [options]

Info: Select the wallpaper for the current resolution tier.

Commands:
  set [--monitor N]       Detect monitor resolution and update wallpaper symlink
                            --monitor N  Use monitor index N (default: 0)
  get [--real]            Print current wallpaper path
                            --real       Print actual file instead of symlink path
  apply [--wait [SEC]]    Set wallpaper on all monitors via hyprpaper IPC
                            --wait [SEC] Wait for hyprpaper socket (default: 10s)
  tiers [--porcelain]     List the resolution tiers a theme may ship
                            --porcelain  One WIDTHxHEIGHT per line, largest first
  cover <WIDTHxHEIGHT>    Print how far the displayed master is scaled to fill
                          a panel of that pixel size (cover fit)
  help, --help            Show this help

Exit codes:
  0  Success
  1  Runtime error (missing file, broken symlink, hyprpaper not ready, etc.)
  2  Usage error (unknown command or option)

Examples:
  w-wallpaper set
  w-wallpaper set --monitor 1
  w-wallpaper get
  w-wallpaper apply
  w-wallpaper apply --wait
  w-wallpaper apply --wait 5
  w-wallpaper tiers --porcelain
  w-wallpaper cover 2880x1800
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-wallpaper help`.
