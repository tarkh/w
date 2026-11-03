---
title: Security
section: guide
category: system
order: 3
summary: What W enables out of the box — hardening, sudo-rs, firewall, encrypted DNS, keyring, firmware updates, fingerprint, disk encryption and Secure Boot.
sources:
  - path: .claude/library/security.md
    sha256: 85649ab384308d1c5a2bdf97aebd4dc077ea08025974c54bb7d939a270c2f0a5
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

## Disk encryption and Secure Boot

The installer offers an encrypted disk first, and it is the recommended
choice — especially on a laptop. The whole system partition is encrypted
(LUKS2): a stolen laptop or a removed drive reveals nothing without the
passphrase. Encryption does not protect a running, unlocked system — that is
the job of the screen lock and the other layers on this page.

**Why the passphrase is asked at every boot.** Until you choose otherwise,
the passphrase is the only key. Automatic unlocking is only safe together with
Secure Boot, so the installer turns it on only when Secure Boot is already on in
the firmware, and only on a desktop (see *Installing with Secure Boot on*);
everywhere else it stays your decision, made in the installed system.

**Automatic unlock (Secure Boot + TPM2).** The TPM2 chip can hold the disk key
and release it only to a boot chain it recognises. Without Secure Boot that
check means nothing — the TPM would hand the key to any USB stick someone
boots — so W enables the two in one order: Secure Boot first, then TPM2.

**Secure Boot is switched on in two places.** The switch in the firmware setup
(BIOS) alone does not make W boot: W first has to prepare its own chain — its
key, and a signed boot loader that carries a fingerprint of its menu. The
**Secure Boot** row in **Hub → System → Security** shows where the machine is
and names the next step: prepare W, reboot, turn Secure Boot on in the firmware
(the row can reboot straight into the firmware setup), finish. From a terminal
it is `sudo w-secureboot enable`, run once before and once after the reboot.
The way depends on the firmware:

- **Factory keys (the usual case).** W boots through Microsoft-signed *shim*
  and adds its own key with your confirmation: after the first step, reboot,
  and the blue *Shim UEFI key management* menu opens by itself. Choose
  **Enroll MOK → Continue → Yes**, type the one-time code the terminal printed
  (it is not shown while you type), then **Reboot** — within 5 minutes, or the
  firmware restarts the computer and the request is lost. Never choose
  **Reset MOK**: it erases all enrolled keys. Windows started instead? Pick
  **W** in the firmware's boot menu (F11/F12/Esc) and put it first in the
  firmware's boot order. Afterwards turn Secure Boot on in the firmware if it
  is not on yet, and finish enabling.
  If the firmware does not trust Microsoft's third-party certificate (some
  "Secured-core" laptops), W says so: turn on *Allow Microsoft 3rd-party UEFI
  CA* in the firmware's Secure Boot settings.
- **Firmware in Setup Mode** (you cleared its keys yourself). W enrolls its
  own keys instead; reboot once, then finish.

**Then automatic unlock, separately.** Turning Secure Boot on never adds
automatic unlock by itself — that is the **Automatic unlock (TPM2)** row
below it, locked until Secure Boot is on in W and in the firmware:

- **TPM** — the disk opens without a question while the boot chain is W's.
- **TPM + PIN** — the TPM still checks the boot chain, and asks for a short
  PIN as well. The PIN prompt shows a keypad under the field. Forgot the PIN?
  After three wrong ones the keypad turns into a lock: that prompt takes the
  passphrase or the recovery key. The same lock appears straight away when the
  boot chain changed. The passphrase typed into the keypad prompt counts as a
  wrong PIN.
- **Off** — the passphrase at every boot.

Every choice asks for the current passphrase once, in a terminal. When the
firmware or shim is updated — or Windows on the same computer installs
Microsoft's Secure Boot updates, which it does only while Secure Boot is on —
the TPM no longer recognises the chain: the disk asks for the passphrase once and the row offers **Re-seal**
(`sudo w-crypt reenroll-tpm`). From a terminal: `sudo w-crypt enroll-tpm`
(`--pin` for a PIN), `sudo w-crypt wipe-tpm` to turn it off.

**Turning Secure Boot off** goes the other way round: the firmware first (with
its factory keys W boots only through shim), then **Turn off in W** in the same
row. It removes automatic unlock too — the passphrase is asked again.

**Windows with BitLocker next to W.** The first way does not touch the
firmware's keys, so Windows notices nothing. W's own keys change what
BitLocker measures, and Windows asks for its recovery key once — have it at
hand. Turning Secure Boot off in the firmware does the same.

