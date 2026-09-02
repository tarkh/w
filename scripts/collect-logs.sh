#!/usr/bin/env bash
# collect-logs.sh — gather W Linux install + runtime diagnostics into one bundle.
# Run inside the installed VM/target as root, after first boot (ideally after
# apply.sh) — w-firstboot calls this itself once apply --all finishes (success or
# failure), so a diagnostic bundle always exists, even on real hardware with no
# dev-VM share to inspect logs over SSH.
#   bash /var/lib/w/src/scripts/collect-logs.sh [dest-dir]
# Default dest: /var/log/w/diag/ — same root as the install/apply/firstboot logs,
# persistent on the target's own root filesystem (unlike /tmp, usually tmpfs → gone
# on reboot). Also best-effort mirrored to the virtiofs share (/mnt/w-src/vm/logs/)
# when present, for host-side dev convenience.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must be run as root." >&2; exit 1; }

TS="$(date +%Y%m%d-%H%M%S)"
BASE="${1:-/var/log/w/diag}"
OUT="$BASE/diag-$TS"
mkdir -p "$OUT"

say() { echo -e "\033[1;35m==>\033[0m $*"; }
grab() { # grab <outfile> <cmd...>
  local f="$1"; shift
  echo "\$ $*" > "$OUT/$f"
  "$@" >> "$OUT/$f" 2>&1 || echo "[exit $?]" >> "$OUT/$f"
}

say "Collecting into $OUT"

# ── Install / apply logs ───────────────────────────────────────────────────────
for f in /var/log/w/install.log /var/log/w/apply.log /var/log/w/firstboot.log; do
  [[ -f "$f" ]] && cp "$f" "$OUT/"
done

# ── Journal (current boot) ─────────────────────────────────────────────────────
grab journal-err.txt      journalctl -b -p err     --no-pager
grab journal-warn.txt     journalctl -b -p warning --no-pager
grab journal-full.txt     journalctl -b            --no-pager
grab journal-prev-err.txt journalctl -b -1 -p err  --no-pager

# ── Failed units ───────────────────────────────────────────────────────────────
grab failed-system.txt systemctl --failed --no-pager
# Per-user units for each human user (uid >= 1000).
while IFS=: read -r user _ uid _; do
  (( uid >= 1000 && uid < 65534 )) || continue
  echo "\$ systemctl --user --failed ($user)" > "$OUT/failed-user-$user.txt"
  # shellcheck disable=SC2024  # runs as root: sudo -u DROPS to the user for the
  # query while the root-owned redirect into $OUT is exactly what we want
  sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" \
    systemctl --user --failed --no-pager >> "$OUT/failed-user-$user.txt" 2>&1 \
    || echo "[no user bus / not logged in]" >> "$OUT/failed-user-$user.txt"
done < /etc/passwd

# ── Boot / hardware / packages ─────────────────────────────────────────────────
grab dmesg.txt            dmesg
grab coredumps.txt        coredumpctl list --no-pager
grab boot-blame.txt       systemd-analyze blame
grab boot-critical.txt    systemd-analyze critical-chain
grab pkgs-explicit.txt    pacman -Qe
grab pkgs-foreign.txt     pacman -Qm
[[ -f /var/log/pacman.log ]] && cp /var/log/pacman.log "$OUT/"

# ── Bundle ─────────────────────────────────────────────────────────────────────
tar -czf "$OUT.tar.gz" -C "$BASE" "diag-$TS" 2>/dev/null || true
sync

# Dev-VM convenience: mirror the bundle to the host-shared virtiofs, if mounted
# (same detection as devtools.sh). No-op on real hardware.
if mountpoint -q /mnt/w-src 2>/dev/null; then
  mkdir -p /mnt/w-src/vm/logs 2>/dev/null && cp "$OUT.tar.gz" /mnt/w-src/vm/logs/ 2>/dev/null || true
fi

say "Done. Bundle: $OUT  (+ $OUT.tar.gz)"
