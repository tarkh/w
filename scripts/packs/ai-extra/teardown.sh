#!/usr/bin/env bash
# ai-extra bundle — MACHINE layer teardown, the declared inverse of setup.sh. Run
# by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# THIS BUNDLE IS WHY THE INVERSE HAS TO BE DECLARED. setup.sh installs Ollama by
# GPU variant (ollama / ollama-cuda / ollama-rocm), decided at install time from
# lspci — so the bundle's main package is deliberately NOT in pkgs.txt, and a
# remover that only undid the tree would leave it behind, service and all. Only
# the bundle knows what it installed, so only the bundle can take it back.
#
# What is NOT undone, by design:
#   * /var/lib/ollama — the model store. Gigabytes of downloads, and a nested
#     btrfs subvolume that `rm -rf` does not even remove properly. It is data:
#     the path and its size are printed and the human decides.
#
# Idempotent; best-effort. See pack-ai-extra.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

WITH_PACKAGES="${PACK_PACKAGES:-0}"
STORE="/var/lib/ollama"

# ── 1. Stop and disable the service ──────────────────────────────────────────
if systemctl list-unit-files ollama.service &>/dev/null; then
  info "Disabling ollama.service..."
  systemctl disable --now ollama.service 2>/dev/null \
    || warn "could not disable ollama.service (already gone?)"
fi

# ── 2. The GPU-variant package setup.sh chose (only when packages were asked for) ─
# Whichever variant is actually installed is the one to take, not the one this
# machine would pick today — the GPU may have changed since.
variant="$(pacman -Qq 2>/dev/null | grep -E '^ollama(-cuda|-rocm)?$' | head -1 || true)"
if [[ -n "$variant" ]]; then
  if [[ "$WITH_PACKAGES" == 1 ]]; then
    info "Removing $variant (installed by this bundle's setup, not by pkgs.txt)..."
    pacman -Rns --noconfirm "$variant" || warn "could not remove $variant"
  else
    info "Left installed: $variant — this bundle installed it outside pkgs.txt."
    info "  It is included if you re-run with --packages, or remove it yourself:"
    info "      sudo pacman -Rns $variant"
  fi
fi

# ── 3. The model store stays — it is data ────────────────────────────────────
if [[ -d "$STORE" ]]; then
  size="$(du -sh "$STORE" 2>/dev/null | cut -f1 || echo '?')"
  info "Kept: $STORE ($size) — downloaded models, W never deletes them."
  if btrfs subvolume show "$STORE" >/dev/null 2>&1; then
    info "  It is a btrfs subvolume; to reclaim the space:"
    info "      sudo btrfs subvolume delete $STORE"
  else
    info "  To reclaim the space: sudo rm -rf $STORE"
  fi
fi

info "ai-extra machine teardown complete."
exit 0
