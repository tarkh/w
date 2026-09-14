#!/usr/bin/env bash
# office bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup office` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# setup-user.sh triggered an axis render and switched on the vault-registry
# watcher; the render's artefacts in this account are the w.css snippets the
# axis left in its Obsidian vaults — and the axis itself was just removed from
# the w-style drop-in root by w-pack. Take all of it back, or the account keeps
# a themed file nothing left on the machine will ever refresh again:
#   1. <vault>/.obsidian/snippets/w.css        — W's file, removed outright
#   2. "w" in <vault>/.obsidian/appearance.json — the entry the axis' guarded
#      enable added; taken out of the array, every other key preserved
#   3. the w-obsidian-vaults.path wants-symlink — the watcher, stopped + unlinked
#
# NOT removed, by design:
#   * The vaults and every note in them — user data, never touched.
#   * Obsidian's other settings — appearance.json is jq-merged, one array entry
#     subtracted, nothing else. If Obsidian is RUNNING, both appearance.json and
#     (only for the stale-name effect) nothing else matter: the pass skips the
#     file (a running app holds it in memory and would overwrite us) and says
#     so — a snippet name without its file is invisible in the UI and harmless
#     (Obsidian keeps stale names on purpose, upstream wontfix: a sync service
#     may restore the file later).
#
# Idempotent; best-effort. See pack-office.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# ── 0. Is Obsidian running for this account? ───────────────────────────────────
# The Arch package runs the app under the system Electron (`/usr/lib/electronNN/
# electron /usr/lib/obsidian/app.asar`), so the process name is "electron" —
# match the asar on the command line, never `-x obsidian` (matches nothing).
obs_running=0
pgrep -u "$USER_NAME" -f 'obsidian/app\.asar' >/dev/null 2>&1 && obs_running=1

# ── 1. The axis-rendered snippets + the enable entries, one per vault ──────────
# Vault paths are user data; the registry is the only channel that knows them.
reg="$USER_HOME/.config/obsidian/obsidian.json"
if [[ ! -r "$reg" ]]; then
  info "No Obsidian vault registry for this account — nothing to undo."
else
  removed=0
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    f="$v/.obsidian/snippets/w.css"
    if [[ -f "$f" ]]; then
      rm -f "$f" && info "Removed $f"
      removed=1
    fi
    # Un-enable "w" (only where it is present, only with the app closed). If
    # the list is empty after taking "w" out, drop the key entirely: an empty
    # array is what a user toggle-off leaves behind, and it reads as "curated"
    # to the axis' three-state rule — removing the key returns the vault to the
    # fresh pre-W state, so a later reinstall gets the pack's default-enable
    # instead of a silently manual one. A non-empty list (user's own snippets)
    # is kept untouched.
    ap="$v/.obsidian/appearance.json"
    if [[ -f "$ap" && $obs_running -eq 0 ]] \
       && [[ "$(jq -r '(.enabledCssSnippets // []) | index("w")' "$ap" 2>/dev/null)" != "null" ]]; then
      if jq '.enabledCssSnippets |= map(select(. != "w"))
             | if ((.enabledCssSnippets // []) | length) == 0 then del(.enabledCssSnippets) else . end' \
           "$ap" >"$ap.tmp" 2>/dev/null && mv -f "$ap.tmp" "$ap"; then
        info "Un-enabled the W snippet in $v"
      else
        rm -f "$ap.tmp"
        warn "could not update $ap (left as-is; a stale name without its file is harmless)."
      fi
    fi
  done < <(jq -r '.vaults[]?.path // empty' "$reg" 2>/dev/null)
  (( removed == 1 )) || info "No W snippets found in this account's vaults."
fi
[[ $obs_running -eq 0 ]] || warn "Obsidian is running — appearance.json left alone (a stale snippet name is invisible and harmless)."

# ── 2. Stop watching the vault registry ────────────────────────────────────────
# The symlink is removed by hand for the same reason setup-user.sh wrote it by
# hand: at firstboot, or over runuser, `systemctl --user` addresses ROOT's manager.
LINK="$USER_HOME/.config/systemd/user/graphical-session.target.wants/w-obsidian-vaults.path"
if [[ -L "$LINK" || -e "$LINK" ]]; then
  rm -f "$LINK"
  info "New Obsidian vaults are no longer themed on creation for $USER_NAME."
fi
if [[ -d /run/systemd/system ]]; then
  if [[ "${PACK_AS_ROOT:-0}" == 1 ]]; then sysctl_user=(systemctl --user --machine="$USER_NAME@.host")
  else sysctl_user=(systemctl --user); fi
  "${sysctl_user[@]}" stop w-obsidian-vaults.path >/dev/null 2>&1 || true
  "${sysctl_user[@]}" daemon-reload >/dev/null 2>&1 || true
fi

# ── 3. What stays, and why ─────────────────────────────────────────────────────
info "Kept: your vaults and notes; ~/.config/obsidian (Obsidian's own state)."

info "office user teardown complete."
exit 0
