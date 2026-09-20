---
title: w-userdirs
section: reference
order: 0
summary: Standard home folders (Documents, Pictures, ...) that follow the language.
---

`w-userdirs` — Standard home folders (Documents, Pictures, ...) that follow the language.

## Usage

```
Usage: w-userdirs <command> [options]

Info: Standard home folders (Documents, Pictures, ...) that follow the language.

Commands:
  status [--porcelain]   Each folder's path and state, the language anchor, and
                         what the next login would rename
  sync [--dry-run]       The login step: create missing folders, and rename the
                         default-named ones when the language has changed
                         (--dry-run only reports)
  localize yes|no        Whether folders are renamed when the language changes
  help                   Show this help

Programs resolve a folder with `xdg-user-dir <NAME>` (NAME: DESKTOP DOWNLOAD
DOCUMENTS MUSIC PICTURES VIDEOS), never by its name. Move a folder yourself with
`xdg-user-dirs-update --set <NAME> <path>` and it is yours: no rename touches it.

Files: ~/.config/user-dirs.dirs (where the folders are)
       ~/.config/user-dirs.locale (the language they were named in)
       /etc/xdg/user-dirs.defaults (which folders exist)
Settings: w-conf cat userdirs

Exit codes: 0 success · 1 runtime error · 2 usage

Examples:
  w-userdirs status
  w-userdirs sync --dry-run
  w-userdirs localize no
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-userdirs help`.
