#!/usr/bin/env bash
# office bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup office` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Two steps: render the bundle's obsidian axis into THIS account's vaults right
# now, so the pack arrives themed without waiting for the next login (which
# renders all axes anyway — this is the catch-up, and the second-account catch
# -up for a pack installed by someone else), and switch on the vault-registry
# watcher (w-obsidian-vaults.path) so a vault created LATER is themed the
# moment Obsidian registers it — the axis can only reach vaults it can find,
# and on a fresh install the first vault appears well after the last render.
# The axis also enables the snippet by default in fresh vaults (its guarded
# appearance.json write, three-state rule — see pack-office.md). No root-only
# steps, so it works identically under rootless `w-pack setup`.
#
# Idempotent; best-effort. See pack-office.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; move to one the account can read (packs.md).
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Render the obsidian axis for this account ───────────────────────────────
# w-pack already rendered the freshly deployed axes as root (a no-op for this
# axis — vaults are per-account); this pass writes the snippet into the vaults
# of THIS account. Skips itself politely when the account has no vaults yet.
if [[ -d "$USER_HOME" ]] && command -v w-style >/dev/null; then
  info "Rendering the obsidian theme for $USER_NAME's vaults..."
  as_user w-style apply obsidian \
    || warn "w-style apply obsidian failed (renders at next login instead)."
else
  info "w-style not available yet — the obsidian axis renders at next login."
fi

# ── 2. Watch the vault registry for vaults created from now on ─────────────────
# The wants-symlink is written by hand rather than via `systemctl --user enable`
# (idiom of the bitwarden bundle): at firstboot the account has no running user
# manager, and over runuser `systemctl --user` would address ROOT's manager.
# The symlink is exactly what `enable` produces; `--machine=<user>@.host` is
# how root reaches the account's own manager to make it live NOW — a pack
# installed mid-session must catch the vault the user creates a minute later.
# Both are best effort: the next login is correct on the symlink alone.
WANTS_DIR="$USER_HOME/.config/systemd/user/graphical-session.target.wants"
LINK="$WANTS_DIR/w-obsidian-vaults.path"
if install -d -m755 -o "$USER_NAME" -g "$USER_NAME" "$WANTS_DIR" 2>/dev/null \
   || install -d -m755 "$WANTS_DIR" 2>/dev/null; then
  ln -sfn /etc/systemd/user/w-obsidian-vaults.path "$LINK"
  [[ "$AS_ROOT" == 1 ]] && chown -h "$USER_NAME:$USER_NAME" "$LINK" 2>/dev/null
  info "New Obsidian vaults will be themed as they are created (registry watcher)."
else
  warn "could not create $WANTS_DIR — vaults created later theme at the next login instead."
fi
if [[ -d /run/systemd/system ]]; then
  if [[ "$AS_ROOT" == 1 ]]; then sysctl_user=(systemctl --user --machine="$USER_NAME@.host")
  else sysctl_user=(systemctl --user); fi
  "${sysctl_user[@]}" daemon-reload >/dev/null 2>&1 \
    && "${sysctl_user[@]}" start w-obsidian-vaults.path >/dev/null 2>&1 \
    || info "  (watcher starts with the next graphical login)"
fi

# ── 3. What the user may still want to know, said out loud ─────────────────────
info "Obsidian: the W snippet is enabled by default in fresh vaults."
info "  Toggled it off yourself? W respects that forever — re-enable by hand:"
info "  Settings → Appearance → CSS snippets → \"w\" (Reload snippets if needed)."
info "  A vault created while Obsidian is open shows the theme after the app"
info "  restarts (or toggle \"w\" on right away — the snippet is already there)."

info "office user setup complete for $USER_NAME."
exit 0
