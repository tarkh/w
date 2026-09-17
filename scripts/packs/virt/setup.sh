#!/usr/bin/env bash
# virt bundle — MACHINE layer. Run by `w-pack install` AFTER packages and config
# (manifest) are in place, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Desktop virtualization machine setup: enable the libvirt system daemon socket
# (on-demand, not a running service) and mark the default NAT network for autostart
# so a `virsh net-start default` is not needed on a fresh boot. Both are
# idempotent and offline-safe — no daemon is started and no network is brought up
# here, which matters for firstboot (no session, no bridge, no dnsmasq yet).
#
# The DIRECTORY /var/lib/libvirt/images is created by libvirt's tmpfiles on
# package install — but that is not the same thing as a libvirt storage POOL:
# unlike the default network (shipped as XML by the package, see §2 below),
# libvirt ships no default pool definition at all. Without one, virt-install
# and a first-run virt-manager/Boxes have nowhere to put a disk. §2a below
# defines it offline, the same way §2 handles the network. It lives under the
# root subvolume `@` and is deliberately NOT excluded as a nested btrfs
# subvolume — see meta.conf / pack-virt.md for the rollback reason.
#
# Idempotent; best-effort. See packs.md / pack-virt.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. libvirt system daemon socket (on-demand) ──────────────────────────────
# libvirtd is socket-activated: a `virsh` / virt-manager / Boxes connect starts
# it on demand. `enable` makes the socket available; `--now` would start the
# daemon now, which is unnecessary on-demand and unhelpful at firstboot (no
# session, no console). Enable the socket only — the first connect brings the
# daemon up. libvirtd.socket covers the legacy monolithic path; the modular
# virtqemud.socket is an alternative libvirt ships, but the monolithic socket is
# what the default `qemu:///system` URI and the polkit rule target.
info "Enabling libvirtd.socket (on-demand system daemon)..."
systemctl enable libvirtd.socket >/dev/null 2>&1 \
  || warn "could not enable libvirtd.socket (already enabled?)"

# ── 2. Default NAT network autostart ──────────────────────────────────────────
# libvirt ships /etc/libvirt/qemu/networks/default.xml (NAT bridge virbr0 +
# dnsmasq). It does NOT autostart unless a symlink in networks/autostart/ points
# at it. Create that symlink so a freshly-booted machine brings up virbr0 the
# moment the daemon first starts — without it the user hits "network default is
# not active" on their first VM. Idempotent: ln -sf never fails on an existing
# target. The network itself is NOT started here (no daemon, no bridge, offline).
NET_SRC="/etc/libvirt/qemu/networks/default.xml"
NET_DST="/etc/libvirt/qemu/networks/autostart/default.xml"
if [[ -f "$NET_SRC" ]]; then
  info "Marking default NAT network for autostart..."
  ln -sf ../default.xml "$NET_DST" \
    || warn "could not create autostart symlink for default network"
else
  warn "libvirt default.xml not found at $NET_SRC — default network not autostarted"
  warn "  (expected from the libvirt package; the network will need a manual start)"
fi

# ── 2a. Default storage pool (offline) ────────────────────────────────────────
# libvirt ships no default.xml for a storage pool the way it does for the
# network — a fresh install has the /var/lib/libvirt/images directory (package
# tmpfiles) but no pool object pointing at it. GUI tools paper over this by
# defining one themselves on first connect; virt-install and a headless first
# `virsh` do not get that for free and fail outright. Write the pool config
# directly (no `virsh`, no daemon contact — same offline invariant as §2); the
# uuid is intentionally omitted so libvirtd assigns one on first load.
POOL_DIR="/etc/libvirt/storage"
POOL_AUTOSTART_DIR="$POOL_DIR/autostart"
POOL_SRC="$POOL_DIR/default.xml"
POOL_DST="$POOL_AUTOSTART_DIR/default.xml"
if [[ ! -f "$POOL_SRC" ]]; then
  info "Defining default storage pool (/var/lib/libvirt/images)..."
  mkdir -p "$POOL_DIR" "$POOL_AUTOSTART_DIR"
  cat > "$POOL_SRC" <<'EOF'
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/var/lib/libvirt/images</path>
    <permissions>
      <mode>0755</mode>
      <owner>0</owner>
      <group>0</group>
    </permissions>
  </target>
</pool>
EOF
  chmod 600 "$POOL_SRC"
else
  info "Default storage pool already defined — leaving as-is."
fi
ln -sf ../default.xml "$POOL_DST" \
  || warn "could not create autostart symlink for default storage pool"

# ── 3. Offline verification ──────────────────────────────────────────────────
# Confirm the unit and the default network/pool XML are present on the machine.
# No daemon start, no network start, no network pull — this is the offline
# invariant every bundle checks.
info "Verifying machine setup (offline)..."
ok=1
systemctl status libvirtd.socket >/dev/null 2>&1 || { warn "libvirtd.socket not found"; ok=0; }
[[ -f "$NET_SRC" ]] || { warn "default network XML not found"; ok=0; }
[[ -f "$POOL_SRC" ]] || { warn "default storage pool XML not found"; ok=0; }
# The bridge module: firewalld's libvirt backend needs the kernel bridge filter
# (br_netfilter on some kernels; the `bridge` module on others). W's kernel
# (linux-zen) ships bridge filtering built-in — verify the sysctl only.
if sysctl -n net.bridge.bridge-nf-call-iptables >/dev/null 2>&1; then
  : # bridge filtering present
else
  : # not fatal — libvirt's firewalld backend handles this without the sysctl
fi

if [[ $ok -eq 1 ]]; then
  info "virt machine setup complete (socket + default network/pool autostart)."
  info "  Connect after login: virt-manager / Boxes / virsh (LIBVIRT_DEFAULT_URI"
  info "  = qemu:///system set at next login). The daemon starts on first connect."
else
  warn "virt machine setup completed with warnings — see above."
fi
exit 0
