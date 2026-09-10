#!/usr/bin/env bash
# dev bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run by
# `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup dev` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# setup-user.sh did three things; each has a different correct inverse:
#   1. warned about a legacy ~/.gitconfig — advice leaves no trace, nothing to undo.
#   2. carved ~/.cache/mise and ~/.local/share/mise as snapshot-excluded subvolumes
#      — those hold downloaded toolchains, i.e. DATA. Named and kept.
#   3. rendered the zed/git/lazygit theme files — W's own artefacts, produced by
#      axes w-pack has just removed. They go, or the account keeps themed configs
#      that nothing left on the machine will ever refresh again.
#
# Idempotent; best-effort. See pack-dev.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# ── 1. Axis-rendered theme files ─────────────────────────────────────────────
# Deliberately the same three paths pack-dev's manifest documents as NOT being
# manifest rows, precisely because an axis owns them. The axis is gone; so are they.
for f in ".config/zed/themes/w.json" ".config/w/git-theme.conf" ".config/w/lazygit-theme.yml"; do
  [[ -f "$USER_HOME/$f" ]] || continue
  info "Removing the axis-rendered ~/$f..."
  rm -f "$USER_HOME/$f"
done

# ── 2. What stays, and why ───────────────────────────────────────────────────
for d in ".cache/mise" ".local/share/mise"; do
  p="$USER_HOME/$d"
  [[ -e "$p" ]] || continue
  size="$(du -sh "$p" 2>/dev/null | cut -f1 || echo '?')"
  info "Kept: $p ($size) — your toolchains/cache, W never deletes them."
  if btrfs subvolume show "$p" >/dev/null 2>&1; then
    info "  It is a btrfs subvolume; to reclaim the space:"
    info "      btrfs subvolume delete $p"
  fi
done

info "Zed loses the W theme at its next launch; git and lazygit at the next shell."
info "dev user teardown complete for $USER_NAME."
exit 0
