#!/usr/bin/env bash
# invokeai bundle — MACHINE teardown. Run by `w-pack remove` as root, AFTER all
# per-account layers are gone and BEFORE the shipped config is removed (the unit
# still exists, so the service stops cleanly). Env:
#   BUNDLE_NAME BUNDLE_DIR PACK_PACKAGES(0|1)
#
# Removes only what setup.sh created that a manifest cannot own: the rendered
# drop-in. The DATA — the engine tree (venv, gallery, model registry) and the
# shared model store, including InvokeAI's own $DIR/invokeai downloads — is
# preserved and reported, exactly like the comfyui pack. See pack-invokeai.md.
#
# Best-effort — a hiccup warns rather than aborting.

set -uo pipefail

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

source /usr/lib/w/w-conf-lib.sh
wconf_load invokeai
wconf_load ai-models
ROOT="$(wconf_get invokeai ROOT /var/lib/w/invokeai)"
DIR="$(wconf_get ai-models DIR /var/lib/w/ai-models)"

info "Stopping and disabling invokeai.service..."
systemctl disable --now invokeai.service 2>/dev/null \
  || warn "invokeai.service stop/disable failed (unit may already be gone)."

# The drop-in we rendered — never a 20-local.conf the admin wrote.
DROPIN_DIR="/etc/systemd/system/invokeai.service.d"
if [[ -f "$DROPIN_DIR/10-w.conf" ]]; then
  rm -f "$DROPIN_DIR/10-w.conf"
  rmdir "$DROPIN_DIR" 2>/dev/null || true
  systemctl daemon-reload
  info "Removed rendered drop-in $DROPIN_DIR/10-w.conf."
fi

info "Data preserved (remove did NOT delete it):"
for p in "$ROOT" "$DIR/invokeai"; do
  [[ -e "$p" ]] && printf '  -- %s: %s\n' "$p" "$(du -sh "$p" 2>/dev/null | cut -f1)"
done
info "The shared store $DIR stays for every other engine. To delete InvokeAI's own data (irreversible!):"
info "  rm -rf $ROOT $DIR/invokeai               # plain dirs"
info "  btrfs subvolume delete $ROOT             # if it is a subvolume"
