#!/usr/bin/env bash
# containers bundle — MACHINE layer. Run by `w-pack install` AFTER packages, config
# (manifest) and the w-style axis are in place, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Deliberately almost empty, and that is the point: rootless containers are a
# per-account thing end to end — the engine, the API socket, the image store and
# the UID mapping all belong to one user. All of that now lives in setup-user.sh
# so any account can set itself up (`w-pack setup containers`), instead of the
# machine claiming the bundle on behalf of whoever ran the install.
#
# What genuinely is machine-wide: the packages (pkgs.txt), /etc/containers and
# /etc/w/env.d (manifest), and the kernel policy checked below.
#
# Idempotent; best-effort. See pack-containers.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── userns sysctl sanity (W does not disable it; harden.sh keeps it on) ──────
# One kernel knob for the whole machine: with it at 0 no account can run rootless
# containers, however well their own layer is set up.
maxns="$(sysctl -n user.max_user_namespaces 2>/dev/null || echo '')"
if [[ -n "$maxns" && "$maxns" == 0 ]]; then
  warn "user.max_user_namespaces=0 — rootless containers need it >0 (check harden.sh)"
fi

info "containers machine setup complete."
exit 0
