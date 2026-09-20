#!/usr/bin/env bash
# dev bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup dev` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Everything here reaches exactly one home: the legacy-git advisory, the mise
# storage subvolumes, and the first theme render. The machine half — packages and
# the zed→zeditor symlink — is in setup.sh.
#
# Works in every context: firstboot (root, the account not logged in), a later
# `sudo w-pack install dev`, and a second account catching itself up with no root
# at all. Idempotent; best-effort. See pack-dev.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root over sudo/ssh, or
# a service dir at firstboot) the target user cannot chdir there. Move to a cwd
# they can read.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Legacy git layout (bundles installed before 2026-08-04) ───────────────
# W's git settings used to be seeded INTO ~/.gitconfig; they now live in the
# managed ~/.config/git/config, which git reads first and W may update freely.
# A machine carrying the old copy still works — the values are identical and the
# user's file simply wins — but those stale lines would pin W's settings and
# silently block any future change to them. Point it out; never edit their file.
GITCONFIG="$USER_HOME/.gitconfig"
if [[ -f "$GITCONFIG" ]] && grep -q 'w/git-theme.conf' "$GITCONFIG" 2>/dev/null; then
  warn "$GITCONFIG carries W's OLD git settings (pre-2026-08-04 layout)."
  warn "  They now live in ~/.config/git/config, which W owns and keeps current."
  warn "  Your copy still works but freezes those keys at today's values."
  warn "  To follow W again, delete from $GITCONFIG the [include] of"
  warn "  w/git-theme.conf plus the [core]/[interactive]/[delta] blocks W added."
  warn "  Keep everything you wrote yourself — [user] above all."
fi

# ── 2. mise storage out of @home snapshots ───────────────────────────────────
# mise downloads whole toolchains (node, go, rust, java — easily multiple GiB) into
# ~/.local/share/mise, plus a pure download cache in ~/.cache/mise. Both are large,
# ephemeral and fully recoverable from the network (`mise install` rebuilds them
# from mise.toml) — exactly the profile that should not ride inside @home snapshots.
# Carve them as nested btrfs subvolumes: snapper's snapshots are non-recursive, so a
# nested subvolume is excluded natively. Same pattern as the uv/pip caches
# (defaults/home-subvols → w_home_subvol) and the containers pack's rootless storage.
#
# Per account by nature — every user has their own toolchains, so every user needs
# their own exclusion.
#
# Only acts while the path is ABSENT — a populated directory cannot be converted in
# place — hence doing it here, before mise has ever run. Best-effort: a non-btrfs
# home just gets a plain directory.
own_dir() {   # create <dir> owned by the account, whichever privilege we hold
  if [[ "$AS_ROOT" == 1 ]]; then install -d -o "$USER_NAME" -g "$USER_NAME" "$1"
  else install -d "$1"; fi
}

exclude_from_snapshots() {
  local dir="$1"
  if [[ -e "$dir" ]]; then
    if btrfs subvolume show "$dir" >/dev/null 2>&1; then
      info "$dir already a subvolume — nothing to do."
    else
      warn "$dir already exists as a regular dir — leaving as-is (rides in @home snapshots)."
    fi
    return 0
  fi
  # Subvolume creation is permitted for whoever may write the parent directory, so
  # this works for an account catching itself up, not only for root.
  if as_user btrfs subvolume create "$dir" >/dev/null 2>&1; then
    [[ "$AS_ROOT" == 1 ]] && chown "$USER_NAME:$USER_NAME" "$dir"
    info "Created nested subvolume $dir (excluded from @home snapshots)."
  else
    own_dir "$dir"
    warn "$dir not on btrfs (or subvolume create failed) — plain dir, no snapshot exclusion."
  fi
}

if [[ -d "$USER_HOME" ]]; then
  info "Keeping mise toolchains/cache out of @home snapshots for $USER_NAME..."
  own_dir "$USER_HOME/.cache"; own_dir "$USER_HOME/.local/share"
  exclude_from_snapshots "$USER_HOME/.cache/mise"
  exclude_from_snapshots "$USER_HOME/.local/share/mise"
fi

# ── 3. Theme for this account (skel + system are already done by w-pack) ─────
# w-pack renders the freshly deployed axes as root, which covers /etc/skel and the
# system scope; a user's own copies are normally written at the next login. Render
# them now so the tools are themed on first launch, without a relogin. No-op at
# firstboot if the home does not exist yet.
if [[ -d "$USER_HOME" ]]; then
  for axis in zed git lazygit; do
    info "Rendering the $axis theme for $USER_NAME..."
    as_user w-style apply "$axis" >/dev/null 2>&1 \
      || warn "w-style apply $axis failed for $USER_NAME (renders at next login)"
  done
fi

# ── 4. Offline verification (no network, firstboot-safe) ─────────────────────
info "Verifying the bundle for $USER_NAME (offline)..."
if as_user zeditor --version >/dev/null 2>&1; then
  info "Zed OK: $(as_user zeditor --version 2>/dev/null). Launch: zed (or zeditor)."
else
  warn "zeditor --version did not succeed — check 'w-pack install dev' package step"
fi
for bin in delta lazygit mise; do
  if as_user "$bin" --version >/dev/null 2>&1; then
    info "$bin OK."
  else
    warn "$bin --version did not succeed — check 'w-pack install dev' package step"
  fi
done

# Both activation paths are session/shell scoped, so nothing here is live:
#   lazygit palette + mise shims  → /etc/w/env.d/dev.sh    (next LOGIN)
#   mise per-prompt activation    → /etc/w/zshrc.d/dev.zsh (next NEW SHELL)
info "lazygit colours and mise activate at the next login (/etc/w/env.d, /etc/w/zshrc.d)."

info "dev user setup complete for $USER_NAME."
exit 0
