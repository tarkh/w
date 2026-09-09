---
title: Packs — optional software bundles
section: guide
order: 10
summary: What a pack is, the bundles W offers, installing one for the machine and setting it up for your account, and how to undo it.
sources:
  - path: .claude/library/packs.md
    sha256: 83d58d741f78be6eb9bdab294fc288880eead52a7cdc707e3ad737a83e42d7c5
---

W installs in two layers. The **base** is everything a working desktop needs and
is always there. **Packs** are the second layer: optional bundles you add when
you want them.

A pack is named after a *direction* rather than a tool — `containers`, not
`podman`; `dev`, not a list of editors. You choose the capability; which
software delivers it is W's problem. Each pack brings its own packages, its own
configuration, its own colours for the active theme, and a setup step that wires
it into the desktop — so a pack arrives configured, not merely downloaded.

## What is on offer

- **containers** — rootless Podman with the Docker command line and a terminal
  UI for it.
- **dev** — a development environment: the Zed editor, git tooling, a toolchain
  version manager.
- **flatpak** — sandboxed third-party applications: Flatpak with Flathub, the
  Bazaar store and Flatseal for managing app permissions. This is the answer to
  "how do I install an application that is not packaged for Arch".
- **bitwarden** — the Bitwarden desktop app wired into W's slots: SSH agent,
  biometric unlock, tray autostart.
- **ai-extra** — the advanced stack for [the AI assistant](ai.md#advanced): local
  models, semantic memory, better web search.

**Hub → Packs** lists them with their state, and installing from there opens a
terminal so you can watch it happen. From a shell the same list is `w-pack
list`.

Packs are also offered during installation, so a new machine can arrive with the
ones you want already set up. A couple of them only make sense from a running
system and are deliberately absent from that checklist.

## Installing, and setting up for your account

A pack has two halves, and the panel names them:

- **The machine half** — packages and system configuration. It is installed once
  for the whole machine and needs an administrator: `sudo w-pack install
  <name>`, or the **Install** button.
- **Your half** — the parts that live in your home directory. It is set up per
  account, needs no password, and is *not* done for everybody automatically:
  spending someone else's disk on a choice they never made would be rude.

That is why a pack can show **On this machine, but not set up for you** with a
**Set up** button next to it. Nothing is broken — it is an honest "not yet", and
one click (or `w-pack setup <name>`) finishes it. On a single-account machine
you will rarely see this state, because installing does both halves for you.

Installing is snapshotted like any other package change, so it is reversible the
same way — see [the update guide](updates.md#if-an-update-goes-wrong).

## Undoing a pack

There is no *remove* yet, and that is a deliberate omission rather than an
oversight: packs share dependencies with the base system and with each other,
and automatic removal risks taking something else with it. It is a planned
addition.

What you can do today:

- `w-reset <pack>` returns the pack's configuration to the W default, backing up
  your current copies first. No administrator rights needed for your own home.
- The pre-install snapshot is still in the boot menu if you would rather rewind
  the whole thing.

## Keeping packs current

When a W update changes a pack you already have, it is re-applied for you — the
configuration, theming and setup step, without touching packages. There is
nothing to do by hand. If a pack's configuration ever looks stale, `sudo w-pack
refresh` does that pass on demand; it works offline and takes seconds.
