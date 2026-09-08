---
title: Security
section: guide
order: 3
summary: What W enables out of the box — hardening, sudo-rs, firewall, encrypted DNS, keyring, firmware updates, fingerprint and Secure Boot controls.
sources:
  - path: .claude/library/security.md
    sha256: f406324ae9e0c67ff4c0e72a0439ad46f79368a92ae7ad58b928e69db0f3f486
---

W enables a set of protections on every installation and gives you switches
for the parts worth adjusting. The graphical controls concentrate in
**Hub → System → Security**.

## What is on by default

- **Kernel hardening** — a curated sysctl and command-line tightening of the
  default kernel (`w-kernel harden status`). It is a toggle, not a fork: the
  everyday kernel is the responsive one.
- **sudo-rs** as the privilege tool with the familiar `sudo` coexisting —
  escalation prompts behave the same as any Arch system.
- **Encrypted DNS** — systemd-resolved resolving over TLS to a privacy-respecting
  provider (Quad9 by default). `w-dns` changes the provider or the mode.
- **Firewall** — firewalld with an `nftables` backend and a permissive default
  zone appropriate for home networks. `w-firewall public|home` moves the
  machine between zones; **Hub → Network** has the same dropdowns.
- **Keyring** — gnome-keyring stores the user's secrets (WiFi, saved
  passwords); the SSH agent side is a neutral slot (`w-ssh`) that works with
  any backend.
- **Firmware updates** — `fwupd` and its timer; `fwupdmgr refresh && fwupdmgr
  update` applies them.
- **Flatpak sandboxing** — Flatpak with Flathub, the Bazaar store and Flatseal
  for per-app permissions when they are installed.

## Fingerprint login

If the machine has a fingerprint reader, `w-fingerprint` records your fingers
and the login screen, the lock screen and privilege prompts will accept them.
**Hub → Input → Fingerprint** does the same thing graphically.

## Secure Boot

On encrypted installs W ships a two-phase Secure Boot setup: enroll the keys,
reboot once, turn Secure Boot on in the firmware. **Hub → System → Security**
walks through it (`w-secureboot` from a terminal). The installer does not turn
it on automatically on purpose — the firmware requires steps outside the OS.

## Kernel controls

`w-kernel` changes the active kernel (default, LTS, vanilla) and carries the
hardening profile. Both live in the Hub; kernel switching suggests the
graceful reboot when the running kernel changed.

## What is (not yet) protected

USB quarantine (USBGuard) is designed but optional and not yet shipped —
plugging in a foreign USB device is currently trusted like any other storage.
Snapshots are the answer to a bad update; they are not a backup — if the drive
is lost or the disk dies, there is nothing to roll back to. Back up whatever
you cannot reproduce.
