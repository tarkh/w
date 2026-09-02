---
name: w-security
description: >-
  W Linux security model and tools: kernel/sysctl hardening (w-kernel), privileges
  (sudo-rs, run0), the secrets keyring (gnome-keyring, gcr-ssh-agent, seahorse),
  firmware updates (fwupdmgr), and disk encryption / Secure Boot (w-crypt,
  w-secureboot) on encrypted installs. Load this for hardening, secrets/SSH keys,
  firmware, or LUKS/TPM2/Secure Boot questions.
sources:
  - path: .claude/library/security.md
    sha256: 364888438b946122813a6e365cb060270b25f25b7b0fbc9f8e01e08d86c24b6e
  - path: .claude/library/package-limine.md
    sha256: a54c01ec7b7d2d5195b0ed8beb3adaf0c481154a1d21de8362522954b490097a
tools:
  - w_fwupd_refresh
---

# W Security

W ships a modern, minimal-but-sufficient security baseline. Wayland/Hyprland already
isolate input and screen capture; fingerprint + PAM + the lock screen + polkit handle
authentication; btrfs + Snapper + snap-pac provide rollback; Arch rolling delivers fast
CVE fixes. On top of that:

## Kernel & hardening — `w-kernel`

The default kernel is `linux-zen` (not `linux-hardened`, which would break Flatpak's user
namespaces and DKMS). sysctl and boot-cmdline hardening are applied as a profile.

- `w-kernel` — select the active kernel (`linux-zen` ↔ vanilla `linux`) and toggle the
  hardening profile on/off; it regenerates the bootloader/initramfs as needed.

## Privileges — sudo-rs and run0

- `sudo` on W is **sudo-rs** (memory-safe), used transparently via a shadow symlink; it
  reads the normal `/etc/sudoers`.
- `run0` (from systemd, no extra package) is available as an interactive alternative:
  no setuid, a clean environment, and authorization through polkit → the fingerprint/
  password prompt in a GUI terminal.

## Secrets & SSH keys

Two decoupled layers:

- **Secrets:** `gnome-keyring` provides the Secret Service, auto-unlocked by your login
  password. GUI manager: **seahorse** ("Passwords and Keys").
- **SSH agent:** `gcr-ssh-agent` is W's default SSH agent; it exports `SSH_AUTH_SOCK`
  itself. To store a key passphrase persistently, just `ssh user@server` — on first use
  the agent shows a prompt with an "automatically unlock" checkbox and saves it to the
  keyring. (`ssh-add` does **not** persist to the keyring; `ssh-add -l` is not a reliable
  unlocked-state indicator.)
- **Caveat:** logging in with fingerprint only does **not** auto-unlock the keyring (a PAM
  limitation) — the login password does.

## Firmware — fwupd

Firmware updates use **fwupd** with LVFS; metadata refreshes on a timer. There is no
GNOME Software/Discover — use the CLI:

- `fwupdmgr get-devices`, `fwupdmgr refresh`, `fwupdmgr get-updates`, `fwupdmgr update`.

## Disk encryption & Secure Boot (encrypted installs only)

On an encrypted install, W uses LUKS2 (Argon2id) + TPM2 auto-unlock + a passphrase
fallback, with **Limine** as the bootloader and snapshot-boot support. Two tools manage it
(run with `sudo`):

- `w-crypt status | enroll-tpm | reenroll-tpm | recovery-add | wipe-tpm` — TPM2 auto-unlock
  enrollment and a printable recovery key.
