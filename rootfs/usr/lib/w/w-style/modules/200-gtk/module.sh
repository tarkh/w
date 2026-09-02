# w-style module: gtk (user-scope) — GTK3/4 brand colors via @define-color.
# Brands general GTK apps from W_GTK_* tokens. Two delivery paths, because the
# toolkits differ on what live-reloads:
#   • GTK3 (+ plain GTK4): brand colors go into TWO twin NAMED themes,
#     ~/.local/share/themes/w-gtk/ and ~/.local/share/themes/w-gtk-alt/, each
#     @importing stock adw-gtk3 and overriding its libadwaita names. Per the
#     standard adw-gtk3 layout each theme ships BOTH gtk.css and gtk-dark.css:
#     GTK3 loads gtk-dark.css when gtk-application-prefer-dark-theme is set, else
#     gtk.css — if the requested variant file is missing it silently falls back to
#     stock Adwaita (this was the "dark theme shows stock colors" bug). The theme
#     NAME applied at startup is constant (w-gtk); light/dark is selected by
#     prefer-dark (appearance axis), not by renaming the theme. A W theme has a
#     single appearance, so all four files are identical and carry the active
#     theme's brand over the matching adw-gtk3 base — the brand is correct
#     whichever variant GTK picks. The TWIN exists only for live reload: GTK
#     re-reads a theme's CSS only when gtk-theme NAME changes, so the appearance
#     axis flips gtk-theme to whichever twin differs from the current value (one
#     guaranteed name change). Both twins are branded, so a running app can never
#     land on stock default — the previous flip-to-stock-and-back left dark
#     switches stuck on default when the return set was dropped (see the appearance
#     module). Legacy Adwaita names cover plain (non-libadwaita) GTK3.
#   • GTK4 / libadwaita: consumes our named colors natively from the user overlay
#     ~/.config/gtk-4.0/gtk.css, but ignores named themes AND does not re-read that
#     overlay on any external signal — it is read at app startup only, so running
#     libadwaita apps still need a restart for a brand change (dark/light flips
#     live via the portal regardless). Verified on VM.
# The old GTK3 user overlay (~/.config/gtk-3.0/gtk.css) is intentionally emptied:
# as a higher-priority static provider it would mask the named theme and defeat
# live recoloring. Unused color names are harmless.
# Band 200 = gtk (must precede appearance/300, which flips between the twins here).
DESC="GTK3/4 brand colors (@define-color, named themes)"

GTK3_CSS_REL=".config/gtk-3.0/gtk.css"          # GTK3/libhandy named colors (emptied overlay)
GTK4_CSS_REL=".config/gtk-4.0/gtk.css"          # GTK4/libadwaita named colors

# Map W_APPEARANCE → "prefer scheme base brand" (shared verbatim with the appearance
# module; both need `base` = the adw-gtk3 variant this theme wraps and `brand` = the
# named theme "w-gtk"). Kept per-module so each stays self-contained.
gtk_appearance_map() {
  case "${1:-dark}" in
    dark)  echo "true  prefer-dark  adw-gtk3-dark w-gtk" ;;
    light) echo "false prefer-light adw-gtk3      w-gtk" ;;
    *)     return 1 ;;
  esac
}

