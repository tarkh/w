---
title: w-fingerprint
section: reference
order: 0
summary: Enrol, list and delete the fingerprints of the current user.
---

`w-fingerprint` — Enrol, list and delete the fingerprints of the current user.

## Usage

```
Usage: w-fingerprint <command> [args]

Info: Enrol, list and delete the fingerprints of the current user.

Commands:
  status [--porcelain]  Show reader availability and all ten finger slots
  enroll <finger>       Enroll one finger; emits event=<name> lines while running
  delete <finger>       Delete one enrolled finger
  fingers               List accepted finger names
  help                  Show this help

Exit codes: 0 success · 1 runtime error · 2 usage
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-fingerprint help`.
