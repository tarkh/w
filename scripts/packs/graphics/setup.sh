#!/usr/bin/env bash
# graphics bundle — MACHINE layer. Run by `w-pack install` AFTER packages and
# config, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# There is nothing to set up on the machine: the four apps are plain packages,
# their look rides existing w-style axes (GIMP/Inkscape → gtk + appearance
# through the seeded gimprc / Inkscape's defaults; Krita → its own theme set),
# and everything AI-related is per account (setup-user.sh). What remains is the
# offline verification every bundle does — the binaries and the MCP SDK the
# GIMP bridge's server half needs.
#
# Idempotent; best-effort — a hiccup warns rather than aborting (packages are
# already deployed by the time this runs). See packs.md / pack-graphics.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── Offline verification ─────────────────────────────────────────────────────
info "Verifying the graphics bundle (offline)..."
for b in gimp inkscape krita; do
  command -v "$b" >/dev/null && info "$b: OK" || warn "$b: not found"
done
[[ -x /usr/lib/gimp/3.0/plug-ins/gmic_gimp_qt/gmic_gimp_qt ]] && info "G'MIC for GIMP: OK" \
  || warn "G'MIC for GIMP: plug-in not found (gimp-plugin-gmic)"
# python-mcp comes from the base --ai module (w-mcp runs on it), not from pkgs.txt.
python3 -c 'import mcp' 2>/dev/null && info "python-mcp (GIMP bridge SDK): OK" \
  || warn "python-mcp: not importable — run 'sudo apply.sh --ai'; the GIMP MCP server will not start"

info "graphics machine setup complete."
exit 0
