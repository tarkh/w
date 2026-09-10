#!/usr/bin/env bash
# office bundle — MACHINE layer. Run by `w-pack install` AFTER packages and
# config, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# 1. LibreOffice UI language pack for the system locale
#    (libreoffice-fresh-<lang>, region-specific candidate first — the same
#    probe-the-sync-db idiom as w-langpack). The main package ships the en-US
#    UI built in (provides libreoffice-en-US), so a pack is only worth
#    installing for other languages; pkgs.txt cannot name it because the right
#    package depends on the machine's locale (same reason ai-extra installs the
#    GPU-matched Ollama here rather than in pkgs.txt).
# 2. Offline verification of the bundle's binaries.
#
# What deliberately does NOT happen here: spell-check dictionaries are
# w-langpack's job (hunspell-<lang> for the system locale; LibreOffice reads
# /usr/share/hunspell natively), and no LibreOffice user-profile file is seeded
# — LO rewrites registrymodifications.xcu itself and its defaults already pair
# colibre/colibre_dark with the system appearance.
#
# Idempotent; best-effort — a hiccup warns rather than aborting (packages are
# already deployed by the time this runs). See packs.md / pack-office.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. LibreOffice UI language pack for the system locale ─────────────────────
# Same source of truth as w-langpack: LANG in /etc/locale.conf.
lang="$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | tr -d '"' | head -1)"
lang="${lang%%.*}"                       # strip the encoding (.UTF-8)
lang_code="${lang%%_*}"; lang_code="${lang_code,,}"
terr_code="${lang#*_}"; [[ "$terr_code" == "$lang" ]] && terr_code=""
terr_code="${terr_code,,}"

# en_* is skipped entirely: the en-US UI is built into the main package and
# en-GB users are served by it (their spell-check comes from w-langpack's
# hunspell-en_gb either way) — a langpack would be dead weight, the same call
# w-langpack makes for Firefox.
lo_langpkg=""
if [[ -n "$lang_code" && "$lang_code" != en ]]; then
  cands=()
  [[ -n "$terr_code" ]] && cands+=("libreoffice-fresh-${lang_code}-${terr_code}")
  cands+=("libreoffice-fresh-${lang_code}")
  for c in "${cands[@]}"; do
    pacman -Si -- "$c" &>/dev/null && { lo_langpkg="$c"; break; }
  done
fi

if [[ -z "$lo_langpkg" ]]; then
  info "No LibreOffice language pack needed (locale '${lang:-unknown}' — en-US UI is built in)."
elif pacman -Qq -- "$lo_langpkg" &>/dev/null; then
  info "LibreOffice language pack already installed: $lo_langpkg"
else
  info "Installing LibreOffice UI language pack: $lo_langpkg"
  pacman -S --needed --noconfirm "$lo_langpkg" \
    || warn "pacman install of $lo_langpkg failed — the UI stays en-US (non-fatal)."
fi

# ── 2. Offline verification (no network calls — packs.md contract) ───────────
info "Verifying office components (offline)..."
for bin in soffice pdfarranger xournalpp obsidian; do
  command -v "$bin" >/dev/null && info "$bin: OK" \
    || warn "$bin: binary not found — package install above may have failed."
done

# ── 3. Session-env reminder (packs.md gotcha: both channels are login-scoped) ─
info "Note: SAL_USE_VCLPLUGIN (gtk3 pin) is active from the NEXT login."

info "office machine setup complete."
exit 0
