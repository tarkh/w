---
name: w-apps
description: >-
  The everyday apps on W and how to open things: file managers (yazi CLI, Nemo
  GUI), media viewers (imv images, mpv video/audio, zathura PDF/EPUB), terminal
  editors (micro default, helix), mounting removable and network drives (USB,
  NTFS/exFAT/APFS, SMB/NFS, phones), and driverless printing + scanning. Load this
  for "what opens X", "mount my drive/NAS", "why won't my printer work", or default-app
  questions.
sources:
  - path: .claude/library/package-files.md
    sha256: 4a7d8310cfc989001c09688193b3f82df60a7931965bdc19a7ec69b60ba208da
  - path: .claude/library/package-printing.md
    sha256: c994a8ed2d35da6357a5251ab80d769c45f3fcd386905b1c2d4fdfe734b1257d
---

# W Apps — files, media, editors, printing

W ships a small set of light, Wayland-native apps and wires them up as the
defaults. Files come from `apply.sh --files`, printing/scanning from
`apply.sh --printing`. All are themed by `w-style` (see the **w-theming** skill).

## Default apps & what opens what

| Kind | App | Notes |
|---|---|---|
| Files (CLI) | **yazi** | terminal file manager, themed (`yazi` w-style axis) |
| Files (GUI) | **Nemo** | GTK3 file manager |
| Images | **imv** | `image/*` |
| Video / audio | **mpv** | `video/*` + `audio/*`; `vo=gpu-next`; audio-only files get a 20-band visualizer |
| PDF / EPUB / CBZ / XPS | **zathura** | dark `recolor` reading by default |
| Text editor (default) | **micro** | the system `EDITOR`/`VISUAL` |
| Text editor (modal) | **helix** (`hx`) | secondary |

Defaults are set through `mimeapps.list` (imv→images, mpv→video+audio,
zathura→documents). To change a default, edit the user `~/.config/mimeapps.list` or
use a file manager's "Open With → set default".

## Mounting drives & network shares

- **Removable USB/SATA disks automount** via udisks2 + udiskie (a tray/agent). Plug
  in and it mounts; eject from the file manager or `udisksctl unmount`.
- **Foreign filesystems** work read-write: NTFS (`ntfs-3g`), exFAT (`exfatprogs`),
  Apple **APFS** (`linux-apfs-rw-dkms`, read-write), HFS+ (in-kernel). ⚠️ The APFS
  driver is DKMS — after a kernel change it rebuilds; a version skew can block the
  mount until the module is rebuilt (see **w-diagnostics**).
- **Network shares** (SMB/NFS/AFP, plus mDNS/DNS-SD discovery) mount through **gvfs**
  — browse them in Nemo, or `gio mount smb://host/share`. A `gvfsd-fuse` bridge
  exposes gvfs mounts to CLI tools under `/run/user/<uid>/gvfs`. Discovery uses
  avahi + nss-mdns (already enabled by the files module).
- **Phones**: iOS (afc) and Android (mtp) appear as gvfs mounts too — browse in Nemo.

## Printing & scanning (driverless)

W is **driverless-first** — IPP Everywhere / AirPrint, no vendor PPD databases.
Most network and modern USB printers just appear.

| Package | Role |
|---|---|
| `cups` | print server: CLI `lp`/`lpr`/`lpadmin`/`lpstat` + web UI at `localhost:631` |
| `cups-pk-helper` | polkit admin (add/manage printers without sudoers) |
| `cups-filters` + `ghostscript` | rasterize PDF for printers without native PDF |
| `ipp-usb` | driverless **USB** bridge: a USB-AirPrint device → local IPP (print + eSCL scan over USB) |
| `system-config-printer` | GTK printer-setup GUI (auto-themed) |
| `sane` + `sane-airscan` | driverless scanning (eSCL/WSD, network + ipp-usb) |
| `simple-scan` | GTK scanning GUI |

- **Add a printer:** it should auto-discover — open **system-config-printer** or the
  web UI `http://localhost:631`. Admin actions prompt via polkit (fingerprint/
  password), no terminal sudo needed. `lpstat -p` lists configured printers.
- **Scan:** open **simple-scan** (or `scanimage -L` to list devices). No scan daemon
  runs — airscan/simple-scan are client-side.
- Zero-config: no skel config is shipped. `cups.socket` and `ipp-usb.service` are
  enabled (socket / udev self-activated); the firewall `home` zone already passes
  mDNS + outgoing IPP.
- **Security note:** `cups-browsed` is intentionally **masked** (RCE
  CVE-2024-47176); W does not rely on it.

## Rules of engagement

- Opening files, listing printers, mounting a user's own removable drive are all
  read/safe — no confirmation needed.
- Installing extra apps or new packages is privileged and goes through W's prompt;
  prefer these first-party defaults over adding new tools (W's zero-bloat ethos).
