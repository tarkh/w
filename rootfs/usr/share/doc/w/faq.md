---
title: FAQ
section: start
order: 2
summary: Short answers to common questions.
sources:
  - path: .claude/library/w-rollback.md
    sha256: 9c9d1deab14153a4d60dab390f7ef42c86dba88bb59cf5ada4d7e8a213b715a5
---

I keep this curated by re-reviewing it at each W release. Where a question
needs detail, the answer links to a guide or a recovery page instead of
duplicating it.

## General

**What is W?**
An Arch Linux distribution with a ready Hyprland/Quickshell desktop, W's own
`w-*` tools for the parts a desktop needs (updates, themes, network, security,
recovery), and automatic snapshots. See `w-info` for the tool list.

**Where are the configuration files?**
W-managed ones live in `/usr/share/w/defaults` (vendor), `/etc/w` (machine),
`~/.config/w` (user). Overriding to taste is normal — resetting to the W
defaults is one command per area: see `w-reset`.

**How do I find what a `w-*` command does?**
`w-info` lists them; `w-<tool> help` prints each tool's help; the command
reference of this documentation has a page per tool.

## Updates and recovery

**An update broke my system. How do I roll back?**
Reboot, pick the pre-upgrade snapshot in the boot menu, and follow
[RECOVERY.md](RECOVERY.md) (a copy is on disk). Snapper keeps the last few
transactions.

**Why does an update say "reboot pending"?**
The running kernel differs from the installed one. The reboot offered by
`w-update` closes windows gracefully first — cancel a save dialog and the
reboot is called off.

**What is `w-sync` / the "edge" channel?**
W updates its *packages* with `w-update` and its own configuration with the
edge channel (`w-sync`). The stable channel is planned but not live yet.

## Desktop

**My screen is black / a monitor died after I changed display settings.**
W guards against losing the last enabled output, and if something slips
through `w-monitor reset all` from a text console (Ctrl+Alt+F2) puts sane
defaults back. Details in [RECOVERY.md](RECOVERY.md).

**The fingerprint reader stopped unlocking.**
Re-enroll the finger with `w-fingerprint` (or **Hub → Input → Fingerprint**);
the traditional password always works as the fallback.

**A window I closed keeps coming back after I log in.**
That is session restore, on by default. Turn it off or exclude the app in
**Hub → System → Session**; see [the desktop guide](guide/desktop.md).

## Software

**How do I install something not in my list?**
`w-software` covers the two native channels: `yay` (repositories + AUR) and
Flatpak/Bazaar for sandboxed apps. Anything installed this way snapshots like
an update does.

**Is AUR safe?**
It is third-party packaging, reviewed by you at the PKGBUILD prompt the same
way any Arch user reviews it. W keeps boot-critical packages out of AUR where
it matters.
