---
title: Security
section: guide
order: 3
summary: What W enables out of the box — hardening, sudo-rs, firewall, encrypted DNS, keyring, firmware updates, fingerprint and Secure Boot controls.
sources:
  - path: .claude/library/security.md
    sha256: 3ec7c64f94e8053341ba52ded39be6b779d58ea1284c8db81f32c45f0697e12c
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

## Sandboxed applications (optional)

Third-party GUI applications are best run sandboxed, and W keeps the slots that
takes ready — the desktop portals and the kernel's unprivileged user namespaces
are enabled out of the box. The channel itself is opt-in: `sudo w-pack install
flatpak` adds Flatpak with the Flathub remote, the **Bazaar** store, **Flatseal**
for per-app permissions, and W's theme inside the sandbox. Install it if you
want that ecosystem; a machine that takes its software from the repositories
does not need it.

## Fingerprint login

If the machine has a fingerprint reader, `w-fingerprint` records your fingers
and the login screen, the lock screen and privilege prompts will accept them.
**Hub → Input → Fingerprint** does the same thing graphically.

The same panel decides how the reader behaves under the lock screen. By
default it stays lit for the whole lock and hyprlock verifies the finger
itself. Some readers overheat under that and stop answering after a few
minutes; for them choose **Sensor → On activity** (`w-fingerprint lock-sensor
mode wake`): the sensor lights up for a short window after locking, waking the
machine or any activity while locked, then sleeps. The window is adjustable
(10–300 s); the change applies from the next lock.

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