**The boot menu is sealed.** With Secure Boot on, the boot loader carries a
fingerprint of its menu and refuses to start when the menu changes behind its
back. W refreshes the fingerprint on its own changes and checks it again before
every shutdown, reboot and hibernation, so even a hand edit is picked up. Only a
power cut or a hard reset right after a change can leave it stale — the way
back is in `RECOVERY.md` (*CHECKSUM MISMATCH FOR CONFIG FILE*).

- **Worth it** on a desktop with a TPM2 chip: the disk stays unreadable once
  removed from the machine, and you stop typing the passphrase.
- **TPM + PIN** on a laptop you carry around: with TPM alone a stolen laptop
  starts up to the login screen, and only the account password stands between
  the thief and your files. With a PIN it stops before the disk opens, and the
  TPM locks itself after a few wrong guesses — a short PIN is enough.
- **Stay on the passphrase** when the machine has no TPM2, when you want the
  key to exist only in your head, or when you often change firmware settings.

Keep the passphrase even with automatic unlock: it is asked again whenever the
firmware or Secure Boot changes. The **Recovery key** row (or
`sudo w-crypt recovery-add`) adds a long printable key as a second spare: it is
shown once, in the terminal, and **Replace** swaps it for a new one. It works
wherever the passphrase does — typed into the lock prompt at boot, or to open
the disk from a live USB stick — so it helps when the passphrase is forgotten,
when the TPM no longer recognises the machine, or when the disk moves to another
computer. Store both outside this computer.

### Installing with Secure Boot on

The W install medium starts with Secure Boot left on. It boots through
Microsoft-signed *shim*, and shim trusts W's boot loader by its fingerprint,
which you add once per downloaded image:

1. Boot the medium. Shim does not know this image yet: `Verification failed`
   appears, then a blue *Shim UEFI key management* screen. It waits only 10
   seconds — press any key. Missed it: restart and try again.
2. Choose **Enroll hash from disk**, the medium, then `EFI/BOOT/grubx64.efi`.
   Before **Continue**, compare the hash MokManager shows with the *Secure Boot
   hash* on the download page — that is what your firmware is about to trust.
   Then **Continue → Yes → Reboot**. No password is needed.
3. The medium now starts the installer. A newer image is a different file and
   asks once more; an old fingerprint does no harm.

With Secure Boot on, the whole medium is checked: an altered image stops before
the installer starts. Firmware that trusts Windows only (some "Secured-core"
laptops) refuses the medium outright — `Access Denied` or a Secure Boot violation
screen. Turn on *Allow Microsoft 3rd-party UEFI CA* in its Secure Boot settings, or
switch Secure Boot off for the installation; either way Windows with BitLocker asks
for its recovery key once.

With Secure Boot on, only the encrypted installation is offered, and the installer
sets Secure Boot up for the installed system itself (the shim way above). One step
is left for you, on the first boot after the installation:

1. The last screen of the installer shows a one-time code. Reboot: the blue
   *Shim UEFI key management* menu opens by itself.
2. **Enroll MOK → Continue → Yes**, type the code (it is not shown while you
   type). This adds the installed system's own key; without it W does not
   start with Secure Boot on.
3. **Delete MOK → Continue → Yes**, the same code. This removes the medium's
   fingerprint you added to boot the installer: the installed W no longer needs
   it, and leaving it would keep that public image trusted by your firmware. A
   newer image has a different fingerprint anyway — the medium asks again if
   you boot it later. If **Delete MOK** is not listed, skip this step.
4. **Reboot.**

Finish within 5 minutes — the firmware then restarts the computer and the
request is lost. Never choose **Reset MOK**: it erases all enrolled keys. If
the request was lost, the menu comes back after *Verification failed* with a
10-second countdown — press any key, then **Enroll key from disk → W_EFI (the
system disk) → EFI → W → W-MOK.cer → Continue → Yes → Reboot**, no code needed.
The medium's fingerprint then stays; it does no harm.

Some firmware does not accept the request at all — it refuses new variables
from a running system and takes them only from the blue screen at boot (seen on
older AMI boards, such as the ASUS X99 series). The installer notices and its
last screen shows no code, only these steps: reboot, press any key when the
menu appears after *Verification failed*, then **Enroll key from disk → W_EFI →
EFI → W → W-MOK.cer → Continue → Yes → Reboot**. The medium's fingerprint stays
in that case too — removing it would need the same refused request.

W then finishes the installation with Secure Boot on. On a desktop with a TPM2
chip the disk unlocks by itself from then on; a laptop keeps asking for the
passphrase — **Hub → System → Security → Automatic unlock** adds TPM + PIN (or
TPM) if you want it there.

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
