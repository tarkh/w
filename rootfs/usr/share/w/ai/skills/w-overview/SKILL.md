---
name: w-overview
description: >-
  Orient here first for any task on a W Linux machine. Explains what W is, its
  filesystem and config layout, and the first-party w-* commands for theming,
  updates, network, DNS, firewall, disk encryption, and wallpaper. Load this
  before answering questions about how W is organized or which command to use.
sources:
  - path: .claude/library/essentials.md
    sha256: a24041cbc98c39ae853e16a743b73008f2478fa1885292b1fbdbf971a6e92bce
---

# W Overview

**W** is an Arch Linux–based personal distribution. It is a reproducible install:
every machine gets fresh Arch packages but a fixed, curated configuration. The OS
identifies as `w` in `/etc/os-release`.

The desktop is **Hyprland** (Wayland compositor) with a single **Quickshell** UI
providing the bar, launcher, notifications, on-screen display, lock screen, and
login greeter. The default terminal is **Ghostty**, the shell is **zsh** with
Starship, the browser is **Firefox**, and the file manager is **Nemo** (GUI) /
**yazi** (CLI). Everything is themed from one source (see *Theming* below).

## Filesystem & config layout

W keeps its own state and configuration under predictable roots:

| Path | Purpose |
|---|---|
| `/usr/share/w/defaults/` | W's own config defaults per subsystem — overwritten by every update. |
| `/etc/w/` | System-scope W config: this machine's DEVIATIONS from those defaults, plus the active theme pointer and themes. |
| `/etc/w/themes/<name>/` | A theme: `theme.conf` (color/geometry/effect tokens), `wallpaper/`, optional `logo/`, `motion.conf`, `font.conf`. |
| `~/.config/w/` | Per-user overrides: user themes and the user's active-theme pointer (no root needed). |
| `~/.config/quickshell/w/` | The Quickshell UI config tree, live. Split by ownership: `shell.qml`, `core/`, `modules/` are W's (refreshed by every update, in EVERY account's home); `config/*.json` (bar, launcher, notifications, …) are the user's — written once, never overwritten. |
| `/run/w/` | Runtime state: the resolved wallpaper manifest under `/run/w/wallpaper/`, and `/run/w/fp/` where the auth dialog parks its per-user "ask me for the password, not my fingerprint" flag. |
| `/usr/share/w/ai/` | This AI knowledge base (read-only, shipped). |
| `/usr/share/doc/w/` | The user documentation, on disk: `index.md`, `faq.md`, `guide/`, a page per command under `reference/`, and `RECOVERY.md`. |
| `/usr/bin/w-*` | The first-party W command-line tools — everything a person, a unit or a config calls by name. |
| `/usr/lib/w/` | W's internals: sourced shell libraries, the polkit dispatchers, the `w-mcp` Python package, the `w-style` rendering axes. Not on `PATH`, and not meant to be run by hand. |

Point people at the shipped documentation rather than improvising an answer: it is
the same text the desktop shows on <kbd>Super+F1</kbd> (and behind the **?** button
in a Hub panel), it works with no network, and `reference/w-<cmd>.md` is generated
from that command's own help, so it cannot drift from the tool. `w-info` lists every
command with a one-line description.

Themes resolve **user over system**: a per-user theme in `~/.config/w/` shadows the
system one in `/etc/w/`, and both sit above W's defaults in `/usr/share/w/defaults/`
(`w-conf cat <subsys>` shows which layer each value came from).

## Key `w-*` commands

W exposes each subsystem through a first-party CLI. Prefer these over ad-hoc
commands — they encode W's conventions and keep the system consistent. Most support
`status` and a `--help`.

**Appearance**
- `w-theme set <name>` / `w-theme list` / `w-theme current` / `w-theme reset` —
  switch the active theme (seamless crossfade; per-user by default, `sudo` for
  system scope). Adding `~/.config/w/themes/<name>/` makes a new theme available.
