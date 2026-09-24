#!/usr/bin/env bash
# comfyui bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup comfyui` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Desktop ComfyUI per-user setup is exactly one thing: add the account to the
# `w-ai` group so it can write into the shared model store. The store's setgid
# dirs (w-ai, 2775) make that group the write boundary — the engine account
# `comfyui` is grouped g+w-ai too, so both the service and the human users can
# drop/read models in $DIR, while nothing outside the store is opened up. The
# web UI itself is the machine's systemd service bound to localhost; a browser
# just talks HTTP, no per-user socket or daemon involved.
#
# That is the whole per-user layer — no app install (machine-scope), no model
# download (users pull what they need into the group dir). Adding the group is
# genuinely root's call (usermod edits /etc/group), so an account catching itself
# up without root gets the exact command to ask for.
#
# Idempotent; best-effort. See pack-comfyui.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# ── 1. Group `w-ai` membership ────────────────────────────────────────────────
# setgid 2775 dirs under the store give group-writes and group-inheritance for new
# files (see setup.sh step 4). `usermod -aG w-ai` adds the group; the effect is at
# the NEXT login (a new group list is read at session start, not mid-session).
info "Adding $USER_NAME to group 'w-ai' (shared model store write access)..."
if [[ "$AS_ROOT" == 1 ]]; then
  if usermod -aG w-ai "$USER_NAME" >/dev/null 2>&1; then
    info "$USER_NAME added to group 'w-ai'."
  else
    warn "usermod -aG w-ai failed — the account may already be a member, or usermod errored."
  fi
else
  # Adding a user to a group is root's call (it edits /etc/group). An account
  # catching itself up without root gets the exact command to ask for — a silent
  # skip would leave it unable to write models with no clue why.
  if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx w-ai; then
    info "$USER_NAME is already in group 'w-ai' — nothing to do."
  else
    warn "$USER_NAME is not in group 'w-ai'. Only an administrator can add it:"
    warn "    sudo usermod -aG w-ai $USER_NAME"
    warn "  then log out and back in (group membership applies at login), and re-run:"
    warn "    w-pack setup comfyui"
  fi
fi

# ── 2. Offline verification ──────────────────────────────────────────────────
# Confirm the group exists (it comes from the bundle's own sysusers). No service
# check here — the engine may legitimately not be running.
if getent group w-ai >/dev/null 2>&1; then
  : # group present
else
  warn "group 'w-ai' not found — the bundle's sysusers did not create it?"
  warn "  The machine layer may not be set up yet; re-run after 'sudo w-pack install comfyui'."
fi

info "comfyui user setup complete for $USER_NAME."
info "  Group membership applies at the NEXT login. Open 'ComfyUI' from the app"
info "  menu (menu item starts the service first), or:"
info "    systemctl start comfyui   &&   xdg-open http://127.0.0.1:8188"
info "  Model files go into the shared store: sudo w-conf set ai-models DIR ...  show:"
info "    w-conf get ai-models DIR"
# Where the renders land is the first thing anyone asks after the first
# generation, and the answer is not guessable — it sits under the engine root,
# which w-ai membership (above) is what makes browsable at all. Resolve both
# paths rather than printing the defaults: this account may be catching up on a
# machine whose admin relocated them long ago.
if [[ -r /usr/lib/w/w-conf-lib.sh ]]; then
  source /usr/lib/w/w-conf-lib.sh
  wconf_load comfyui 2>/dev/null
  info "  Your generated images and video: $(wconf_get comfyui ROOT /var/lib/w/comfyui)/data/output"
fi
exit 0