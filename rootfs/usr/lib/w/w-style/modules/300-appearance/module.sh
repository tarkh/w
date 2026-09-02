# w-style module: appearance / color-scheme (user-scope).
# Propagates the theme's light/dark preference (W_APPEARANCE) so GTK apps and —
# via the XDG appearance portal (xdg-desktop-portal-gtk reading gsettings) — web
# browsers and Electron apps honour prefers-color-scheme. Channels:
#   • GTK3/4 settings.ini  → gtk-application-prefer-dark-theme (app startup default)
#   • GTK3 settings.ini    → gtk-theme-name = our brand theme w-gtk (constant name)
#   • gsettings color-scheme → org.freedesktop.appearance portal (live, for running
#                              GTK/web/Electron); only in a live user dbus session.
#   • gsettings gtk-theme  → live brand recolor of running GTK3/plain-GTK4 apps
#                            via a flip-and-back toggle (see below).
# settings.ini may also hold icon-theme/font, so only the dark-theme KEY is
# patched in place (other keys preserved); the file is created if absent.
# Band 300 = appearance (runs after gtk/200, which writes the w-gtk twins it flips).
DESC="light/dark preference + portal color-scheme + GTK theme flip"

GTK3_SETTINGS_REL=".config/gtk-3.0/settings.ini"
GTK4_SETTINGS_REL=".config/gtk-4.0/settings.ini"

# Map W_APPEARANCE → "prefer scheme base brand" (shared verbatim with the gtk
# module; kept per-module so each stays self-contained). prefer =
# gtk-application-prefer-dark-theme · scheme = portal color-scheme · base = stock
# adw-gtk3 variant the brand wraps · brand = our named GTK3 theme, ALWAYS "w-gtk".
gtk_appearance_map() {
  case "${1:-dark}" in
    dark)  echo "true  prefer-dark  adw-gtk3-dark w-gtk" ;;
    light) echo "false prefer-light adw-gtk3      w-gtk" ;;
    *)     return 1 ;;
  esac
}

render_user() {
  load_conf "$(w_userscope_theme_dir)"
  local mode="${W_APPEARANCE:-dark}"
  echo "w-style: rendering appearance ($mode)..."

  local prefer scheme base brand
  read -r prefer scheme base brand < <(gtk_appearance_map "$mode") \
    || { echo "w-style: invalid W_APPEARANCE '$mode' (want dark|light)" >&2; exit 1; }

  patch_gtk_key "$GTK3_SETTINGS_REL" gtk-application-prefer-dark-theme "$prefer"
  patch_gtk_key "$GTK4_SETTINGS_REL" gtk-application-prefer-dark-theme "$prefer"
  # GTK3 loads our brand-carrying named theme w-gtk (constant name; it ships both
  # gtk.css and gtk-dark.css — see the gtk module). prefer-dark picks the variant;
  # the name never changes. GTK4 stays on native libadwaita (no gtk-theme-name).
  patch_gtk_key "$GTK3_SETTINGS_REL" gtk-theme-name "$brand"

  # Live channel for running GTK/web/Electron via the appearance portal. Needs a
  # user dbus session + gsettings schemas; skip silently at root/install time.
  if [[ $EUID -ne 0 ]] && command -v gsettings &>/dev/null \
       && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    local iface="org.gnome.desktop.interface"
    local gs="gsettings set $iface"
    $gs color-scheme "$scheme" 2>/dev/null || true
    # Live-recolor running GTK3/plain-GTK4 apps. Brand colors live in the twin
    # named themes w-gtk / w-gtk-alt (identical, both branded — see the gtk module).
    # GTK re-reads a theme's CSS only when gtk-theme NAME changes (same-name
    # rewrites are ignored), so flip to whichever twin differs from the current
    # value — one guaranteed name change forces a fresh read of the just-regenerated
    # brand. Both targets are branded, so a running app never lands on stock default
    # (the old flip-to-stock-and-back left dark switches stuck on default). Works
    # for any number of themes, including switches between same-appearance themes
    # where color-scheme does not change. libadwaita GTK4 ignores named themes
    # (brand via gtk-4.0/gtk.css, read at startup) → those still need a restart.
    local cur target
    # `|| true`: if the gschema is absent `gsettings` fails → pipefail+set -e would
    # abort the appearance axis. Empty `cur` just means "no current theme" (→ flips
    # to $brand), which is the right fallback.
    cur=$(gsettings get "$iface" gtk-theme 2>/dev/null | tr -d "'\"") || true
    if [[ "$cur" == "$brand" ]]; then target="${brand}-alt"; else target="$brand"; fi
    $gs gtk-theme "$target" 2>/dev/null || true
  fi

  echo "w-style: appearance done."
}
