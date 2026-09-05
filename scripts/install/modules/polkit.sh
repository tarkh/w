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

  # ⚠️ ORDER MATTERS: the executable bit BEFORE the PAM stack that calls it.
  # The stack's first line runs /usr/lib/w/w-fp-gate through pam_exec, and
  # apply_rootfs can land plain files 644 (see apply-rootfs-resets-file-modes).
  # Deploying the stack first would leave a window in which every polkit
  # authentication runs a non-executable gate: it still authenticates (a gate
  # error means "skip the reader, ask for the password"), but the fingerprint
  # would be silently dead in between.
  #
  # w-authd + its user unit also ride in via apply_rootfs; same guard.
  [[ -f /usr/lib/w/w-authd ]] && chmod 755 /usr/lib/w/w-authd
  [[ -f /usr/lib/w/w-fp-gate ]] && chmod 755 /usr/lib/w/w-fp-gate

  # The channel the gate reads. It CANNOT live in the user's $XDG_RUNTIME_DIR:
  # the PAM conversation runs inside polkit-agent-helper@.service, whose
  # ProtectHome=yes hides /run/user, so a flag there is invisible and "Use
  # password" silently degrades to a 30s wait. Created here (not only by
  # --wallpaper, which owns the same file) so --polkit stays self-contained.
  info "Creating runtime dirs (fingerprint opt-out channel)..."
  install -Dm644 "$SRC/rootfs/usr/lib/tmpfiles.d/w.conf" /usr/lib/tmpfiles.d/w.conf
  systemd-tmpfiles --create /usr/lib/tmpfiles.d/w.conf

  info "Deploying polkit-1 PAM stack..."
  # Stack shape (rootfs/etc/pam.d/polkit-1):
  #   1. pam_exec gate   — lets the card's "Use password" button skip the reader
  #                       (see w-fp-gate; the flag lives in /run/w/fp because the
  #                       helper unit's ProtectHome hides /run/user);
  #   2. pam_fprintd     — sufficient: fingerprint first, silent no-op without a
  #                       reader or enrollment, falls through to the password;
  #   3. the password chain — a PINNED COPY of system-auth's auth section with
  #                      one delta: pam_unix gains `authtok_err=die conv_err=die`,
  #                      so a CANCELLED prompt (the socket-activated helper
  #                      talking to a dead socket since polkit 126; pam_get_authtok
  #                      maps that to PAM_AUTHTOK_ERR) fails WITHOUT pam_faillock
  #                      tallying it as a failed login. Drift from pambase is
  #                      gated by `scripts/check.sh --pam` (pinned snapshot +
  #                      live sha256 sensor). Wrong passwords still tally; see
  #                      quickshell-auth.md for the measured behaviour.
  # w-authd runs this stack via polkit-agent-helper-1, so fingerprint + password
  # both flow through unchanged — the shell card just surfaces the PAM messages.
  install -Dm644 "$SRC/rootfs/etc/pam.d/polkit-1" /etc/pam.d/polkit-1

  # Lets w-authd end an abandoned fingerprint verification (Cancel / Use password)
  # by restarting fprintd — the only abort path pam_fprintd honours, now that the
  # agent has no helper process left to signal. Scoped to that one unit, that one
  # verb and an active local session; ships via apply_rootfs, installed explicitly
  # here for the same self-containment reason as the PAM stack above.
  info "Deploying fingerprint-abort polkit rule..."
  install -Dm644 "$SRC/rootfs/usr/share/polkit-1/rules.d/50-w-fprintd-abort.rules" \
    /usr/share/polkit-1/rules.d/50-w-fprintd-abort.rules

  info "W auth agent (w-authd) installed; started from hyprland.lua."
  info "Fingerprint unlock activates after enrolling a finger: run 'fprintd-enroll' as your user."
}
