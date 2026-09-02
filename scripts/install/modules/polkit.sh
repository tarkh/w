# modules/polkit.sh — polkit authentication agent (W auth dialog).
# apply.sh context: runs on live system as root.
#
# Owns: package install, PAM stack for polkit-1.
# The active agent is w-authd (the unified "W auth dialog": a small Python daemon
# that IS the polkit agent and renders the prompt in the Quickshell shell —
# modules/auth/, see quickshell-auth.md). Its binary and systemd --user unit ship
# in rootfs (deployed by apply_rootfs); autostart is `systemctl --user start w-authd`
# in hyprland.lua. hyprpolkitagent is kept installed as a manual fallback only —
# it is NOT autostarted (only one polkit agent may register per session).

mod_polkit() {
  info "Installing polkit auth agent stack..."
  # python-gobject   — GI bindings (Polkit/PolkitAgent) that w-authd runs on
  # hyprpolkitagent  — kept as a manual fallback agent (not autostarted)
  # fprintd          — fingerprint D-Bus service; also installed by --hyprlock,
  #                    duplicated here so --polkit is self-contained
  w_pac -S --needed --noconfirm \
    python-gobject \
    hyprpolkitagent \
    fprintd

  info "Removing polkit-kde-agent if present..."
  pacman -Rns --noconfirm polkit-kde-agent 2>/dev/null || true

  info "Deploying polkit-1 PAM stack..."
  # pam_fprintd.so sufficient: tries fingerprint first; if no reader or no
  # enrolled finger, fails immediately and falls through to system-auth (password).
  # w-authd runs this stack via polkit-agent-helper-1, so fingerprint + password
  # both flow through unchanged — the shell card just surfaces the PAM messages.
  install -Dm644 "$SRC/rootfs/etc/pam.d/polkit-1" /etc/pam.d/polkit-1

  # w-authd + its user unit ride in via apply_rootfs; guard the executable bit
  # (apply_rootfs can land plain files 644 — see apply-rootfs-resets-file-modes).
  [[ -f /usr/lib/w/w-authd ]] && chmod 755 /usr/lib/w/w-authd

  info "W auth agent (w-authd) installed; started from hyprland.lua."
  info "Fingerprint unlock activates after enrolling a finger: run 'fprintd-enroll' as your user."
}
