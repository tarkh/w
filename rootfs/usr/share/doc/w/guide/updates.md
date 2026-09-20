---
title: Keeping W up to date
section: guide
order: 1
summary: The single update path, the badge in the bar, Arch news, and what to do when an upgrade goes wrong.
sources:
  - path: .claude/library/w-update.md
    sha256: 004038d61a61d74780748e6bf3ad212974e646e931fa4459b8b076a7ddf5f8dd
  - path: .claude/library/w-mirrors.md
    sha256: 713856f43f54c44fc52642f8968824cdca2f0c967b7bcca2c6943e9a0f6f147c
---

W has one native update path built on `pacman` and `yay`. There are no
third-party update managers. Every upgrade transaction is snapshotted
automatically (snap-pac), so an update is always reversible — see
[the FAQ](faq.md#an-update-broke-my-system-how-do-i-roll-back) and
[RECOVERY.md](../RECOVERY.md).

## The `w-update` command

- `w-update` (or `w-update upgrade`) — interactive full upgrade: repository and
  AUR packages in one pass. It runs without `--noconfirm` on purpose — you
  review the package list and AUR build diffs before anything is applied. When
  the kernel changed it offers a reboot at the end, and that reboot closes your
  windows gracefully first, so unsaved work still asks for confirmation.
- `w-update check` — checks for repository and AUR updates **without root** and
  remembers the result. Never run a bare `pacman -Sy`; W's checker uses a
  private temporary database instead.
- `w-update status` — the last recorded status.
- `w-update news` — the latest [Arch Linux news](https://archlinux.org/news/)
  items. Read this **before a large upgrade**; it surfaces the rare
  manual-intervention announcements.
- `w-update enable` / `disable` / `interval [minutes]` — per-user control of
  the background checker that keeps the badge in the bar current.
- `w-update plan` — a read-only preflight: what a repo upgrade would touch,
  pending AUR builds, whether a kernel change means a reboot, free disk space.

## Where you see updates

- **The bar** shows an updates block with a count once updates are available.
- **The Hub → System** shows the same counter and, after an upgrade that
  requires it, a "reboot pending" hint.
- Clicking the bar block (or the Updates tile in the Hub) opens `w-update` in
  a terminal.

W-specific `/etc` files get their `.pacnew` reconciled automatically by a
pacman hook; third-party `.pacnew` files stay manual, and `w-update` points
them out.

## If an update goes wrong

- A failed download is most often mirror trouble: `w-mirrors status` and
  `w-mirrors sync` re-rank and refresh the mirrorlist; then retry.
- If the system misbehaves after an upgrade, reboot into the pre-upgrade
  snapshot: the boot menu (GRUB or Limine, depending on the install) lists
  snapshots, and [RECOVERY.md](../RECOVERY.md) walks the restore step by step. W
  also ships a copy of that page on disk, so it is readable even when the
  system does not boot.

## The update channel of W itself

`w-update` upgrades *packages*; the distribution's own configuration travels
the `w-sync` channel (edge) — see `w-sync check` and the update chapter of the
FAQ.
