---
title: w-hotkeys
section: reference
order: 0
summary: Manage Hyprland keybindings — profiles, catalog, custom binds.
---

`w-hotkeys` — Manage Hyprland keybindings — profiles, catalog, custom binds..

## Usage

```
Usage: w-hotkeys <command> [args]

Info: Manage Hyprland keybindings — profiles, catalog, custom binds.

Commands:
  status [--porcelain]        Show the active profile + effective binds
  catalog [--porcelain]       List tokens (token / category / default / chord / source / profile-chord)
  profiles [--porcelain]      List profiles (built-in + user), marking the active one
  use <profile>               Switch the active profile (live + persisted)
  set <token> <chord>         Rebind one action (empty chord "" unbinds it)
  reset <token|--all>         Revert token(s) to the active profile's chord
  custom [--porcelain]        List custom actions (chord → command)
  custom-add <chord> <exec>   Add a custom action (arbitrary chord → shell command)
  custom-rm <chord>           Remove a custom action by its chord
  profile-new <name> [--from <profile|current>]   Save a user profile
  profile-rm <name>           Delete a user profile
  help                        Show this help

Active fragment: $FRAG
Catalog:         $TOKENS      User profiles: $USER_PROFILES

Exit codes: 0 success · 1 runtime/validation error · 2 usage

Examples:
  w-hotkeys use i3-vim
  w-hotkeys set launcher "SUPER + Space"
  w-hotkeys set launcher ""            # unbind
  w-hotkeys reset launcher
  w-hotkeys custom-add "SUPER + C" "gnome-calculator"
  w-hotkeys custom-rm "SUPER + C"
  w-hotkeys profile-new mine --from current
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-hotkeys help`.
