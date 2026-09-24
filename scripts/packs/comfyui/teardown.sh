#!/usr/bin/env bash
# comfyui bundle — MACHINE teardown. Run by `w-pack remove` as root, AFTER all
# per-account layers are gone, and STILL BEFORE the shipped config is removed —
# so the unit, drop-in dir and sysusers fragment exist while this runs, and the
# service can be cleanly stopped. Env:
#   BUNDLE_NAME BUNDLE_DIR PACK_PACKAGES(0|1)
#
# Removes only what setup.sh imperatively created that a manifest cannot own: the
# rendered drop-in, the engine's service state, and the comfy-cli toolchain from
# the service account. The shipped unit/sysusers fragment are manifest rows and
# w-pack removes them itself. The DATA — ROOT app tree and the shared model store
# DIR — is deliberately preserved and merely reported, exactly like ai-extra's
# model store: it is user content, not something remove should one-line into the
# void (rollback story: remove + fresh install keeps the store; `rm -rf` deletes
# gigabytes irreversibly). See pack-comfyui.md.
#
# Best-effort — a hiccup warns rather than aborting.

set -uo pipefail

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

source /usr/lib/w/w-conf-lib.sh
wconf_load comfyui
wconf_load ai-models
ROOT="$(wconf_get comfyui ROOT /var/lib/w/comfyui)"
DIR="$(wconf_get ai-models DIR /var/lib/w/ai-models)"

# ── 1. Stop and disable the service (unit still present at this point) ─────────
info "Stopping and disabling comfyui.service..."
systemctl disable --now comfyui.service 2>/dev/null \
  || warn "comfyui.service stop/disable failed (unit may already be gone)."

# ── 2. Drop-in we rendered (never touch a 20-local.conf the admin wrote) ───────
DROPIN_DIR="/etc/systemd/system/comfyui.service.d"
DROPIN="$DROPIN_DIR/10-w.conf"
if [[ -f "$DROPIN" ]]; then
  rm -f "$DROPIN"
  rmdir "$DROPIN_DIR" 2>/dev/null || true
  systemctl daemon-reload
  info "Removed rendered drop-in $DROPIN."
fi

# ── 3. Toolchain from the service account's scope ─────────────────────────────
if [[ -x "$ROOT/.local/bin/comfy" ]] || [[ -d "$ROOT/.local/share/uv" ]]; then
  info "Removing comfy-cli from the 'comfyui' account..."
  ( cd "$ROOT" && runuser -u comfyui -- env HOME="$ROOT" PATH="/usr/local/bin:/usr/bin:/bin" \
    uv tool uninstall comfy-cli 2>/dev/null ) \
    || warn "comfy-cli uninstall failed — leftover under $ROOT/.local/bin."
fi

# ── 4. Data is preserved, sizes reported ───────────────────────────────────────
info "Data preserved (remove did NOT delete it):"
for p in "$ROOT" "$DIR"; do
  if [[ -e "$p" ]]; then
    printf '  -- %s: ' "$p"
    du -sh "$p" 2>/dev/null | cut -f1 || echo "?"
  fi
done
info "To delete them yourself (irreversible!):"
info "  rm -rf $ROOT $DIR     # plain dirs"
info "  btrfs subvolume delete $ROOT $DIR   # they are subvolumes on btrfs"