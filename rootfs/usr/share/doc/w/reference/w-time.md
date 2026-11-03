---
title: w-time
section: reference
order: 0
summary: Set the timezone, the system clock and NTP (systemd-timesyncd).
---

`w-time` — Set the timezone, the system clock and NTP (systemd-timesyncd).

## Usage

```
Usage: w-time <command> [args]

Info: Set the timezone, the system clock and NTP (systemd-timesyncd).

Commands:
  status                 Show timezone, clock, NTP state + the selected server set
  list-zones [--porcelain]
                         List timezones as "<offset>  <Zone>" (copy the Zone name)
  set-zone <Zone>        Set the timezone (root; e.g. Europe/Moscow)
  ntp on|off             Enable/disable network time sync (root)
  set-time <"Y-m-d H:M:S">
                         Set the clock manually (root; requires NTP off)
  servers <name>         Switch the NTP server set from the catalog (root)
  rtc [auto|utc|local]   Show/set the hardware clock mode (setting: root); auto =
                         local time when Windows is on this machine, else UTC
  apply                  Re-render the timesyncd drop-in from $CONF (after editing)
                         and apply the hardware clock mode
  help                   Show this help

Catalog & selection: $CONF   Rendered (generated): $DROPIN

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-time status
  w-time list-zones | grep -i berlin
  sudo w-time set-zone Europe/Moscow
  sudo w-time ntp off
  sudo w-time set-time "2026-07-23 14:30:00"
  sudo w-time servers cloudflare
  sudo w-time rtc utc
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-time help`.
