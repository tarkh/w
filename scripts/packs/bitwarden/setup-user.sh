#!/usr/bin/env bash
# bitwarden bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup bitwarden` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Everything this bundle does is per-account, because everything it touches is:
# which SSH agent YOUR session uses, and whether the app starts with YOUR login.
# The machine layer is just the package and the two managed files in the manifest,
# so there is no setup.sh at all.
#
# Works in every context — firstboot (root, the account not logged in), a later
# `sudo w-pack install bitwarden`, and a second account catching itself up with no
# root. Idempotent; best-effort. See pack-bitwarden.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root over sudo/ssh, or
# a service dir at firstboot) the target user cannot chdir there.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
#
# ⚠️ HOME and the XDG vars are passed EXPLICITLY. `runuser` keeps the caller's
# environment, so root's XDG_CONFIG_HOME / XDG_RUNTIME_DIR would otherwise ride
# along and w-ssh would write this account's agent choice into /root/.config/w —
# reporting success while changing nothing for the user it was run for.
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

# ── 1. Hand SSH over to Bitwarden's agent ────────────────────────────────────
# This writes the account's ssh.conf user layer, masks gcr-ssh-agent.socket for
# this account, and re-points W's stable SSH_AUTH_SOCK symlink. Reversible in one
# command (`w-ssh use gcr`), which is the whole point of the indirection.
if as_user w-ssh use bitwarden; then
  info "SSH agent for $USER_NAME → bitwarden."
else
  warn "could not switch the SSH agent for $USER_NAME — run 'w-ssh use bitwarden' as that user."
fi

# ── 2. Autostart with the graphical session ──────────────────────────────────
# The wants-symlink is written directly rather than via `systemctl --user enable`
# for the same reason w-ssh writes its mask by hand: at firstboot the account has
# no running user manager, and over runuser `systemctl --user` would address
# ROOT's manager instead. The symlink is exactly what `enable` produces.
WANTS_DIR="$USER_HOME/.config/systemd/user/graphical-session.target.wants"
LINK="$WANTS_DIR/bitwarden.service"
if install -d -m755 -o "$USER_NAME" -g "$USER_NAME" "$WANTS_DIR" 2>/dev/null \
   || install -d -m755 "$WANTS_DIR" 2>/dev/null; then
  ln -sfn /etc/systemd/user/bitwarden.service "$LINK"
  [[ "$AS_ROOT" == 1 ]] && chown -h "$USER_NAME:$USER_NAME" "$LINK" 2>/dev/null
  info "Bitwarden will start with $USER_NAME's graphical session (tray, hidden)."
else
  warn "could not create $WANTS_DIR — Bitwarden will not autostart for $USER_NAME."
fi

# A manager that is already running does not notice a new symlink on its own
# (the same gotcha mod_hyprland documents for `--global enable`). Best effort:
# nothing here is required for the NEXT login to be correct.
if [[ "$AS_ROOT" == 1 ]] && [[ -d /run/systemd/system ]]; then
  systemctl --user --machine="$USER_NAME@.host" daemon-reload >/dev/null 2>&1 || true
elif [[ -d /run/systemd/system ]]; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# ── 3. What only the human can do ────────────────────────────────────────────
# Three switches live inside the app's own settings and cannot be pre-set from
# outside: the vault is encrypted, and W deliberately never touches its state.
cat <<EOF

  Bitwarden is installed and wired in. Three steps remain inside the app itself
  (W cannot set them: they live in your encrypted vault's local state):

    1. Log in, then Settings → Security → "Unlock with system authentication".
       That is the biometric unlock. On W it goes through polkit, so the prompt
       is W's own auth card — fingerprint if you enrolled one (fprintd-enroll),
       password otherwise. No extra polkit setup is needed: the Arch package
       already ships the action file.

    2. Settings → "Enable SSH Agent". The socket path is pinned for you.

       Also turn on "Close to tray" (Settings → Preferences). The window pops
       out of the tray for every SSH request and stays after you approve;
       Super+Q hides it — but with this OFF (the app's default) Super+Q quits
       the app, and the SSH agent inside it dies too. "Remember SSH
       authorizations → until vault lock" keeps the prompts to one per key.

    3. Name each SSH key in the vault after the hosts it belongs to, e.g.
       "GitLab git.example.com" or "Prod 10.0.0.7", then run:

           w-ssh sync
           w-ssh include      # once, if ~/.ssh/config has no Include yet

       That generates the per-host key selectors without which an agent holding
       more than ~6 keys fails with "Too many authentication failures".

  Check anytime with: w-ssh status

EOF

info "bitwarden user setup complete for $USER_NAME."
exit 0
