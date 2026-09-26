---
title: Packs — optional software bundles
section: guide
order: 10
summary: What a pack is, the bundles W offers, installing one for the machine and setting it up for your account, and how to undo it.
sources:
  - path: .claude/library/packs.md
    sha256: 77e6b1307966e37236394abcd9174756c7b4fee07b79972cb01ad747072f627b
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
- **localsend** — LocalSend, an open-source AirDrop-like way to send files to
  your phone, tablet or another computer: official apps on Linux, Windows,
  macOS, Android and iOS all talk the same open protocol over the local
  network — no account, no cloud. The pack seeds W's accent colour into it,
  opens the firewall for it on trusted (home) networks only, and adds a
  right-click "Send with LocalSend" action to Nemo. It does not start
  automatically — open it when you need it, or turn on
  `systemctl --user enable --now localsend.service` for it to sit in the tray,
  always ready to receive.
- **graphics** — 2D creative work: GIMP for raster editing and photo retouching
  (with the G'MIC filter suite), Inkscape for vector drawing and design, Krita
  for digital painting. All three follow the W theme (Krita through its "W"
  theme, selected for you unless you had picked another). The pack also
  wires [the AI assistant](ai.md) into both editors: it can draw, edit and
  export vector documents through an Inkscape server, and run edits inside a
  running GIMP and look at the result — with whatever model your profile uses,
  local or cloud. Generative painting in Krita is planned for a companion pack.
- **gaming** — Steam, Lutris and Heroic side by side on one shared
  Proton/Wine/MangoHud/gamemode foundation: Steam covers most of a typical
  library, Lutris is the catch-all for everything else (GOG, Amazon, native
  installers, emulation), Heroic talks to Epic/GOG's own APIs directly. The
  pack enables the `multilib` repository, matches the 32-bit graphics stack to
  your GPU, keeps your game library out of `@home` snapshots (it can run to
  hundreds of gigabytes and is fully recoverable from the storefronts
  themselves), and dresses the MangoHud FPS overlay (`Shift_F12`) and the
  Heroic window itself in your active W colours — Heroic opens in them from its
  very first launch, and follows every later theme change the next time you
  start it. Installing games on a second drive stays each launcher's own
  setting: Steam's **Settings → Storage**, Heroic's **Default Installation
  Path**, Lutris's **Default installation folder**. Use a Linux filesystem for
  that drive — games on NTFS or exFAT break under Proton.
- **virt** — desktop virtualization: libvirt and QEMU/KVM underneath, with
  virt-manager for full control and GNOME Boxes for creating a VM in one click
  from an ISO. A default network is ready to go the moment the pack is set up,
  and your account gets passwordless access to it — no extra steps before your
  first VM. A hardware TPM for guests that need one (Windows 11, an encrypted
  disk) is not included; add it yourself if you need it.
- **ai-extra** — the advanced stack for [the AI assistant](ai.md#advanced): local
  models, semantic memory, better web search.
- **comfyui** — local image and video generation with ComfyUI, a node-based
  editor and backend running as a system service on [localhost](ai.md#comfyui).
  The engine is matched to your GPU at install; models are shared machine-wide
  in `/var/lib/w/ai-models`. Open **ComfyUI** from the app menu, or
  `systemctl start comfyui`, and visit `http://127.0.0.1:8188/`.

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
