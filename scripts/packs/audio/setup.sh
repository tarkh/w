#!/usr/bin/env bash
# audio bundle — MACHINE layer. Run by `w-pack install` AFTER packages and config,
# always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Nothing to configure on the machine: the JACK swap is pre.sh, the `realtime`
# group and its limits come with realtime-privileges, Ardour's seeds and the
# window rule are manifest rows, the themes are w-style axes, the MCP surface is
# an mcp.d drop-in, group membership is per account (setup-user.sh). What
# remains is the offline verification.
#
# Idempotent; best-effort. See packs.md / pack-audio.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

info "Verifying the audio bundle (offline)..."
pacman -Q pipewire-jack >/dev/null 2>&1 && info "JACK API from PipeWire: OK" \
  || warn "pipewire-jack missing — Ardour's JACK backend has no server (re-run: w-pack install audio)"
command -v ardour9 >/dev/null && info "ardour: OK" || warn "ardour: not found"
getent group realtime >/dev/null && info "group 'realtime': OK" \
  || warn "group 'realtime' missing — realtime-privileges did not install?"
info "audio machine setup complete."
exit 0