# ── Flatpak GTK3 delivery ─────────────────────────────────────────────────────
# Mirror the rendered GTK3 brand into self-contained flatpak Gtk3theme extensions so
# sandboxed GTK3 apps match the host. Three sandbox facts force this shape:
#   • /usr/share/themes is blacklisted, so the twin's absolute @import of the
#     adw-gtk3 base can't resolve in the sandbox → each extension must be SELF-
#     CONTAINED (the adw-gtk3 base CSS+assets + our brand appended).
#   • flatpak only mounts the Gtk3theme extension whose name equals the portal-
#     reported gtk-theme, and the appearance axis flips that between w-gtk and
#     w-gtk-alt for live host recolor → ship BOTH names (identical content).
#   • flatpak can't live-reload an extension (read at app launch), and we don't need
#     it to — but the brand must be CURRENT, so this re-runs on every gtk render.
# USER scope only: flatpak GTK3 apps run inside a user session, env-hyprland renders
# `w-style apply user` at login (before apps start), and a user-dir extension mounts
# even for system-installed apps (verified). Skipping root/skel avoids a system-vs-
# user same-name extension precedence clash. No-op without flatpak or the base theme.
# $1 = adw-gtk3 base name (appearance-correct), $2 = brand theme name (w-gtk),
# $3 = brand CSS (theme_css sans the @import line).
sync_flatpak_gtk3() {
  local base="$1" brand="$2" brand_css="$3"
  [[ $EUID -eq 0 ]] && return 0
  command -v flatpak &>/dev/null || return 0
  local basedir="/usr/share/themes/$base/gtk-3.0"
  [[ -d "$basedir" ]] || return 0
  local arch extroot t ext
  arch=$(flatpak --default-arch 2>/dev/null) || return 0
  extroot="$HOME/.local/share/flatpak/extension"
  for t in "$brand" "${brand}-alt"; do
    ext="$extroot/org.gtk.Gtk3theme.$t/$arch/3.22"
    rm -rf "$ext"
    mkdir -p "$ext"
    cp -a --reflink=auto "$basedir/." "$ext/"            # base CSS + relative assets
    printf '\n%s\n' "$brand_css" >>"$ext/gtk.css"
    printf '\n%s\n' "$brand_css" >>"$ext/gtk-dark.css"
  done
}

render_user() {
  load_conf "$(w_userscope_theme_dir)"
  echo "w-style: rendering GTK colors..."

  # adw-gtk3 base matching this theme's appearance (wrapped by both gtk variants).
  local _prefer _scheme base brand
  read -r _prefer _scheme base brand < <(gtk_appearance_map "${W_APPEARANCE:-dark}") \
    || { echo "w-style: invalid W_APPEARANCE '${W_APPEARANCE:-}' (want dark|light)" >&2; exit 1; }

  # libadwaita named colors — GTK4 native, GTK3 via adw-gtk3.
  local adw
  adw="$(cat <<EOF
@define-color window_bg_color $W_GTK_WINDOW_BG;
@define-color window_fg_color $W_GTK_WINDOW_FG;
@define-color view_bg_color $W_GTK_VIEW_BG;
@define-color view_fg_color $W_GTK_VIEW_FG;
@define-color headerbar_bg_color $W_GTK_HEADERBAR_BG;
@define-color headerbar_fg_color $W_GTK_HEADERBAR_FG;
@define-color headerbar_backdrop_color $W_GTK_HEADERBAR_BG;
@define-color sidebar_bg_color $W_GTK_HEADERBAR_BG;
@define-color sidebar_fg_color $W_GTK_HEADERBAR_FG;
@define-color card_bg_color $W_GTK_CARD_BG;
@define-color card_fg_color $W_GTK_CARD_FG;
@define-color popover_bg_color $W_GTK_CARD_BG;
@define-color popover_fg_color $W_GTK_CARD_FG;
@define-color dialog_bg_color $W_GTK_WINDOW_BG;
@define-color dialog_fg_color $W_GTK_WINDOW_FG;
@define-color accent_bg_color $W_GTK_ACCENT_BG;
@define-color accent_fg_color $W_GTK_ACCENT_FG;
@define-color accent_color $W_GTK_ACCENT_BG;
@define-color destructive_bg_color $W_GTK_DESTRUCTIVE_BG;
@define-color destructive_fg_color $W_GTK_DESTRUCTIVE_FG;
@define-color destructive_color $W_GTK_DESTRUCTIVE_BG;
@define-color borders $W_GTK_BORDER;
EOF
)"
  # Legacy Adwaita names for plain (non-libadwaita) GTK3 apps.
  local legacy
  legacy="$(cat <<EOF
