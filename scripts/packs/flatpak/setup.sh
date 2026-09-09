#!/usr/bin/env bash
# flatpak bundle — MACHINE layer. Run by `w-pack install` AFTER packages, always as
# root with: BUNDLE_NAME  BUNDLE_DIR
#
# What is machine-wide here: the Flathub remote, the global theme override, the
# Kvantum QStyle engine per KDE runtime branch, and Flatseal. What is NOT — the
# Papirus icon mirror, which lives in one account's home and therefore in
# setup-user.sh (packs.md, "two layers").
#
# THE HARD PART — carrying the W theme into the sandbox. A Flatpak app sees the
# runtime's /usr and a private $HOME, NOT the host's themes/configs. /usr/share/
# themes and /usr/share/icons are BLACKLISTED (a --filesystem bind there is a silent
# no-op). What does work, per toolkit (all verified on VM):
#
#   • GTK3 — flatpak mounts the Gtk3theme EXTENSION whose name equals the host
#     gtk-theme (reported via xdg-desktop-portal-gtk → gsettings), which the
#     appearance axis flips between w-gtk and w-gtk-alt for live host recolor. The
#     w-gtk twins @import an ABSOLUTE adw-gtk3 path the sandbox can't resolve, so the
#     extensions must be SELF-CONTAINED. This bundle does NOT build them — the w-style
#     `gtk` axis does (sync_flatpak_gtk3), so they track every theme switch, for BOTH
#     names, user-scope (rendered at login by env-hyprland; setup-user.sh renders once
#     at install so the first launch is already themed). No GTK_THEME env is set (the
#     portal already names the theme; any value — even empty — breaks GTK3/GTK4).
#   • GTK4/libadwaita — ignores named themes; reads ~/.config/gtk-4.0/gtk.css (bound)
#     for the brand @define-colors and the portal's icon-theme for icons. (GTK_THEME
#     would break it — left unset.)
#   • Qt — qt5ct/qt6ct platform themes do NOT load in the sandbox (no plugin in the
#     runtimes). The KDE runtime ships KDEPlasmaPlatformTheme, so QT_QPA_PLATFORMTHEME=
#     kde drives Qt brand from bound kdeglobals: the W KColorScheme, [Icons] Theme, and
#     [General] font (the only Qt font channel in the sandbox — w-style writes it). The
#     widget engine is Kvantum (QT_STYLE_OVERRIDE=kvantum + the KStyle.Kvantum engine
#     extension matching each KDE runtime branch). Non-KDE-runtime Qt apps degrade
#     gracefully (Kvantum colors, no platform icons/font).
#   • Icons — /usr/share/icons is blacklisted and Flathub has no Papirus Icontheme
#     extension, so setup-user.sh reflink-copies host Papirus into the account's
#     ~/.local/share/icons (bindable). GTK (portal icon-theme=Papirus-Dark) and Qt
#     (kdeglobals [Icons] Theme=Papirus-Dark) both resolve their icons there.
#   • The brand overlays (GTK4 css, Kvantum theme, kdeglobals + W.colors, fontconfig)
#     ride in via home-dir binds (xdg-config/* — these ARE allowed).
#
# KNOWN LIMIT — Qt theming is version-coupled best-effort: a Qt app installed AFTER
# this bundle pulls a new KDE runtime branch with no matching KStyle.Kvantum yet;
# `sudo w-pack refresh flatpak` (idempotent) fetches it.
#
# Idempotent; best-effort. See pack-flatpak.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATSEAL_ID="com.github.tchx84.Flatseal"

command -v flatpak >/dev/null 2>&1 \
  || { warn "flatpak not installed — package step must have failed; nothing to set up."; exit 1; }

# ── Flathub remote (system-wide) ─────────────────────────────────────────────
info "Adding the Flathub remote (system-wide)..."
flatpak remote-add --if-not-exists flathub "$FLATHUB_URL" \
  || warn "could not add the Flathub remote (offline?) — re-run: sudo w-pack refresh flatpak"

# ── Kvantum QStyle engine per installed KDE runtime branch ───────────────────
# The extension is per-runtime (org.kde.KStyle.Kvantum//<branch>), so QT_STYLE_OVERRIDE=
# kvantum resolves in those sandboxes; match each org.kde.Platform branch present.
info "Installing Kvantum engine extensions (Qt brand style in the sandbox)..."
branches=$(flatpak list --runtime --columns=ref 2>/dev/null \
           | sed -n 's|^org\.kde\.Platform/[^/]*/||p' | sort -u)
if [[ -z "$branches" ]]; then
  info "No KDE runtime installed yet — the engine follows the first Qt app"
  info "  (top it up later with: sudo w-pack refresh flatpak)."
else
  while read -r br; do
    [[ -n "$br" ]] || continue
    info "Kvantum engine for org.kde.Platform//$br..."
    flatpak install -y --noninteractive flathub "org.kde.KStyle.Kvantum//$br" \
      || warn "could not install org.kde.KStyle.Kvantum//$br"
  done <<<"$branches"
fi

# ── Global W theme override (declarative: reset, then apply) ─────────────────
# This global override is W-managed and must be DECLARATIVE. `flatpak override` is
# additive and never drops keys, so an env set by an earlier version lingers;
# crucially `--unset-env` leaves `GTK_THEME=` (empty) in [Environment], and an EMPTY
# GTK_THEME is still an override that breaks GTK styling (GNOME PSA, discourse
# #35200). Reset guarantees a clean slate, then we add only what we want.
info "Applying global W theme overrides to the sandbox..."
flatpak override --system --reset || warn "override reset failed"
flatpak override --system \
  --filesystem=xdg-data/icons:ro \
  --filesystem=xdg-data/color-schemes:ro \
  --filesystem=xdg-config/gtk-3.0:ro \
  --filesystem=xdg-config/gtk-4.0:ro \
  --filesystem=xdg-config/Kvantum:ro \
  --filesystem=xdg-config/kdeglobals:ro \
  --filesystem=xdg-config/fontconfig:ro \
  --env=QT_QPA_PLATFORMTHEME=kde \
  --env=QT_STYLE_OVERRIDE=kvantum \
  || warn "could not apply the system override"
# NO GTK_THEME (the portal already reports the theme; any value, even empty, breaks
# GTK3/GTK4). QT_QPA_PLATFORMTHEME=kde drives the KDE platform theme that reads
# kdeglobals (KColorScheme + Papirus icons + [General] font); Kvantum is the widget
# engine. GTK3 itself comes from the w-style-built Gtk3theme extensions, GTK4 from
# the bound gtk-4.0 css + portal — no env needed for either.
#
# A per-app USER override (~/.local/share/flatpak/overrides/<app>, what Flatseal
# writes) SHADOWS this system one. That is the user's zone and we never touch it —
# see pack-flatpak.md for the diagnosis when one app's theme looks wrong.

# ── Flatseal (per-app permission GUI, itself a Flatpak app) ──────────────────
if flatpak info "$FLATSEAL_ID" &>/dev/null; then
  info "Flatseal already installed."
else
  info "Installing Flatseal (per-app permission GUI) from Flathub..."
  flatpak install -y --noninteractive flathub "$FLATSEAL_ID" \
    || warn "could not install Flatseal — re-run: sudo w-pack refresh flatpak"
fi

info "flatpak machine setup complete."
info "Browse/install apps: Bazaar; tune permissions: Flatseal; CLI: flatpak install flathub <app-id>."
info "Installed apps appear in the launcher after your next login (flatpak extends"
info "  XDG_DATA_DIRS from /etc/profile.d, which the session reads at login)."
exit 0
