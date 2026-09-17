---
name: virt
description: >-
  Operating desktop virtual machines on W Linux with the `virt` W-Pack: libvirt
  + QEMU/KVM, virt-manager and GNOME Boxes. Load this when the user works with
  VMs — list, start, create, shut down, snapshots, networks, pools, ISOs,
  troubleshooting — and `w-pack status virt` reports installed. The `libvirt`
  group gives passwordless manage; nothing here needs sudo after install.
---

# W-Pack: virt

Operating desktop virtual machines on W Linux. This bundle installs **libvirt**
(manager) + **QEMU/KVM** (hypervisor, desktop meta), **virt-manager** (power-user
GUI) and **GNOME Boxes** (express VM creation). Curated into
`/usr/share/w/ai/skills/virt/` when the bundle is installed. Present only if
`w-pack status virt` reports installed.

## What the user has

- **Manager:** libvirt, system daemon (`qemu:///system`), socket-activated —
  starts on first connect. `LIBVIRT_DEFAULT_URI=qemu:///system` is set in the
  session (via `/etc/w/env.d/virt.sh`), so `virsh` with no URI talks to the
  system daemon, not the per-user session.
- **Access:** the account is in the `libvirt` group → libvirt's shipped polkit
  rule (`50-libvirt.rules`) grants passwordless `org.libvirt.unix.manage`. No
  sudo, no password prompt on connect. Membership applies at login; if a connect
  still prompts, the group was added after the current login — log out and back
  in, or `newgrp libvirt` for the current shell.
- **GUIs:** virt-manager (full management: create/edit, consoles, networks,
  pools, snapshots) and GNOME Boxes (one-click from ISO, simpler).
- **Network:** the default NAT network `default` (bridge `virbr0`, dnsmasq DHCP
  + DNS for guests) autostarts with the daemon. Guests get `192.168.122.x` and
  outbound NAT.
- **Storage:** default image pool at `/var/lib/libvirt/images` (root-owned,
  under the `@` subvolume — plain directory, no snapshot exclusion by design).
- **UEFI:** edk2-ovmf is pulled transitively by `qemu-desktop` — UEFI firmware
  is available for guests that need it.

## You are the AI layer of this bundle

Everything here is the **system** libvirt daemon and the **`libvirt` group** —
no per-user socket, no rootless engine. You run `virsh` and the GUIs as the
user; the group membership makes manage passwordless. For anything the user
cannot do (the rare root-level pool/network change), `w_run` (Tier-2, off) or
`sudo virsh` is the path — but routine VM work needs neither.

## Status and inspection

```sh
virsh list --all                    # all domains (running + off)
virsh net-list --all                # networks (default should be active/autostart)
virsh pool-list --all               # storage pools
virsh domstate <name>               # one domain's state
virsh net-info default              # the NAT network
virsh pool-info default             # the image pool
w-pack status virt                  # the W-Pack layer (machine + user)
```

virt-manager and Boxes show the same state graphically. If `virsh` says
`failed to connect to qemu:///system`: the daemon socket is not enabled
(`systemctl status libvirtd.socket`) or the account is not in the `libvirt`
group yet this session.

## Find → install → create a VM

```sh
# 1. ISO: place it anywhere readable (~/Downloads is fine).
# 2. Create a VM (virt-install) — e.g. a 4G/2vcpu Linux from an ISO:
virt-install --name myvm --memory 4096 --vcpus 2 \
  --disk size=20,bus=virtio --cdrom ~/Downloads/linux.iso \
  --os-variant generic --graphics spice

# Or one-click from ISO in GNOME Boxes, or the wizard in virt-manager.
# os-variant: 'osinfo-query os' lists known; 'generic' is a safe fallback.
```

A created VM is a persistent domain — it survives reboot, starts on `virsh
start`, shuts down on `virsh shutdown`. Autostart at boot: `virsh autostart
<name>`. The disk lands in the default pool (`/var/lib/libvirt/images/<name>.qcow2`).

## Snapshots

```sh
virsh snapshot-create-as <name> snap1          # live snapshot
virsh snapshot-list <name>
virsh snapshot-revert <name> snap1
virsh snapshot-delete <name> snap1
```

Snapshots are stored in the domain's qcow2 (internal) unless you pass
`--disk-only`/`--memprof`/external paths. They are VM data, not W wiring —
unaffected by `w-pack remove`.

## Networks (the default is NAT)

The `default` network is a NAT bridge (`virbr0`) with dnsmasq. Guests resolve
via dnsmasq on the bridge IP `192.168.122.1` — **this does not conflict with
systemd-resolved**: resolved keeps the stub on `127.0.0.53` with DoT/Quad9,
dnsmasq binds the bridge IP only, not `0.0.0.0:53`. Do not "fix" DNS by
changing resolved here; there is nothing to fix.

For a bridged (physical) network, define one in virt-manager or
`virsh net-define`, but that puts the guest on the LAN directly and is the
user's networking decision, not the default.

## Gotchas

- **No `swtpm` in this bundle.** A TPM 2.0 (Windows 11, encrypted-disk guests)
  needs the emulated TPM, and this product bundle does not include `swtpm` by
  design — it is the `w-dev` bundle's dev-VM dependency. If a guest needs it:
  `sudo pacman -S swtpm`, then `virt-install … --tpm vsock,model=tpm-crb`.
- **Group applies at login.** `w-pack setup virt` added the group; a connect
  that still prompts for a password is a stale session — log out and back in, or
  `newgrp libvirt`.
- **Default network not active after install?** The autostart symlink is set at
  install; if `virsh net-list --all` shows `default` inactive, start it once:
  `sudo virsh net-start default` (or reboot — the daemon socket brings it up).
- **Image pool is in root snapshots.** `/var/lib/libvirt/images` is a plain
  directory under `@` (not a subvolume). Root snapshots are snap-pac only
  (~10 pacman transactions). This is deliberate — a nested subvolume under `@`
  breaks root rollback. Don't try to "exclude" it.
- **Don't use `qemu:///session`.** The session daemon is a separate libvirt
  with no default network and no group access. `LIBVIRT_DEFAULT_URI` is set to
  `qemu:///system` for a reason; if `virsh` ever targets the session, re-check
  the env drop-in (`/etc/w/env.d/virt.sh`).

## Reset / remove

- **Reset configs to default:** `w-reset virt` (re-deploys the env.d drop-in
  from the manifest).
- **Remove the bundle:** `w-pack remove virt` (machine teardown: disables
  socket, removes autostart symlink, keeps all VM data + definitions).
  `--packages` also runs `pacman -Rns` on the bundle's packages. VM disk images
  and definitions are never deleted — they are printed with their size, and
  the user decides.
- **Per-user (your account only, no root):** `w-pack unsetup virt` removes the
  account from the `libvirt` group.
