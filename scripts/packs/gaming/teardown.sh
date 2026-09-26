#!/usr/bin/env bash
# gaming bundle — MACHINE teardown, the declared inverse of setup.sh. Run by
# `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# Closes the firewalld services setup.sh opened. Deliberately does NOT:
#   - disable multilib — other bundles or the user's own lib32 packages may
#     depend on it; a pack that turned the repo back off on remove would break
#     things it never touched. Printed explicitly so the choice reads as one.
#   - unload ntsync — a harmless loaded module, and unloading a kernel module
#     that may be in use elsewhere is not this bundle's call to make.
#   - remove the vendor lib32 packages pre.sh installed — no code needed here
#     for that. pre.sh installs them `--asdeps` specifically so pacman's own
#     `-Rns` on pkgs.txt's list (w-pack's `remove --packages`, which runs
#     right after this script) sweeps the whole vendor lib32 chain up as
#     orphaned in the SAME transaction, once its last consumer (steam) is
#     gone — see pre.sh's own comment for why a separate removal here would
#     have needed to reimplement pkgs.txt's neighbour-subtraction to stay
#     safe, and would fight pacman's dependency resolver either way (removing
#     the vendor chain before steam is gone fails exactly like removing
#     lib32-gnutls before the vendor chain is gone) — verified live.
#
# Idempotent; best-effort. See pack-gaming.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }

if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
  firewall-cmd --permanent --zone=home --remove-service=steam-streaming >/dev/null 2>&1 || true
  firewall-cmd --permanent --zone=home --remove-service=steam-lan-transfer >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  info "Closed Steam's firewalld services in the 'home' zone."
fi

info "multilib repository left enabled — other packages/bundles may depend on"
info "  it. Turn it off yourself in /etc/pacman.conf if nothing else needs it."
info "ntsync kernel module left loaded (harmless; unload yourself if you want:"
info "  sudo modprobe -r ntsync)."

info "gaming machine teardown complete."
exit 0
