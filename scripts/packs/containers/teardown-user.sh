#!/usr/bin/env bash
# containers bundle — PER-USER teardown, the declared inverse of setup-user.sh.
# Run by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup containers` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# Nearly the whole bundle lives on this side, so nearly the whole teardown does
# too. Three things are deliberately NOT undone:
#
#   * the image store (~/.local/share/containers) — data, often many GB, and a
#     nested btrfs subvolume that rm -rf cannot properly remove. Printed, not
#     touched.
#   * linger — `loginctl enable-linger` is a machine-level property of the
#     account, not of this bundle. Other user services may now depend on it, and
#     turning it off would stop them silently. Named, left alone.
#   * the subuid/subgid range — granted once by useradd or usermod and used by
#     anything rootless, not just podman. Removing it would be W reaching outside
#     its own wiring.
#
# Idempotent; best-effort. See pack-containers.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"
USER_UID="$(id -u "$USER_NAME")"
RUNDIR="/run/user/$USER_UID"
STORE="$USER_HOME/.local/share/containers"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$RUNDIR" "$@"
  else "$@"; fi
}

# ── 1. Podman API socket ─────────────────────────────────────────────────────
# The counterpart of `enable --now`. Failure here is expected on an account with
# no running manager (firstboot, or removing on behalf of someone logged out) —
# the persistent disable is what matters, and it is the same symlink either way.
info "Disabling podman.socket for $USER_NAME..."
if [[ -d "$RUNDIR" ]]; then
  as_user systemctl --user disable --now podman.socket 2>/dev/null \
    || warn "podman.socket disable --now failed (not enabled?)"
else
  as_user systemctl --user disable podman.socket 2>/dev/null \
    || warn "podman.socket disable failed (not enabled?)"
fi

# ── 2. The themed lazydocker config (an axis artefact, not a manifest row) ───
# ~/.config/lazydocker/config.yml is rendered into this home by the bundle's own
# w-style axis, which w-pack has just removed. It is W's artefact, so it goes with
# the axis — otherwise the account keeps a themed config for a tool the bundle no
# longer wires, and no axis left on the machine would ever refresh it.
CFG="$USER_HOME/.config/lazydocker/config.yml"
if [[ -f "$CFG" ]]; then
  info "Removing the axis-rendered $CFG..."
  rm -f "$CFG"
fi

# ── 3. What stays, and why ───────────────────────────────────────────────────
if [[ -e "$STORE" ]]; then
  size="$(du -sh "$STORE" 2>/dev/null | cut -f1 || echo '?')"
  info "Kept: $STORE ($size) — your images and containers, W never deletes them."
  if btrfs subvolume show "$STORE" >/dev/null 2>&1; then
    info "  It is a btrfs subvolume; to reclaim the space:"
    info "      btrfs subvolume delete $STORE"
  fi
fi
if loginctl show-user "$USER_NAME" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
  info "Kept: linger for $USER_NAME — other user services may rely on it."
  info "  Turn it off yourself if nothing else needs it:"
  info "      sudo loginctl disable-linger $USER_NAME"
fi

info "DOCKER_HOST disappears from your session at the next login (/etc/w/env.d)."
info "containers user teardown complete for $USER_NAME."
exit 0
