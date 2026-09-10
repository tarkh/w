---
title: w-langpack
section: reference
order: 0
summary: Show and deliver what a locale needs beyond LANG (translations, dictionary, font).
---

`w-langpack` — Show and deliver what a locale needs beyond LANG (translations, dictionary, font).

## Usage

```
Usage: w-langpack <command> [args]

Info: Show and deliver what a locale needs beyond LANG (translations, dictionary, font).

Commands:
  status [--porcelain]     Show the profile of the current system locale
  plan [<locale>] [--porcelain]
                           List the missing packages for a locale (default: current)
  apply [<locale>]         Install the missing packages + set the console font (root)
  font [<locale>]          Set only the console font (root; offline-safe)
  help                     Show this help

Config: $CONF (FONT=)   Catalog: pacman sync db

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-langpack status
  w-langpack plan ru_RU.UTF-8 --porcelain
  sudo w-langpack apply
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-langpack help`.
