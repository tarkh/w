---
title: Packs — optional software bundles
section: guide
order: 10
summary: What a pack is, the bundles W offers, installing one for the machine and setting it up for your account, and how to undo it.
sources:
  - path: .claude/library/packs.md
    sha256: bd349cb3e68549c98add90316a45d89cadcafca001745435172c8132347c3079
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
- **office** — the office direction: LibreOffice for documents, spreadsheets
  and presentations, pdfarranger and xournalpp for PDF page surgery and
  annotation, and the Obsidian markdown knowledge base for notes.
- **bitwarden** — the Bitwarden desktop app wired into W's slots: SSH agent,
  biometric unlock, tray autostart.
- **telegram** — Telegram Desktop with W's colours: the pack renders the active
  theme into Telegram's own theme file, flat chat wallpaper included, and a
  Telegram that has never been started on your account opens in those colours
  from its very first launch (with a plain window frame — no title bar of its
  own). If Telegram had already run before the pack was set up, its data is
  left alone and you pick the file once in the app (Settings → Chat settings →
  Chat background → Choose from file). Either way, from then on every theme
  switch recolours a running Telegram live.
- **ai-extra** — the advanced stack for [the AI assistant](ai.md#advanced): local
  models, semantic memory, better web search.

**Hub → Packs** lists them with their state and does the whole life cycle —
installing, setting up and removing. Anything long or privileged opens a terminal
so you can watch it happen. From a shell the same list is `w-pack list`.

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

## Removing a pack

In **Hub → Packs**, every pack that is on the machine has a **Remove** button. It
asks first, and the confirmation offers the same two answers the commands do —
take the pack off the machine (needs an administrator), or undo only your own
account's layer. From a shell:

```
sudo w-pack remove <pack>
```

This undoes what W did, which is not the same as uninstalling the software.
Removing a pack takes away its wiring: the pack stops being listed as installed,
its colours stop being rendered, its session variables and shell hooks go, its
configuration files that W owned are deleted (a backup is made first), and
whatever it set up — a service, a command name, a system-wide setting — is put
back the way it was.

**Your packages stay by default.** They are `pacman`'s business, not W's, so the
exact command to remove them is printed for you to run — or add `--packages` and
the removal does it in the same pass. The panel never adds that flag on your
behalf: taking the packages is the one irreversible part, and it is not a choice to
make before you have seen the list. That is also why the terminal a removal opens
waits for you before it closes — the report at the end is the point of it. Anything another pack you still have also
needs is left out of that list automatically.

**Your data is never deleted.** Downloaded models, container images, toolchains,
installed Flatpak applications — those are yours, and W only tells you where they
are and how much room they take. The same goes for configuration files you own
rather than W: since the software usually stays installed, deleting your settings
for it would be damage rather than an undo, so they are listed and left alone.

If you removed a pack's packages by hand and it keeps coming back after an
update, this is why: without `w-pack remove`, W still thinks the pack is yours
and re-applies it. Run the command above and it stays gone.

```
w-pack unsetup <pack>
```

The same thing for **your account only**, with no administrator rights: the pack
stays on the machine for everyone else, and it simply stops being set up for you.
`w-pack setup <pack>` brings it back whenever you want.

To put a pack's configuration back to the W default **without removing it**, use
`w-reset <pack>` — it restores from the pack's own files, backing up your current
copies first, and needs no administrator rights for your own home. The pre-install
snapshot is also still in the boot menu if you would rather rewind everything.

## Keeping packs current

When a W update changes a pack you already have, it is re-applied for you — the
configuration, theming and setup step, without touching packages. There is
nothing to do by hand. If a pack's configuration ever looks stale, `sudo w-pack
refresh` does that pass on demand; it works offline and takes seconds.
