---
title: w-firewall
section: reference
order: 0
summary: Toggle the firewall zone between home and public (firewalld).
---

`w-firewall` — Toggle the firewall zone between home and public (firewalld).

## Usage

```
Usage: w-firewall <command>

Info: Toggle the firewall zone between home and public (firewalld).

Commands:
  status        Show default zone, active zones and the default zone's ruleset
  home          Set default zone to 'home'  (W baseline: inbound ssh + mdns)
  public        Set default zone to 'public' (untrusted networks; inbound ssh only)
  help          Show this help

Exit codes:
  0  Success
  1  Runtime error
  2  Usage error

Examples:
  w-firewall status
  sudo w-firewall public
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-firewall help`.