@define-color theme_bg_color $W_GTK_WINDOW_BG;
@define-color theme_fg_color $W_GTK_WINDOW_FG;
@define-color theme_base_color $W_GTK_VIEW_BG;
@define-color theme_text_color $W_GTK_VIEW_FG;
@define-color theme_selected_bg_color $W_GTK_ACCENT_BG;
@define-color theme_selected_fg_color $W_GTK_ACCENT_FG;
@define-color insensitive_fg_color $W_GTK_DISABLED_FG;
EOF
)"
  local hdr="/* W Linux — generated by w-style. Do not edit; edit the theme's theme.conf. */"

  # Concept ③ — app window background translucency (effects axis). Re-define the
  # window/view/dialog background named colors with alpha so the WINDOW BACKGROUND
  # is translucent while widgets (headerbar/card/popover use their own opaque names)
  # stay solid. A later @define-color wins, so these are appended AFTER $adw/$legacy.
  # GTK4/libadwaita is reliable; GTK3 is best-effort (W_FX_APP_BG_GTK3) — only apps
  # that clear their opaque region honour CSS alpha (see config-effects.md). GTK3 also
  # needs the unfocused (:backdrop) state covered, else windows turn opaque on focus
  # loss (adw-gtk3 paints :backdrop with separate opaque theme_unfocused_* colors).
  load_effects "$(resolve_theme_file "$(w_userscope_theme_dir)" effects.conf)"
  local appbg="${W_FX_APP_BG_OPACITY:-1.0}" appbg_on=0 appbg_css="" appbg_legacy=""
  awk -v o="$appbg" 'BEGIN{exit !(o<1)}' && appbg_on=1 || true
  if [[ "$appbg_on" -eq 1 ]]; then
    # alpha() is applied to NAMED solids (the canonical GTK3+GTK4 form — more portable
    # than alpha() on a raw hex). A later @define-color wins, so these override $adw.
    appbg_css="@define-color _w_appbg_window $W_GTK_WINDOW_BG;
@define-color _w_appbg_view $W_GTK_VIEW_BG;
@define-color window_bg_color alpha(@_w_appbg_window, $appbg);
@define-color view_bg_color alpha(@_w_appbg_view, $appbg);
@define-color dialog_bg_color alpha(@_w_appbg_window, $appbg);"
    appbg_legacy="@define-color theme_bg_color alpha(@_w_appbg_window, $appbg);
@define-color theme_base_color alpha(@_w_appbg_view, $appbg);
@define-color theme_unfocused_bg_color alpha(@_w_appbg_window, $appbg);
@define-color theme_unfocused_base_color alpha(@_w_appbg_view, $appbg);"
  fi

  # GTK4 / libadwaita (native consumer; user overlay, read at app startup → not live).
  # Background translucency applies to GTK4 unconditionally (reliable).
  write_user_file "$GTK4_CSS_REL" <<EOF
