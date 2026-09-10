#!/usr/bin/env bash
# flatpak bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup flatpak` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# setup-user.sh put two things in this home; only one of them is this bundle's:
#
#   * the Papirus icon mirror in ~/.local/share/icons — created solely because
#     /usr/share/icons is blacklisted inside the sandbox and Flathub ships no
#     Papirus extension. Nothing outside the sandbox reads it, so it goes. It is a
#     reflink copy, so it never cost the disk space its size suggests, and the
#     host's own icons are untouched under /usr/share/icons.
#   * the sandbox's Gtk3theme extensions — those are built by W's CORE `gtk` axis
#     (sync_flatpak_gtk3), not by this bundle. The axis is presence-guarded and
#     becomes a no-op once flatpak is gone; removing its output from here would be
#     one bundle deleting another subsystem's artefacts.
#
# Idempotent; best-effort. See pack-flatpak.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

icondir="$USER_HOME/.local/share/icons"
for d in Papirus Papirus-Dark; do
  [[ -d "$icondir/$d" ]] || continue
  info "Removing the sandbox icon mirror ~/.local/share/icons/$d..."
  rm -rf "${icondir:?}/$d"
done

info "flatpak user teardown complete for $USER_NAME."
exit 0