- `w-theme new <name> --wallpaper <image>` / `w-theme edit <name>` / `w-theme rm <name>` —
  build a whole theme (palette + every wallpaper size) out of one picture, rebuild an
  existing one's palette without touching its wallpaper, or delete one. Per-user without
  root, system-wide with `sudo`. See the *w-theming* skill for the options.
- `w-style apply <axis>` — re-render one theming axis (colors, geometry, effects,
  font, gtk, qt, hyprlock, …). Usually invoked by `w-theme`; use directly to
  re-apply after editing a theme's `theme.conf`.
- `w-wallpaper set|get|apply` — resolution-aware wallpaper from the active theme
  (multi-monitor, per-resolution tiers with bidirectional fallback).

**System**
- `w-conf cat <subsys>` / `w-conf get|origin <subsys> <KEY>` — read W's layered
  configuration and see **which layer** a value came from (W defaults → site defaults
  → admin `/etc/w` → user `~/.config/w` → **site policy**, which locks the key). This
  is the first thing to run when a setting "is not what the file says" or an edit
  appears to have no effect. `w-conf scope <subsys> [KEY]` says who may set it at all.
- `w-update` — interactive full upgrade (repo + AUR in one pass via yay).
  `w-update check` (no root) refreshes the available-update count shown in the bar;
  `w-update status`, `w-update news`. Never use bare `pacman -Sy`.
  Upgrading — like `w-sync update` and `w-pack install` — is for this machine's
  **administrators** (members of the `wheel` group); anyone else gets a one-line
  explanation instead of a password prompt, while the read-only commands above keep
  working for everyone. See **w-maintenance** for the update channel itself.
- `w-mirrors status|check` — the pacman mirror list this machine downloads from
  (read-only, no root). `w-mirrors check` is the tool to reach for when an install or
  upgrade fails to download: it says whether the mirrors are actually serving data,
  so a delivery problem is not mistaken for a broken package. Rebuilding the list
  (`sudo w-mirrors rank`) is an administrator's job and costs minutes plus a few
  hundred MB — the machine also does it on its own schedule. See **w-updates**.
- `w-pack list|status` — optional software bundles (W-Packs). Installing one is an
  administrator's job, but a bundle has a **per-account half** that anyone sets up
  for themselves with `w-pack setup <bundle>` — no root, no prompt. So "installed"
  is machine-wide while the tools may still be missing for the person asking; the
  listing distinguishes the two. Both halves have an inverse (`w-pack remove`,
  `w-pack unsetup`), and it undoes W's wiring, not the software: packages and data
  stay unless asked for. See **w-packs**.
- `w-locale status|list [--names]|set <locale>` + `w-langpack status|plan|apply` —
  the system interface language. `w-locale` owns `LANG` and nothing else; everything
  a language ALSO needs — the Firefox language pack, a spell-checking dictionary,
  translated man pages, the Linux console font — is `w-langpack`'s. Switching the
  language deliberately does not install those (it must stay instant and work
  offline), so "I changed the language but Firefox is still English" is answered by
  `w-langpack plan`, not by hunting for a setting. Some CLI tools (eza, atuin, helix,
  micro, yazi, btop) have no translations upstream at all and stay English. The `w-*`
  commands themselves: **help is translated** (so is `w-info` and the offline command
  reference), **runtime output is not** — an English error under a Russian help is
  expected, not a half-finished translation. See **w-input**.
- `w-kernel` — select the active kernel (`linux-zen` default, vanilla `linux`, or
  `linux-lts`) and toggle the sysctl/cmdline hardening profile. Switching never removes
  a kernel, so every installed one stays bootable. See the w-security skill.
- `w-kbdlight` — keyboard backlight: `status`, `up`/`down`/`set`/`toggle`, and
  `boot <N|off>` for the level at the disk-password prompt. Use it rather than
  `brightnessctl` for the keyboard (see **w-power** for why, and for the
  "go dark on idle" half, which lives in `w-power idle <ac|bat> kbdlight`).

