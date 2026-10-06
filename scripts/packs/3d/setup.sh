#!/usr/bin/env bash
# 3d bundle — MACHINE layer. Run by `w-pack install` AFTER packages and config,
# always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Nothing to configure on the machine: the env.d drop-in and the Blender
# startup module are manifest rows, the theme is a w-style axis, the AI bridge
# is per account (setup-user.sh). What remains is the offline verification.
#
# Idempotent; best-effort. See packs.md / pack-3d.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

info "Verifying the 3d bundle (offline)..."
command -v blender >/dev/null && info "blender: OK" || warn "blender: not found"
[[ -f /usr/share/w/blender/scripts/startup/w_integration.py ]] && info "Blender W startup module: OK" \
  || warn "Blender W startup module missing — no W theme, no AI bridge add-on"
info "Blender picks up the W integration from the next login (session env: /etc/w/env.d/3d.sh)."
info "3d machine setup complete."
exit 0
