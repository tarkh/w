# modules/userdirs.sh — standard home folders (xdg-user-dirs + w-userdirs).
#
# Userspace layer: wired into apply.sh only (post-boot; the installer stays
# minimal-base), same as mod_nightlight and mod_session.
#
# xdg-user-dirs is the freedesktop layer that gives ~/Documents, ~/Pictures and
# the rest a logical name (`xdg-user-dir PICTURES`) and a language: at every login
# its own user unit creates the missing folders translated into the user's locale
# and records them in ~/.config/user-dirs.dirs. W's only additions are the curated
# defaults file (six folders; shipped by apply_rootfs) and the step upstream
# leaves to a GNOME dialog — renaming the folders when the language changes —
# which is w-userdirs' user unit, ordered before the stock one. See w-userdirs.md.
#
# Nothing here creates or names a folder itself: that is what the user's own
# login does, in the user's language, under the user's uid. A root-side loop over
# homes would get the language wrong for every account but the one that ran the
# apply, and would leave root-owned folders behind — the trap mod_screencapture
# used to fall into with ~/Pictures.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_userdirs() {
  # Post-boot only: there is no user session inside the chroot for the units to
  # run in, and the package is in packages/pacman.txt for the install itself.
  [[ -n "${MNT:-}" ]] && return 0

  # In packages/pacman.txt, but a standalone --userdirs run may predate it.
  command -v xdg-user-dirs-update >/dev/null 2>&1 \
    || { ui_info "Installing xdg-user-dirs..."; w_pac -S --needed --noconfirm xdg-user-dirs; }

  # Both units are WantedBy=graphical-session-pre.target: the stock one is
  # preset-enabled by the package, W's needs the same global enable every W user
  # unit gets (mod_nightlight, mod_session) — every login user's uwsm session
  # raises that target and must get its own run, not just whoever was logged in
  # during apply. The daemon-reload makes a freshly shipped unit visible to an
  # already-running session's `systemctl --user`.
  systemctl daemon-reload
  systemctl --global enable xdg-user-dirs.service 2>/dev/null || true
  systemctl --global enable w-userdirs.service 2>/dev/null || true

  ui_info "Standard home folders: created in each user's language at their next login (w-userdirs status)."
  return 0
}
