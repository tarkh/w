#!/usr/bin/env bash
# w-dev bundle — MACHINE layer setup. Run by `w-pack install` as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# One step, and it closes the fourth silent skip. Three of check.sh's degradations
# are packages (pkgs.txt handles those); the fourth is data. The `paths` suite
# probes every shipped /usr/bin name against `pacman -F` to catch an upstream
# package quietly claiming one of W's command names — a collision that would put
# two files in the same namespace and let the wrong one win. That probe needs the
# pacman FILES database, which a normal `pacman -Sy` does not fetch, so on a stock
# machine it prints "no pacman files database" and steps aside.
#
# Fetched here rather than left to the developer because a one-line hint in a
# green run is not a mechanism. It is pacman's own data (~100 MiB under
# /var/lib/pacman/sync), shared with the "command not found" handler and with
# anyone else running `pacman -F`; the bundle populates it and does not own it.
#
# It does go stale: refresh with `sudo pacman -Fy` alongside a system update. Not
# wired to a timer on purpose — a maintainer bundle should not install background
# work on a machine to keep one probe sharp.
#
# See pack-w-dev.md.
set -uo pipefail   # NOT -e: a failed refresh is a degraded check, not a failed install

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

info "Syncing the pacman files database (check.sh's paths suite reads it)..."
if pacman -Fy; then
  info "Files database ready."
else
  warn "pacman -Fy failed — the paths suite will skip its collision probe."
  warn "Retry later with: sudo pacman -Fy"
fi

info "w-dev machine setup complete."
exit 0
