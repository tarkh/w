#!/usr/bin/env bash
# bitwarden bundle — PER-USER teardown, the declared inverse of setup-user.sh. Run
# by `w-pack remove` (for every account that had the layer) and by
# `w-pack unsetup bitwarden` (rootless, for whoever asks), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)  PACK_PACKAGES
#
# This bundle is per-account end to end, so this is the whole of its teardown —
# there is no teardown.sh, exactly as there is no setup.sh.
#
# The SSH agent is the important half. setup-user.sh handed SSH over to Bitwarden's
# agent, which masked gcr-ssh-agent.socket for this account and re-pointed W's
# stable SSH_AUTH_SOCK symlink. Leaving that in place while removing the bundle
# would give the account a session pointing at an agent socket nothing serves —
# every `git push` failing with no explanation. `w-ssh use gcr` is the documented
# one-command reversal, which is what the indirection existed for.
#
# The vault (~/.config/Bitwarden) is never touched: it is the user's encrypted
# data, and W has no business in it whether the app stays or goes.
#
# Idempotent; best-effort. See pack-bitwarden.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# HOME and the XDG vars are passed EXPLICITLY — runuser keeps the caller's
# environment, so root's XDG_CONFIG_HOME would send w-ssh's write into
# /root/.config/w and report success while changing nothing for this account.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then
    # The runtime vars ride along too: root's XDG_RUNTIME_DIR (/run/user/0) would
    # make w-ssh create its socket link there — EPERM for the account, "could not
    # switch the SSH agent". Point them at the account's own runtime dir when it
    # has a session, drop them when it does not (firstboot: w-ssh then falls back
    # to /run/user/<uid> itself). Same recipe as deploy.sh's w_render_user_theme.
    local rt; rt="/run/user/$(id -u "$USER_NAME")"
    local -a sess=(-u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS)
    [[ -d "$rt" ]] && sess=(XDG_RUNTIME_DIR="$rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus")
    runuser -u "$USER_NAME" -- env "${sess[@]}" HOME="$USER_HOME" \
      XDG_CONFIG_HOME="$USER_HOME/.config" WCONF_HOME="$USER_HOME" "$@"
  else
    env HOME="$USER_HOME" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$USER_HOME/.config}" \
      WCONF_HOME="$USER_HOME" "$@"
  fi
}

# ── 1. Hand SSH back to the keyring agent ────────────────────────────────────
if as_user w-ssh use gcr; then
  info "SSH agent for $USER_NAME → gcr (the W default)."
else
  warn "could not switch the SSH agent back for $USER_NAME."
  warn "  Run this as that user, or SSH will point at an agent that is not there:"
  warn "      w-ssh use gcr"
fi

# ── 2. Stop autostarting with the graphical session ──────────────────────────
# The symlink is removed by hand for the same reason setup-user.sh wrote it by
# hand: at firstboot, or over runuser, `systemctl --user` addresses ROOT's manager.
LINK="$USER_HOME/.config/systemd/user/graphical-session.target.wants/bitwarden.service"
if [[ -L "$LINK" || -e "$LINK" ]]; then
  rm -f "$LINK"
  info "Bitwarden will no longer start with $USER_NAME's graphical session."
fi
if [[ "$AS_ROOT" == 1 ]] && [[ -d /run/systemd/system ]]; then
  systemctl --user --machine="$USER_NAME@.host" daemon-reload >/dev/null 2>&1 || true
elif [[ -d /run/systemd/system ]]; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# ── 3. What stays ────────────────────────────────────────────────────────────
if [[ -d "$USER_HOME/.config/Bitwarden" ]]; then
  info "Kept: ~/.config/Bitwarden — your vault's local state, never W's to delete."
fi
info "Per-host key selectors written by 'w-ssh sync' stay in ~/.ssh; 'w-ssh status' shows the agent."
info "bitwarden user teardown complete for $USER_NAME."
exit 0