- `w-secureboot status[--porcelain] | enable | disable | setup | sign | reenroll` — Secure
  Boot via sbctl. **`enable`/`disable` are the entry points** (also what the Hub's Security
  tile runs). TPM2 auto-unlock is sealed to PCR7, which measures the Secure Boot policy, so
  toggling SB always breaks it — but PCR7 is only measured by the firmware/bootloader at
  boot time, not live, so `enable` **cannot** enroll the sbctl keys and re-seal TPM2 in one
  shot: doing both in the same session seals against the still-old PCR7 and the disk would
  keep asking for its passphrase forever. `enable` is therefore two calls with a reboot in
  between: the first enrolls the keys and asks for a reboot (no TPM prompt yet); after
  rebooting, run `enable` again to actually re-seal TPM2 (one disk-passphrase prompt), which
  only proceeds if a reboot genuinely happened since enrollment (tracked by boot ID) — this
  protects against silently reproducing the same broken seal. `status --porcelain`'s 4th
  field, `tpm_pending` (`no`/`reboot_needed`/`ready`), tells you which phase you're in; the
  Hub surfaces this as a "Finish enabling" row under the toggle rather than lying that it's
  simply "On". `disable` is a single call: it removes TPM2 first (the passphrase prompt
  returns immediately) *then* resets the sbctl keys back to Setup Mode — no PCR timing
  issue there since nothing needs to match a future boot. `enable`'s first call still
  requires the firmware to already be in Setup Mode (a manual UEFI step); the older
  `setup`/`sign`/`reenroll` remain for manual/advanced use and are what `enable` calls
  under the hood.
- **The installer never turns Secure Boot on, and does not ask about it.** Enrolling keys
  needs the firmware in Setup Mode and switching SB on needs a UEFI toggle plus a reboot —
  none of which an installer can do. A fresh encrypted install therefore boots with SB off
  and asks for the LUKS passphrase every time; both are expected. The order that works is
  Secure Boot first, TPM2 auto-unlock second (that is what `enable` does): sealing TPM2
  while SB is off is close to pointless, because PCR7 then reads the same for any medium
  someone boots, so the TPM would hand the key to a USB stick just as readily.

These tools are only present on encrypted/Limine installs; on a standard install the
bootloader is GRUB and neither applies.

### If the ESP stops receiving kernel updates

Two AUR packages keep the ESP in sync with `/boot`: `limine-mkinitcpio-hook` (the boot
path — it builds each initramfs straight into the ESP and updates the Limine entries) and
`limine-snapper-sync` (snapshot boot entries). A machine installed while their upstream
build was broken (Arch's gradle 9.7.0, 2026-08) can be missing both. Neither absence
announces itself, so recognise the symptoms:

- **A kernel update appears to do nothing** — `uname -r` after a reboot still reports the
  old kernel. `mkinitcpio` rebuilds into `/boot`, but Limine boots from the ESP at
  `/boot/efi`, and the piece that copies one to the other is the missing hook.
- **Snapshot boot entries are not generated** (that is `limine-snapper-sync`).

Confirm rather than guess — `pacman -Q limine-mkinitcpio-hook limine-snapper-sync`, and
compare what Limine actually loads against the installed kernel:

```
grep -E '^\s*(path|module_path): boot\(\):' /boot/efi/limine.conf
cmp /boot/efi/<machine-id>/linux-zen/vmlinuz /boot/vmlinuz-linux-zen
```

**The repair is one command** (privileged, and it rebuilds the packages from source, so it
takes a few minutes and needs network):

```
sudo bash /var/lib/w/src/scripts/apply.sh --limine
```

It reinstalls the pair, restages the ESP, and re-pins the default boot entry. Never
improvise instead of running it: hand-copying files into the ESP leaves the entries'
BLAKE2B hashes stale, which halts Limine outright once Secure Boot is on.

## Rules of engagement

All of the above that changes system state (kernel, firewall, disk, firmware, packages) is
**privileged** and goes through W's polkit + fingerprint/password prompt, which is
audited. Never attempt to bypass that prompt — the OS enforces authorization.

**The prompt names the account it is asking for** ("Password for user `x`"), and on a
**non-administrator's** session — where polkit accepts any of the machine's admins — it
also offers the list, so the administrator who is actually present can authenticate
without switching users. If a user reports that their own password is rejected at that
prompt, the first thing to check is which name it shows: an admin-level action does not
accept a non-admin's password, no matter who is typing.
