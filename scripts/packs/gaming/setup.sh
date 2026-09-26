#!/usr/bin/env bash
# gaming bundle — MACHINE layer. Run by `w-pack install`/`refresh` AFTER
# packages and config (manifest) are in place, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Three machine-wide switches that pkgs.txt/manifest alone cannot flip:
# firewalld (Steam's in-home LAN features), the ntsync device node (loaded by
# ntsync-autoload's modules-load.d drop-in, but not necessarily yet on THIS
# boot if the pack was just installed), and a one-line pointer to the sched_ext
# scheduler pkgs.txt already installed but this bundle deliberately does not
# enable (see pkgs.txt).
#
# Idempotent; best-effort. See pack-gaming.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. firewalld: Steam in-home LAN features ──────────────────────────────
# steam-streaming (Remote Play to another device on the LAN) and
# steam-lan-transfer (peer-to-peer local game copies) — both shipped by
# firewalld itself (package-gpu.md precedent: pack-localsend). Zone `home`,
# not `public` — Steam stays unreachable on someone else's Wi-Fi, same rule
# every other W LAN service follows.
if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
  ok=1
  firewall-cmd --permanent --zone=home --add-service=steam-streaming >/dev/null || ok=0
  firewall-cmd --permanent --zone=home --add-service=steam-lan-transfer >/dev/null || ok=0
  firewall-cmd --reload >/dev/null || ok=0
  if [[ $ok -eq 1 ]]; then
    info "Opened Steam Remote Play + LAN transfer in the 'home' firewall zone."
  else
    warn "could not fully open Steam's firewalld services — run manually:"
    warn "  firewall-cmd --permanent --zone=home --add-service=steam-streaming --add-service=steam-lan-transfer && firewall-cmd --reload"
  fi
else
  warn "firewalld not available — Steam Remote Play/LAN transfer will not be reachable until you open them yourself."
fi

# ── 2. ntsync device node ──────────────────────────────────────────────────
# ntsync-autoload (pkgs.txt) ships a modules-load.d drop-in that loads the
# module on every FUTURE boot. On THIS run (a fresh pack install on an
# already-booted machine) the device may not exist yet — load it now so
# Proton benefits immediately instead of waiting for a reboot.
if [[ -e /dev/ntsync ]]; then
  info "/dev/ntsync already present."
elif modprobe ntsync 2>/dev/null; then
  info "Loaded the ntsync kernel module."
else
  warn "could not load ntsync (kernel $(uname -r) may lack the module) — Proton will fall back to esync/fsync, which is slower."
fi

# ── 3. scx_lavd — installed, not enabled ───────────────────────────────────
# W does not switch the machine's CPU scheduler on install (a global,
# session-wide change is not something a game-focused pack should force).
# scx-scheds (pkgs.txt) ships it; point at the one-line way to try it.
if command -v scx_lavd >/dev/null 2>&1; then
  info "scx_lavd (game-tuned sched_ext scheduler) is installed but not enabled."
  info "  Try it:   sudo systemctl start scx_lavd   (stop: sudo systemctl stop scx_lavd)"
fi

info "gaming machine setup complete."
info "Steam/Lutris/Heroic window rules and the gamemode<->w-power bridge are"
info "  live now (Hyprland sessions are reloaded by w-pack); the 'gamemode'"
info "  group (Session 4) needs a fresh login to take effect."
exit 0
