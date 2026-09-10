#!/usr/bin/env bash
# office bundle — MACHINE layer teardown, the declared inverse of setup.sh. Run
# by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# THIS IS WHY THE INVERSE HAS TO BE DECLARED: setup.sh installs the LibreOffice
# UI language pack for the system locale (libreoffice-fresh-<lang>), decided at
# install time from /etc/locale.conf — so a locale-depended package is
# deliberately NOT in pkgs.txt, and a remover that only undid the tree would
# leave it behind. Only the bundle knows what it installed, so only the bundle
# can take it back.
#
# What is NOT undone, by design:
#   * User documents, annotated PDFs and Obsidian vaults — data, never deleted.
#   * ~/.config/libreoffice (profiles) and ~/.config/obsidian (app state) — the
#     same rule in per-account homes; the software itself also stays unless
#     --packages was given, so removing its settings would be harm, not cleanup.
#
# Idempotent; best-effort. See pack-office.md.

set -uo pipefail   # NOT -e: an already-absent piece must not abort the rest

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

WITH_PACKAGES="${PACK_PACKAGES:-0}"

# ── 1. The locale language pack setup.sh chose (only when packages were asked) ─
# Whichever pack is actually installed is the one to take, not the one this
# machine would pick today — the system locale may have changed since install.
# The pattern matches langpacks only (ru, pt-br, zh-cn, ca-valencia, en-gb, …):
# exactly two letters then end-or-hyphen excludes the suite itself (no suffix)
# and the -sdk split package.
langpack="$(pacman -Qq 2>/dev/null | grep -E '^libreoffice-fresh-[a-z]{2}($|-[a-z-]+$)' | head -1 || true)"
if [[ -n "$langpack" ]]; then
  if [[ "$WITH_PACKAGES" == 1 ]]; then
    info "Removing $langpack (installed by this bundle's setup, not by pkgs.txt)..."
    pacman -Rns --noconfirm "$langpack" || warn "could not remove $langpack"
  else
    info "Left installed: $langpack — this bundle installed it outside pkgs.txt."
    info "  It is included if you re-run with --packages, or remove it yourself:"
    info "      sudo pacman -Rns $langpack"
  fi
fi

# ── 2. User data stays ────────────────────────────────────────────────────────
info "Kept (user data, W never deletes it): documents, annotated PDFs,"
info "  Obsidian vaults, ~/.config/libreoffice (profiles) and"
info "  ~/.config/obsidian (app state)."

info "office machine teardown complete."
exit 0
