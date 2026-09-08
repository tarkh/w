---
title: w-locale
section: reference
order: 0
summary: Show and switch the system UI language (LANG).
---

`w-locale` — Show and switch the system UI language (LANG)..

## Usage

```
Usage: w-locale <command> [args]

Info: Show and switch the system UI language (LANG).

Commands:
  status [--porcelain]   Show the current LANG
  list [--porcelain]     List selectable UTF-8 locales
  set <locale>           Switch LANG (root; generates the locale; needs relogin)
  help                   Show this help

Config: $CONF   Catalog: $SUPPORTED

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-locale status
  sudo w-locale set ru_RU.UTF-8
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-locale help`.