$hdr
$adw
$appbg_css
EOF

  # GTK3 brand — two twin named themes "$brand" (w-gtk) and "${brand}-alt"
  # (w-gtk-alt) with identical content. The appearance axis flips gtk-theme
  # between the twins to live-recolor running apps (GTK reloads a theme only on a
  # NAME change); both twins are branded, so an app can never land on stock
  # default (see the appearance module / header). Each wraps the stock adw-gtk3
  # base and overrides its libadwaita names; legacy names cover plain GTK3 apps
  # that bypass adw-gtk3. Each ships BOTH variants GTK may request (gtk.css /
  # gtk-dark.css), identical — a W theme has one appearance.
  # GTK3 best-effort background translucency is gated: only emit alpha overrides
  # when W_FX_APP_BG_GTK3 is true (non-cooperating GTK3 apps may darken instead).
  local gtk3_appbg="" gtk3_appbg_legacy="" gtk3_appbg_rules=""
  if [[ "$appbg_on" -eq 1 && "${W_FX_APP_BG_GTK3:-false}" == "true" ]]; then
    gtk3_appbg="$appbg_css"; gtk3_appbg_legacy="$appbg_legacy"
    # The window/view named colors only frost surfaces that USE them. Toolbars,
    # menubars, sidebars (Nemo's places list) and the pathbar paint their OWN opaque
    # fill (a separate CSS node, with its own :backdrop variant), so the alpha never
    # reaches them and they'd also flip colour on focus loss. Clear that fill — in both
    # the normal AND :backdrop state — so the chrome inherits the frosted window
    # background underneath, uniform and focus-independent. Best-effort (selectors vary
    # per app); borders/contents stay intact.
    gtk3_appbg_rules="toolbar, .toolbar, .primary-toolbar, .inline-toolbar, .secondary-toolbar,
menubar, .menubar, .nemo-window .primary-toolbar, .nemo-window .menubar,
.sidebar, .sidebar .view, .sidebar treeview, .sidebar list, placessidebar, .nemo-window .sidebar,
toolbar:backdrop, .toolbar:backdrop, .primary-toolbar:backdrop, menubar:backdrop, .menubar:backdrop,
.sidebar:backdrop, .sidebar .view:backdrop, .sidebar treeview:backdrop, .sidebar list:backdrop, placessidebar:backdrop, .nemo-window .sidebar:backdrop {
  background-color: transparent;
  background-image: none;
}
/* Unfocused windows get the :backdrop state — GTK paints them with a SEPARATE
   opaque color (theme_unfocused_bg/base, overridden above). Force our frosted alpha
   in the backdrop state too, so translucency survives focus loss. Specificity is
   matched/exceeded and the rule comes after the adw-gtk3 @import, so it wins. */
window:backdrop, .background:backdrop, window.background:backdrop, .nemo-window:backdrop {
  background-color: alpha(@_w_appbg_window, $appbg);
}"
  fi
  local theme_css
  theme_css="$hdr
@import url(\"/usr/share/themes/$base/gtk-3.0/gtk.css\");
$adw
$legacy
$gtk3_appbg
$gtk3_appbg_legacy
$gtk3_appbg_rules"
  local t
  for t in "$brand" "${brand}-alt"; do
    write_user_file ".local/share/themes/$t/gtk-3.0/gtk.css"      <<<"$theme_css"
    write_user_file ".local/share/themes/$t/gtk-3.0/gtk-dark.css" <<<"$theme_css"
  done

  # Carry the same brand into the sandbox via self-contained flatpak Gtk3theme
  # extensions (both twin names). The brand CSS is theme_css minus the unresolvable
  # absolute @import; the extension inlines the adw-gtk3 base instead. See
  # sync_flatpak_gtk3.
  local brand_css="$adw
$legacy
$gtk3_appbg
$gtk3_appbg_legacy
$gtk3_appbg_rules"
  sync_flatpak_gtk3 "$base" "$brand" "$brand_css"

  # Drop the obsolete per-appearance dark theme (superseded by the w-gtk twins).
  local themes_root
  if [[ $EUID -eq 0 ]]; then themes_root="/etc/skel"; else themes_root="$HOME"; fi
  rm -rf "$themes_root/.local/share/themes/w-gtk-dark"

  # Neutralize the old GTK3 user overlay — a static, higher-priority provider would
  # mask the named theme and defeat live recoloring. Brand now comes from "$brand".
  write_user_file "$GTK3_CSS_REL" <<EOF
$hdr
/* GTK3 brand colors moved to the named theme ~/.local/share/themes/w-gtk[-dark]
   so theme switches recolor running apps live. This overlay is left empty on
   purpose — a static user gtk.css would override the named theme. */
EOF

  echo "w-style: GTK done."
}
