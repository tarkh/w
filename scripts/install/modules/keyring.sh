# modules/keyring.sh — secrets: gnome-keyring (Secret Service) + gcr-ssh-agent (security.md, point 6)
#
# Two decoupled, swappable layers:
#   secrets  — gnome-keyring serves org.freedesktop.secrets ONLY (the unique value:
#              Bitwarden/NM/libsecret apps store here). Auto-unlocked at login via
#              pam_gnome_keyring in /etc/pam.d/greetd (deployed here).
#   ssh      — gcr-ssh-agent (from gcr-4) is W's default SSH agent. Its user socket
#              listens at $XDG_RUNTIME_DIR/gcr/ssh and self-exports SSH_AUTH_SOCK via
#              the socket's ExecStartPost, so no session-env hardcoding is needed.
#              Enabled globally for all users; a future --bitwarden masks it and
#              repoints SSH_AUTH_SOCK. (gnome-keyring's own ssh component was removed
#              upstream long ago — gcr-ssh-agent is its successor.)
# Note: gcr-ssh-agent's passphrase prompt is still gcr-prompter (GTK, follows the W
#       GTK theme). The W auth dialog (w-authd) already replaced the polkit agent;
#       phase 2 will fold this SSH passphrase prompt into the same Quickshell card.
# seahorse — GUI manager ("Passwords and Keys") for exactly this stack: inspect/revoke
#       keyring secrets, manage SSH-key passphrases stored by gcr-ssh-agent. Zero config
#       (auto-discovers Secret Service + ssh-agent over D-Bus, ships its own .desktop).

# ⚠️ First-login race — gnome-keyring MUST be started ONLY by gkr-pam, never by systemd.
# The gnome-keyring package ships (Arch vendor preset) an ENABLED systemd user unit
# gnome-keyring-daemon.socket (+ .service). With Linger=yes the user manager runs at
# boot, so sockets.target starts a PASSWORDLESS gnome-keyring daemon that grabs
# org.freedesktop.secrets and scans keyrings BEFORE gkr-pam creates the login keyring on
# the very first login. The login keyring then never loads: /collection/login stays a
# phantom (aliased as `default`, listed, but no D-Bus object). Every write to the default
# collection (e.g. `w-ai key set`) falls through to CreateCollection and hangs with no
# prompt. Subsequent logins work (keyring already on disk), so it looks like a one-off.
# Fix: mask both units so gkr-pam is the sole starter (`--daemonize --login`, with the
# stashed login password). The D-Bus activation of org.freedesktop.secrets then hands off
# to that already-running gkr-pam daemon (discover_other_daemon) instead of spawning a new
# passwordless one → login collection exports unlocked → stores are silent, no prompt.
# gcr-ssh-agent.socket is a DIFFERENT stack (SSH agent) and stays enabled. Verified on a
# fresh first-login VM; regression checklist lives in [[package-gnome-keyring]] TODO.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_keyring() {
  local mnt="${MNT:-}"

  ui_info "Installing gnome-keyring (Secret Service) + gcr-ssh-agent..."
  w_pac -S --needed --noconfirm gnome-keyring gcr-4 libsecret seahorse

  if [[ -n "$mnt" ]]; then
    install -Dm644 "$SRC/rootfs/etc/pam.d/greetd" "$mnt/etc/pam.d/greetd"
    chroot_run systemctl --global enable gcr-ssh-agent.socket
    chroot_run systemctl --global mask gnome-keyring-daemon.socket gnome-keyring-daemon.service
    return
  fi

  ui_info "Deploying greetd PAM stack (keyring auto-unlock)..."
  install -Dm644 "$SRC/rootfs/etc/pam.d/greetd" /etc/pam.d/greetd
  ui_info "Enabling gcr-ssh-agent.socket for all users..."
  systemctl --global enable gcr-ssh-agent.socket
  ui_info "Masking systemd gnome-keyring units (gkr-pam must be the sole starter)..."
  systemctl --global mask gnome-keyring-daemon.socket gnome-keyring-daemon.service

  ui_info "Secrets active: gnome-keyring (secrets) auto-unlocks at login; gcr-ssh-agent is the SSH agent."
}
