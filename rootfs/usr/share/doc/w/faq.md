---
title: FAQ
section: start
order: 2
summary: Short answers to common questions.
sources:
  - path: .claude/library/w-rollback.md
    sha256: 1099b89dead5e78070ffcd430de9775eb954a46b6bc7575d934966e991e31948
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

**Why does W ask for the disk passphrase at every boot?**
The disk is encrypted, and until you turn on automatic unlock the passphrase is
its only key. Automatic unlock needs Secure Boot first: **Hub → System →
Security** walks through Secure Boot, then turns on automatic unlock (TPM, or
TPM + PIN on a laptop) — see
[disk encryption and Secure Boot](guide/security.md#disk-encryption-and-secure-boot).

**Can I install W next to Windows?**
Yes — into free space. First, in Windows, shrink the C: volume (Disk Management →
Shrink Volume) to free 40 GiB or more — enter 40960 MB or more in the Shrink
dialog; the installer never resizes NTFS itself. The installer shows sizes in GiB,
the same numbers Windows shows (Windows labels them "GB"), so the room you freed
reads back unchanged. Then pick the disk — the list shows each disk's partitions
and free space — and "Into free space": W creates its own boot
partition (ESP) and root there, and every existing partition — the Windows ESP
included — stays untouched. If BitLocker is on, save its recovery key before you
start. With Secure Boot left on, W installs and boots through Microsoft-signed shim
and Windows notices nothing; only firmware that refuses the W medium ("Secured-core")
needs a Secure Boot setting changed, and then Windows asks for that key once. W becomes the first boot
entry, and its boot menu — otherwise hidden — now shows for 5 seconds with a
Windows entry. Choosing it restarts the computer straight into Windows: W hands
over to the firmware's own Windows entry instead of starting Windows itself, so
BitLocker sees a normal Windows boot and does not ask for the key each time. The
entry follows the firmware: if Windows is removed, the entry and the visible menu
go away with the next kernel update; if the firmware lost the Windows entry (after
a firmware reset), start Windows once from the firmware's boot menu (the key shown
at power-on, often F12, F8 or Esc) — Windows restores it. Windows keeps the hardware clock in local time, so while a Windows
is installed, W keeps it in local time too and the clock stays right when you
switch. Prefer UTC on both sides? In Windows, run as administrator
`reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`
and restart Windows, then in W choose **Hub → System → Date & Time → Hardware clock →
UTC** (or `sudo w-time rtc utc`).

## Updates and recovery

**An update broke my system. How do I roll back?**
Reboot, pick the pre-upgrade snapshot in the boot menu, and follow
[RECOVERY.md](RECOVERY.md) (a copy is on disk). Snapper keeps the last 20
system snapshots, about 10 upgrades — see
[snapshots and disk space](guide/updates.md#snapshots-and-disk-space).

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
through, `w-monitor reset --all` from a text console (Ctrl+Alt+F2) puts sane
defaults back. Details in
[the displays guide](guide/displays.md#a-black-screen-after-a-display-change)
and [RECOVERY.md](RECOVERY.md).

**The fingerprint reader stopped unlocking.**
Re-enroll the finger with `w-fingerprint` (or **Hub → Input → Fingerprint**);
the traditional password always works as the fallback.

**A window I closed keeps coming back after I log in.**
That is session restore, on by default. Turn it off or exclude the app in
**Hub → System → Session**; see [the desktop guide](guide/desktop.md).

**Why does my laptop suspend later than the time I set?**
The three idle timers are a chain, not three stopwatches: the screen goes off so
long *after the lock*, and suspend so long *after the screen goes off*. Each row
in **Hub → Power** shows the resulting absolute time underneath it — see
[the power guide](guide/power.md#idle-lock-then-screen-off-then-suspend).

## Software

**How do I install something not in my list?**
`yay` covers the repositories and the AUR; sandboxed third-party apps come from
Flatpak/Bazaar, which is the optional `flatpak` bundle (`sudo w-pack install
flatpak`). Anything installed this way snapshots like an update does.

**A pack says it is on the machine but not set up for me.**
A pack has a machine half (packages, installed once, needs an administrator) and
a per-account half that is deliberately not done for everybody automatically.
Press **Set up** in **Hub → Packs**, or run `w-pack setup <name>` — no password
needed. See [the packs guide](guide/packs.md#installing-and-setting-up-for-your-account).

**Is the AI assistant required, and does it need a paid account?**
Neither. Nothing in W depends on it, and it does nothing until you give it a
model in **Hub → AI**. That can be a subscription you already have, an API key,
or a model running locally on your own machine — see
[the AI guide](guide/ai.md).

**Where did `~/go` go? Why are `~/.cache/uv` and `~/.cache/go` not plain folders?**
W keeps toolchain caches in XDG places and out of home snapshots. Go's module
and build caches live in `~/.cache/go`, `GOPATH` is `~/.local/share/go`, and
`go install` puts binaries in `~/.local/bin` (on PATH). Such cache folders are
nested btrfs subvolumes, so a rollback of your home never drags gigabytes of
recoverable downloads along. A `~/go` left from before is stale — delete it if
you like. The values come from `/etc/profile.d/w-go.sh` and apply at the next
login; your own shell profile can override them.

**Is AUR safe?**
It is third-party packaging, reviewed by you at the PKGBUILD prompt the same
way any Arch user reviews it. W keeps boot-critical packages out of AUR where
it matters.
