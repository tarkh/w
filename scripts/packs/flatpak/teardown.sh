#!/usr/bin/env bash
# flatpak bundle — MACHINE layer teardown, the declared inverse of setup.sh. Run
# by `w-pack remove` as root with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_PACKAGES (1|0)
#
# setup.sh wired four machine-wide things; only two of them are W's to unwire:
#
#   * the global theme override — W's, and declarative by construction. setup.sh
#     itself starts from `override --system --reset` on every run, so resetting is
#     not a destructive novelty here: it is the exact state the bundle leaves
#     between its own steps. Any hand-added system override was already being
#     dropped on every `w-pack refresh flatpak`.
#   * the Kvantum QStyle engine extensions — installed per KDE runtime branch
#     purely so W's Qt brand resolves inside the sandbox. Useless without the
#     override above, so they leave with it (packages, hence --packages only).
#
# NOT undone, because they are the user's, not W's:
#   * the Flathub remote — remove it and every app installed from it loses its
#     origin and its updates. The remote is the ecosystem the user opted into;
#     this bundle only pointed at it.
#   * installed Flatpak apps and their runtimes — data, gigabytes of it.
#   * Flatseal — a real application the user may want to keep even after W stops
#     theming the sandbox. Offered under --packages, named otherwise.
#
# Idempotent; best-effort. See pack-flatpak.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

WITH_PACKAGES="${PACK_PACKAGES:-0}"
FLATSEAL_ID="com.github.tchx84.Flatseal"

command -v flatpak >/dev/null 2>&1 \
  || { info "flatpak is not installed — nothing machine-wide to unwire."; exit 0; }

# ── 1. Drop W's global theme override ────────────────────────────────────────
info "Resetting the system-wide Flatpak override (W's sandbox theming)..."
flatpak override --system --reset || warn "override reset failed"

# ── 2. The Kvantum engine extensions and Flatseal (packages) ────────────────
kvantum="$(flatpak list --columns=ref 2>/dev/null | grep '^org\.kde\.KStyle\.Kvantum/' || true)"
if [[ "$WITH_PACKAGES" == 1 ]]; then
  if [[ -n "$kvantum" ]]; then
    while read -r ref; do
      [[ -n "$ref" ]] || continue
      info "Removing $ref..."
      flatpak uninstall -y --noninteractive "$ref" || warn "could not remove $ref"
    done <<<"$kvantum"
  fi
  if flatpak info "$FLATSEAL_ID" &>/dev/null; then
    info "Removing Flatseal..."
    flatpak uninstall -y --noninteractive "$FLATSEAL_ID" || warn "could not remove Flatseal"
  fi
else
  [[ -n "$kvantum" ]] && info "Kept: the KStyle.Kvantum engine extension(s) — they only served W's Qt theming."
  flatpak info "$FLATSEAL_ID" &>/dev/null && info "Kept: Flatseal ($FLATSEAL_ID)."
  { [[ -n "$kvantum" ]] || flatpak info "$FLATSEAL_ID" &>/dev/null; } \
    && info "  Re-run with --packages to take them, or use 'flatpak uninstall'."
fi

# ── 3. What the user keeps either way ────────────────────────────────────────
if flatpak remotes --system 2>/dev/null | grep -q '^flathub'; then
  info "Kept: the Flathub remote — your installed apps get their updates from it."
  info "  Remove it yourself only if you are done with Flatpak entirely:"
  info "      sudo flatpak remote-delete flathub"
fi
apps="$(flatpak list --app --columns=application 2>/dev/null | grep -cv '^$' || true)"
[[ "${apps:-0}" -gt 0 ]] && info "Kept: $apps installed Flatpak app(s) — W never removes your software."

info "Sandboxed apps fall back to their stock theme at their next launch."
info "flatpak machine teardown complete."
exit 0