**Network & security**
- `w-dns provider <name>` / `w-dns on|strict|off` / `w-dns status` — DNS-over-TLS
  via systemd-resolved (default provider Quad9).
- `w-firewall public|home` — switch the firewalld zone; `w-firewall status`.
- `w-ssh status|list|use <agent>|sync|include` — which SSH agent the session
  uses (gcr by default; a password manager's agent replaces it) and the
  per-host key selectors that keep an agent full of keys usable. `w-ssh status`
  is the first stop for any SSH or `git push` failure — see **w-security**.
- `w-crypt status|enroll-tpm|recovery-add` — LUKS2 disk-encryption management (only
  on encrypted installs).
- `w-secureboot enable|disable|status` — Secure Boot via sbctl (encrypted/Limine
  path). Post-install only — the installer never enables SB and does not ask about it.
  `enable` is two-phase (enroll, reboot, run it again) — see **w-security**.

## Desktop essentials

- Compositor config is Lua: `~/.config/hypr/hyprland.lua` (Hyprland 0.55+ protocol).
- The session is systemd-managed via **uwsm** (`wayland-wm@hyprland.service`); logs
  go to journald.
- Common keybindings (defaults; remappable via the W Hub / `w-hotkeys`): `$mod+D`
  launcher, `$mod+Space` W Hub, `$mod+V` clipboard history, `$mod+L` lock,
  `$mod+Backspace` power menu, `$mod+Shift+I` region screenshot,
  `$mod+Shift+D` Do Not Disturb, `$mod+Shift+N` night light. `$mod` is the Super key.
- **Night light** (blue-light filter, `w-nightlight`): off / on a schedule / always,
  with a night temperature and a night window. Off by default. Details: the
  **w-displays** skill.
- **Session memory** (`w-session`): remembers which windows were open, on which
  workspace, and how the workspace was split between them, and reopens them at the
  next login — including the programs running inside terminals. Off by default;
  `w-session status` says whether it is on and what is stored. The same machinery
  also keeps **named layouts** the user saves on purpose (`Super+O`, or
  `w-session layout`), which work whether or not the automatic memory is on.
  Details: the **w-session** skill.
- The Quickshell bar has data-driven blocks (workspaces, clock, volume, battery,
  network, updates, notifications/DND, system monitors, tray); its live config is
  `~/.config/quickshell/w/config/bar.json`. Which of them are shown is chosen **per
  monitor** — `w-bar` (GUI: Hub → Appearance → Bar). Details: the **w-desktop** skill.
- `w-notify` — notifications: Do Not Disturb, the history of what arrived, per-app
  mute, popup timeouts (`w-notify status`). Also the way to send one:
  `w-notify send -u critical "…" "…"`. Details: the **w-notifications** skill.
- `w-pointer` — mouse and touchpad: speed, acceleration, natural scrolling, and (on a
  laptop) tap-to-click, click method, disable-while-typing, drag modes, the
  workspace-swipe gesture, and cursor idle-hide timeouts (`cursor.system_timeout` /
  `cursor.menu_timeout` — the latter hides the pointer while a modal Quickshell popup
  is open, and stops it highlighting menu entries for as long as it is hidden)
  (`w-pointer status`, `w-pointer keys`). `w-keyboard` covers
  layouts plus key auto-repeat and NumLock. Details: the **w-input** skill.
- `w-fingerprint` — enrol, list and delete the ten fingerprint slots on a machine with a
  reader (GUI: Hub → Input → Fingerprint). It is the only interface to fprintd; never
  call `fprintd-enroll` directly. Details: the **w-security** skill.

## Diagnostics quick start

- Failed services: `systemctl --failed` (system) and `systemctl --user --failed`.
- Session/app logs: `journalctl --user -b` (persistent journald is enabled).
- For a full post-boot diagnostic bundle, W ships `collect-logs.sh` in its source
  tree (dev/diagnostic use).
