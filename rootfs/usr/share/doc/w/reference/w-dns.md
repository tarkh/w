---
title: w-dns
section: reference
order: 0
summary: Switch DNS provider and DNS-over-TLS mode (systemd-resolved).
---

`w-dns` — Switch DNS provider and DNS-over-TLS mode (systemd-resolved).

## Usage

```
Usage: w-dns <command>

Info: Switch DNS provider and DNS-over-TLS mode (systemd-resolved).

Commands:
  status            Show selection + resolved state (resolvectl status)
  list              List available DoT providers from the catalog (* = active)
  provider <name>   Switch resolver (e.g. quad9 cloudflare mullvad google adguard)
  on                DoT = opportunistic  (W default; falls back if blocked)
  strict            DoT = yes            (guaranteed encryption; may break captive)
  off               System default: per-link DHCP DNS (removes the W override)
  apply             Re-render from $CONF (after hand-editing the catalog)
  help              Show this help

Catalog & selection: $CONF   Rendered (generated): $DROPIN

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-dns status
  sudo w-dns provider cloudflare
  sudo w-dns strict
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-dns help`.
