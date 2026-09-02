# modules/reset.sh — w-reset: force-restore any module's config to the W default.
# apply.sh context: runs on the live system as root, post-boot. Ships the w-reset
# script and stages the offline vendor copies of the /etc/w admin-state configs so
# `w-reset <module>` can drop an override back to the vendor default without the
# repo (on a client that keeps its own edited /etc/w/*.conf). See update-system.md
# (ös 3, phase 3). w-reset itself reads the per-module ownership manifests under
# /usr/share/w/update — the same single source of truth the deploy SDK seeds from.

mod_reset() {
  info "Installing w-reset (config force-restore utility)..."
  install -Dm755 "$SRC/rootfs/usr/bin/w-reset" /usr/bin/w-reset

  # Vendor copies of the /etc/w admin-state configs (the ones the update PRESERVES:
  # dns/ai/crypt/logs/power). Sourced from the repo (= pristine truth here), so `w-reset`'s
  # override-restore works offline against a locally edited /etc/w. On stable, the
  # w-system package will ship these instead (phase 6).
  info "Staging vendor defaults for /etc/w override-restore..."
  local f
  for f in dns ai crypt logs power; do
    [[ -f "$SRC/rootfs/etc/w/$f.conf" ]] &&
      install -Dm644 "$SRC/rootfs/etc/w/$f.conf" "/usr/share/w/vendor/etc-w/$f.conf"
  done

  info "w-reset installed. Recover a module: w-reset <module>; everything: w-reset --all; list: w-reset list."
}
