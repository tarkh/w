---
title: W Linux documentation
section: start
order: 1
summary: Where to find what — guides, FAQ, command reference and recovery.
---

**W Linux** is an Arch Linux–based distribution: a Hyprland/Quickshell desktop,
a first set of `w-*` tools that drive the system, and automatic snapshots that
make everyday operations reversible. This documentation is viewed in the
desktop itself (the **?** button in Hub panels, or <kbd>Super+F1</kbd>) and
published with the repository.

## Getting around

- **The Hub** (<kbd>Super+Space</kbd>) is the graphical control center: it is
  where settings live and where the Hotkeys panel lists every key binding.
- **<kbd>Super+F1</kbd>** opens this documentation at any time.
- `w-info` lists every `w-*` command with a one-line description in a terminal.
- [RECOVERY.md](RECOVERY.md) is the page for "the system does not boot" — it
  ships as a separate, standalone copy at the same location on every W machine.

## Guides

- [Keeping W up to date](guide/updates.md) — updates, the badge in the bar, and
  what to do when an upgrade goes wrong.
- [Themes and wallpapers](guide/theming.md) — switching and creating themes,
  wallpapers, and the Appearance panel.
- [Security](guide/security.md) — what W enables out of the box and which
  controls you get in the Hub.
- [The desktop](guide/desktop.md) — windows, workspaces, popups, notifications
  and session restore.
- [Displays and night light](guide/displays.md) — monitor layout, scaling, the
  login screen's own layout, and the blue-light filter.
- [Keyboard, mouse and touchpad](guide/input.md) — layouts and the switch key,
  pointer behaviour, gestures, the fingerprint reader.
- [Network, DNS and the firewall](guide/network.md) — connecting, encrypted DNS,
  and the zone to use on an untrusted network.
- [Power and battery](guide/power.md) — profiles, the idle chain of lock,
  screen-off and suspend, lid actions, charge limit.
- [The AI assistant](guide/ai.md) — profiles, models and keys, how much it may
  do on its own.
- [Packs](guide/packs.md) — the optional software bundles and how to add one.
- [FAQ](faq.md) — short answers to common questions.

## Command reference

Every user-facing `w-*` command has a page under [reference/](reference/),
generated from the command's own help text. The same list is available on any
W machine with `w-info`.

<!-- W-DOCS:reference-toc START (generated — do not edit here) -->
- [`w-ai`](reference/w-ai.md) — Launch and manage the W AI assistant — hosts, keys, memory, ask.
- [`w-appearance`](reference/w-appearance.md) — Per-user overrides that beat the active theme (W Hub -> Appearance -> Settings).
- [`w-bar`](reference/w-bar.md) — Choose which status-bar blocks show on which monitor (W Hub -> Appearance -> Bar).
- [`w-conf`](reference/w-conf.md) — Read and write W's layered configuration (vendor → admin → user).
- [`w-crypt`](reference/w-crypt.md) — Manage disk-encryption factors — TPM2 auto-unlock and recovery keys.
- [`w-dns`](reference/w-dns.md) — Switch DNS provider and DNS-over-TLS mode (systemd-resolved).
- [`w-fingerprint`](reference/w-fingerprint.md) — Enrol, list and delete the fingerprints of the current user.
- [`w-firewall`](reference/w-firewall.md) — Toggle the firewall zone between home and public (firewalld).
- [`w-hotkeys`](reference/w-hotkeys.md) — Manage Hyprland keybindings — profiles, catalog, custom binds.
- [`w-info`](reference/w-info.md) — List all W tools with a one-line description of each.
- [`w-kbdlight`](reference/w-kbdlight.md) — Keyboard backlight — level, media keys, and light at the LUKS prompt.
- [`w-kernel`](reference/w-kernel.md) — Select the active kernel and toggle the hardening profile.
- [`w-keyboard`](reference/w-keyboard.md) — Manage the keyboard-layout ring of the Wayland session (XKB).
- [`w-langpack`](reference/w-langpack.md) — Show and deliver what a locale needs beyond LANG (translations, dictionary, font).
- [`w-locale`](reference/w-locale.md) — Show and switch the system UI language (LANG).
- [`w-logs`](reference/w-logs.md) — Set how long W keeps logs (journal + /var/log + W's own logs), one policy.
- [`w-mirrors`](reference/w-mirrors.md) — Keep the pacman mirrorlist fresh — rank mirrors on a schedule or on demand.
- [`w-monitor`](reference/w-monitor.md) — Configure monitors (resolution, scale, rotation, layout).
- [`w-nightlight`](reference/w-nightlight.md) — Night light — warm the screen on a schedule to cut blue light in the evening.
- [`w-notify`](reference/w-notify.md) — Control desktop notifications — Do Not Disturb, history, per-app mute.
- [`w-pack`](reference/w-pack.md) — Install and inspect optional W software bundles (packs).
- [`w-pointer`](reference/w-pointer.md) — Manage mouse, touchpad and swipe-gesture settings of the Wayland session.
- [`w-power`](reference/w-power.md) — Power profiles, idle policy (lock/display/suspend), lid/power key, charge limit.
- [`w-reset`](reference/w-reset.md) — Force-restore any W module's or bundle's config to its default.
- [`w-rollback`](reference/w-rollback.md) — Roll the system back to a btrfs snapshot, on either boot path.
- [`w-screenshot`](reference/w-screenshot.md) — Capture the screen — region/window/output, annotate/copy/save.
- [`w-secureboot`](reference/w-secureboot.md) — Set up and manage Secure Boot (sbctl keys + Limine hash).
- [`w-session`](reference/w-session.md) — Remember and restore the graphical session (windows, workspaces, split layout).
- [`w-ssh`](reference/w-ssh.md) — Choose the session's SSH agent and generate per-host key selectors from it.
- [`w-style`](reference/w-style.md) — Render the active theme across all themed subsystems.
- [`w-sync`](reference/w-sync.md) — Track the W dev repo (edge channel) and apply updates, keeping user config intact.
- [`w-term`](reference/w-term.md) — Launch or query the configured terminal (single entry point).
- [`w-theme`](reference/w-theme.md) — Switch, add and manage W themes with seamless crossfade.
- [`w-time`](reference/w-time.md) — Set the timezone, the system clock and NTP (systemd-timesyncd).
- [`w-update`](reference/w-update.md) — Update all system and AUR packages (repo + AUR in one pass).
- [`w-userdirs`](reference/w-userdirs.md) — Standard home folders (Documents, Pictures, ...) that follow the language.
- [`w-wallpaper`](reference/w-wallpaper.md) — Select the wallpaper for the current resolution tier.
<!-- W-DOCS:reference-toc END -->
