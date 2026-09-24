#!/usr/bin/env bash
# ai-extra bundle — MACHINE layer teardown, the declared inverse of setup.sh. Run
# by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# THIS BUNDLE IS WHY THE INVERSE HAS TO BE DECLARED. setup.sh installs Ollama as
# base + GPU backend (ollama, plus ollama-cuda / ollama-rocm), the backend decided
# at install time from lspci — so the bundle's main package is deliberately NOT in
# pkgs.txt, and a remover that only undid the tree would leave it behind, service
# and all. Only the bundle knows what it installed, so only it can take it back.
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

# ── 2. The Ollama packages setup.sh installed (only when packages were asked for) ─
# Whatever is actually installed is what gets taken, not what this machine would
# pick today — the GPU may have changed since. Base and backend go in ONE call:
# they are not competing variants, `ollama-rocm`/`ollama-cuda` DEPEND on `ollama`,
# so removing the base alone is refused while a backend is still installed.
mapfile -t variants < <(pacman -Qq ollama ollama-cuda ollama-rocm 2>/dev/null || true)
if (( ${#variants[@]} )); then
  if [[ "$WITH_PACKAGES" == 1 ]]; then
    info "Removing ${variants[*]} (installed by this bundle's setup, not by pkgs.txt)..."
    pacman -Rns --noconfirm "${variants[@]}" || warn "could not remove ${variants[*]}"
  else
    info "Left installed: ${variants[*]} — this bundle installed them outside pkgs.txt."
    info "  They are included if you re-run with --packages, or remove them yourself:"
    info "      sudo pacman -Rns ${variants[*]}"
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
