# w-style module: qt (user-scope) — Qt5 (qt5ct) + Qt6 (qt6ct) + KDE/KF apps.
# Makes both Qt toolkits full theme citizens off ONE set of brand tokens, via the
# matching pair of official platform themes. QT_QPA_PLATFORMTHEME is a colon-list
# "qt5ct:qt6ct" (env-hyprland): Qt loads the entry built for the running version —
# Qt5 → qt5ct, Qt6 → qt6ct (each ct backend builds only for its own Qt and is
# cleanly skipped by the other, so the list falls through to the match). Both
# backends share one config format, so we render them with the same helper into
# ~/.config/{qt5ct,qt6ct}/: a 21-role QPalette colour scheme + a conf with the
# theme's widget engine (W_QT_STYLE: Fusion or kvantum — see below), font axis
# (W_FONT_*) and the icon theme (icon_theme = Papirus-Dark, a REAL theme — Qt's
# icon loader needs a concrete theme, not an inheritance-only meta-theme; see
# config-icons.md). color_scheme_path is absolute and scope-aware: the login render
# fixes $HOME before any Qt app starts (same model as font/appearance). LIVE (~3s,
# qt5ct/qt6ct only): each plugin runs a QFileSystemWatcher on its config DIRECTORY
# and, on a dir-entry change, re-reads after a 3s debounce. We write the *ct.conf
# via atomic rename (write_user_file_atomic) so that watcher fires; Fusion then
# re-applies the QPalette, and Kvantum's proxy style re-parses the SVG via the
# twin-name flip (see write_ct_config). The 3s debounce is hard-coded in the plugin;
# a faster apply would need a patched qt6ct build (documented future option in
# config-qt.md).
#
# Also covers KDE/KF apps (Dolphin, Ark, …): plain Qt apps (qbittorrent, vlc,
# pcmanfm-qt) take the qt6ct QPalette, but KF apps build their palette via
# KColorSchemeManager, which loads the .colors FILE named in kdeglobals
# [UiSettings] ColorScheme. So we render a brand W.colors scheme (write_color_scheme)
# and select it in kdeglobals (write_kdeglobals). The qt axis owns both files
# wholesale (incl. [Icons] theme), so they stay correct on every theme switch (the
# icons axis no longer touches kdeglobals).
#
# (Replaced the former hyprqt6engine AUR engine: as a KDE platform theme it set the
# KDE_COLOR_SCHEME_PATH hint so KColorSchemeManager kept the brand palette — but it
# wasn't picked up as a non-first colon-list entry, so it couldn't share one global
# var with qt5ct. qt6ct + qt5ct do, ship in the official repo; we drive KDE apps
# natively via the W.colors scheme instead of a KDE platform theme / qt6ct-kde.)
#
# Widget engine is per-theme (W_QT_STYLE = fusion | kvantum). Both renders are
# always emitted — the Fusion QPalette above AND a Kvantum theme (write_kvantum_
# config) coloured from the same W_QT_* tokens — and the *ct.conf style= line is
# the only switch. Because both Qt versions read their own *ct.conf (colon-list
# env), the flag governs Qt5 and Qt6 alike; we deliberately do NOT set a global
# QT_STYLE_OVERRIDE, which would pin one engine and defeat the flag.
# Band 400 = toolkit palettes.
DESC="Qt5/Qt6 (qt5ct+qt6ct) + KDE/KF colour scheme"

QT5CT_CONF_REL=".config/qt5ct/qt5ct.conf"       # Qt5 config (qt5ct backend)
QT5CT_COLORS_REL=".config/qt5ct/colors/w.conf"  # Qt5 palette (qt5ct backend)
QT6CT_CONF_REL=".config/qt6ct/qt6ct.conf"       # Qt6 config (qt6ct backend)
QT6CT_COLORS_REL=".config/qt6ct/colors/w.conf"  # Qt6 palette (qt6ct backend)
KDEGLOBALS_REL=".config/kdeglobals"             # KColorScheme + KDE icon theme
COLOR_SCHEME_REL=".local/share/color-schemes/W.colors"  # KDE scheme file
KVANTUM_CONF_REL=".config/Kvantum/kvantum.kvconfig"     # active Kvantum theme pointer
KVANTUM_THEME_REL=".config/Kvantum/w/w.kvconfig"        # the W Kvantum theme (colours)
KVANTUM_SVG_REL=".config/Kvantum/w/w.svg"               # the W Kvantum theme (SVG shapes)
KVANTUM_COLORS_REL=".config/Kvantum/w/w.colors"         # the W Kvantum theme (KDE scheme, for Kvantum Manager)
KVANTUM_DARK_THEME_REL=".config/Kvantum/w/wDark.kvconfig"  # dark twin — identical copy of w.kvconfig (live update; see write_kvantum_config)
KVANTUM_DARK_SVG_REL=".config/Kvantum/w/wDark.svg"         # dark twin — identical copy of w.svg

# Concept ③ helper — translate W_FX_APP_BG_OPACITY (0..1) into Kvantum's
# reduce_window_opacity (0..90 integer; the % the window bg is dimmed). Echoes
# "<translucent_windows> <reduce_window_opacity>" for the caller. Loads the
# active theme's effects.conf first.
effects_kvantum_appbg() {
  local theme_dir="$1" o ro tw
  load_effects "$(resolve_theme_file "$theme_dir" effects.conf)"
  o="${W_FX_APP_BG_OPACITY:-1.0}"
  ro=$(awk -v o="$o" 'BEGIN{r=int((1-o)*100+0.5); if(r<0)r=0; if(r>90)r=90; print r}')
  [[ "${ro:-0}" -gt 0 ]] && tw=true || tw=false
  echo "$tw $ro"
}

# qt5ct/qt6ct want opaque ARGB "#ffRRGGBB"; prepend full-opacity alpha to #rrggbb.
qt5ct_argb() { echo "#ff${1#\#}"; }

# kdeglobals (KColorScheme) wants decimal "R,G,B"; convert #rrggbb.
kde_rgb() { local h="${1#\#}"; printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }

# Emit one qt5ct/qt6ct palette line — a comma-separated list of 21 ARGB colors in
# QPalette::ColorRole order (WindowText..PlaceholderText). $1=1 dims the text
# roles for the `disabled` set; 0 uses the real brand foregrounds (active/inactive).
#
# The list is POSITIONAL: both backends assign entry i to role i, so an extra or
# missing entry silently shifts every role after it (an off-by-one here once put
# black in Window and Highlight, invisible under Kvantum). Count and order are
# therefore gated by tests/qt.bats against the role names in the comments below.
# Qt6 has a 22nd role (Accent, added in 6.6); we deliberately do NOT emit it —
# left unset, QPalette derives Accent from Highlight, which is already the brand
# selection colour, and a 22-entry list would be wrong for Qt5's 21 roles.
qt5ct_palette() {
  local wt tx bt bx
  if [[ "$1" -eq 1 ]]; then
    wt="$W_QT_INACTIVE"; tx="$W_QT_INACTIVE"; bt="$W_QT_INACTIVE"; bx="$W_QT_INACTIVE"
  else
    wt="$W_QT_WINDOW_FG"; tx="$W_QT_VIEW_FG"; bt="$W_QT_BUTTON_FG"; bx="#ffffff"
  fi
  local roles=(
    "$wt"                 # WindowText
    "$W_QT_BUTTON_BG"     # Button
    "$W_QT_BUTTON_BG"     # Light
    "$W_QT_BUTTON_BG"     # Midlight
    "$W_QT_WINDOW_BG"     # Dark
    "$W_QT_WINDOW_BG"     # Mid
    "$tx"                 # Text
    "$bx"                 # BrightText
    "$bt"                 # ButtonText
    "$W_QT_VIEW_BG"       # Base
    "$W_QT_WINDOW_BG"     # Window
    "#000000"             # Shadow
    "$W_QT_SELECTION_BG"  # Highlight
    "$W_QT_SELECTION_FG"  # HighlightedText
    "$W_QT_ACCENT"        # Link
    "$W_QT_INACTIVE"      # LinkVisited
    "$W_QT_WINDOW_BG"     # AlternateBase
    "$W_QT_WINDOW_BG"     # NoRole
    "$W_QT_TOOLTIP_BG"    # ToolTipBase
    "$W_QT_TOOLTIP_FG"    # ToolTipText
    "$W_QT_INACTIVE"      # PlaceholderText
  )
  local out="" r
  for r in "${roles[@]}"; do out+="$(qt5ct_argb "$r"), "; done
  echo "${out%, }"
}

# Render one *ct backend (qt5ct or qt6ct — identical config format). $1 = conf
# relative path, $2 = palette relative path, $3 = absolute palette path for this
# scope, $4 = widget engine (fusion or kvantum). Palette: brand colors as a 21-role
# QPalette list (active/inactive/disabled sets) — used by Fusion and as Kvantum's
# fallback. Config: the resolved style + the icon theme + the font axis in Qt's
# readable QFont descriptor "family,ptSize,-1,5,50,0,0,0,0,0".
#
# Live update: the conf is written via atomic rename so qt5ct/qt6ct's directory
# watcher fires (see write_user_file_atomic). Fusion then re-applies the palette
# in-place. Kvantum is a QStyle whose qt6ct proxy re-parses the SVG ONLY when the
# style NAME changes, so in a live USER session we alternate the name between the
# twin keys "kvantum" and "kvantum-dark" (both render the single W Kvantum theme,
# visually identical for our dark theme — cf. the GTK w-gtk twins). At root/skel
# time we keep the canonical "kvantum" so the shipped template is deterministic.
write_ct_config() {
  local conf_rel="$1" colors_rel="$2" colors_abs="$3" engine="$4" style cur
  if [[ "$engine" == kvantum ]]; then
    style="kvantum"
    if [[ $EUID -ne 0 ]]; then
      # `|| true`: on first login qt?ct.conf does not exist yet → `sed` fails →
      # `pipefail` makes this bare assignment non-zero → `set -e` would silently
      # abort the whole user render mid-`qt` (killing icons/shell/btop). Empty `cur`
      # is the correct first-run value (style stays "kvantum").
      cur="$(sed -n 's/^style=//p' "$HOME/$conf_rel" 2>/dev/null | head -1)" || true
      [[ "$cur" == kvantum ]] && style="kvantum-dark"
    fi
  else
    style="Fusion"
  fi
  {
    echo "# W Linux — generated by w-style. Do not edit; edit the theme's theme.conf."
    echo "[ColorScheme]"
    echo "active_colors=$(qt5ct_palette 0)"
    echo "disabled_colors=$(qt5ct_palette 1)"
    echo "inactive_colors=$(qt5ct_palette 0)"
  } | write_user_file "$colors_rel"

  write_user_file_atomic "$conf_rel" <<EOF
# W Linux — generated by w-style. Do not edit; edit the theme's theme.conf/font.conf.
[Appearance]
custom_palette=true
color_scheme_path=$colors_abs
icon_theme=$W_ICON_THEME
standard_dialogs=default
style=$style

[Fonts]
fixed="$W_FONT_MONO,$W_FONT_MONO_SIZE,-1,5,50,0,0,0,0,0"
general="$W_FONT_UI,$W_FONT_UI_SIZE,-1,5,50,0,0,0,0,0"
EOF
}

# Emit one kdeglobals [Colors:<set>] section from a bg/altbg/fg triple. The shared
# foreground roles (inactive/link/negative/decoration) come from the brand accent +
# inactive + negative tokens, identical across sets. $1=set, $2=bg, $3=altbg, $4=fg.
kde_color_set() {
  cat <<EOF

[Colors:$1]
BackgroundNormal=$2
BackgroundAlternate=$3
ForegroundNormal=$4
ForegroundInactive=$W_KDE_INACTIVE
ForegroundActive=$W_KDE_ACCENT
ForegroundLink=$W_KDE_ACCENT
ForegroundVisited=$W_KDE_INACTIVE
ForegroundNegative=$W_KDE_NEGATIVE
ForegroundNeutral=$W_KDE_ACCENT
ForegroundPositive=$4
DecorationFocus=$W_KDE_ACCENT
DecorationHover=$W_KDE_ACCENT
EOF
}

# Emit the six brand [Colors:*] sections (shared by kdeglobals and the W.colors
# scheme file). Sets the W_KDE_* shared-role locals first; kde_color_set reads them
# via bash dynamic scope. Reads W_QT_* from the loaded theme.
emit_kde_color_sections() {
  local W_KDE_ACCENT W_KDE_NEGATIVE W_KDE_INACTIVE win view btn sel tip
  W_KDE_ACCENT=$(kde_rgb "$W_QT_ACCENT")
  W_KDE_NEGATIVE=$(kde_rgb "$W_QT_NEGATIVE")
  W_KDE_INACTIVE=$(kde_rgb "$W_QT_INACTIVE")
  win=$(kde_rgb "$W_QT_WINDOW_BG");    view=$(kde_rgb "$W_QT_VIEW_BG")
  btn=$(kde_rgb "$W_QT_BUTTON_BG");    sel=$(kde_rgb "$W_QT_SELECTION_BG")
  tip=$(kde_rgb "$W_QT_TOOLTIP_BG")
  kde_color_set Window        "$win"  "$btn"  "$(kde_rgb "$W_QT_WINDOW_FG")"
  kde_color_set View          "$view" "$win"  "$(kde_rgb "$W_QT_VIEW_FG")"
  kde_color_set Button        "$btn"  "$win"  "$(kde_rgb "$W_QT_BUTTON_FG")"
  kde_color_set Selection     "$sel"  "$sel"  "$(kde_rgb "$W_QT_SELECTION_FG")"
  kde_color_set Tooltip       "$tip"  "$win"  "$(kde_rgb "$W_QT_TOOLTIP_FG")"
  kde_color_set Complementary "$win"  "$btn"  "$(kde_rgb "$W_QT_WINDOW_FG")"
}

# Render the KDE colour scheme for KF apps (Dolphin, Ark, …). KF apps build their
# palette via KColorSchemeManager, whose init() applies the scheme named in
# kdeglobals [UiSettings] ColorScheme by loading its .colors FILE — it does NOT read
# kdeglobals [Colors:*], and without a named scheme + no KDE platform-theme hint
# (KDE_COLOR_SCHEME_PATH, which qt6ct doesn't set) it falls back to built-in Breeze
# (light). So we ship BOTH:
#   • W.colors — the brand scheme file (~/.local/share/color-schemes/, XDG-scanned);
#   • kdeglobals [UiSettings] ColorScheme=W — selects it (the key the manager reads).
# kdeglobals also keeps [Colors:*] (consumed by the KColorScheme class directly) and
# [Icons] Theme (the one place KDE apps read the icon theme). The qt axis owns both
# files wholesale. Plain Qt apps (no KColorSchemeManager) keep the qt6ct QPalette.
write_color_scheme() {
  {
    echo "# W Linux — generated by w-style. Do not edit; edit the theme's theme.conf."
    echo "[General]"
    echo "Name=W"
    echo ""
    echo "[KDE]"
    echo "contrast=4"
    emit_kde_color_sections
    echo ""
    echo "[WM]"
    echo "activeBackground=$(kde_rgb "$W_QT_BUTTON_BG")"
    echo "activeForeground=$(kde_rgb "$W_QT_WINDOW_FG")"
    echo "inactiveBackground=$(kde_rgb "$W_QT_WINDOW_BG")"
    echo "inactiveForeground=$(kde_rgb "$W_QT_INACTIVE")"
  } | write_user_file "$COLOR_SCHEME_REL"
}

write_kdeglobals() {
  {
    echo "# W Linux — generated by w-style. Do not edit; edit the theme's theme.conf."
    echo "# Selects the W scheme for KColorSchemeManager (KDE apps) + the icon theme."
    # [General] fonts: read by the KDE platform theme (KDEPlasmaPlatformTheme), the
    # ONLY font channel Qt apps get inside a Flatpak sandbox (qt5ct/qt6ct don't load
    # there). KDE has SEPARATE QFont roles — `font` (general/body), `fixed`, `menuFont`,
    # `toolBarFont`, `smallestReadableFont` (+ [WM] activeFont). qt6ct only carries
    # general+fixed and lets Qt fall back to the general font for menu/toolbar, so on the
    # host those match the body. KDEPlasmaPlatformTheme instead returns its OWN (smaller)
    # defaults for any role we leave unset → in the sandbox the menu bar + toolbar font
    # came out smaller than the body. We therefore pin EVERY role to the UI font so the
    # sandbox is uniform. Same QFont descriptor write_ct_config uses; see config-qt.md.
    local ui="$W_FONT_UI,$W_FONT_UI_SIZE,-1,5,50,0,0,0,0,0"
    local small_sz=$(( W_FONT_UI_SIZE > 9 ? W_FONT_UI_SIZE - 2 : W_FONT_UI_SIZE ))
    echo "[General]"
    echo "font=$ui"
    echo "fixed=$W_FONT_MONO,$W_FONT_MONO_SIZE,-1,5,50,0,0,0,0,0"
    echo "menuFont=$ui"
    echo "toolBarFont=$ui"
    echo "smallestReadableFont=$W_FONT_UI,$small_sz,-1,5,50,0,0,0,0,0"
    echo ""
    echo "[WM]"
    echo "activeFont=$ui"
    echo ""
    # Toolbar buttons: KDE defaults to TextBesideIcon (labels next to icons), whereas
    # the host (Qt default via qt6ct) shows icons only. Pin NoText so sandbox toolbars
    # match the icon-forward host look.
    echo "[Toolbar style]"
    echo "ToolButtonStyle=NoText"
    echo "ToolButtonStyleOtherToolbars=NoText"
    echo ""
    echo "[UiSettings]"
    echo "ColorScheme=W"
    echo ""
    echo "[Icons]"
    echo "Theme=$W_ICON_THEME"
    emit_kde_color_sections
  } | write_user_file "$KDEGLOBALS_REL"
}

# Render the Kvantum theme "w" — the SVG widget engine, an alternative to Fusion
# (selected per theme by W_QT_STYLE). Kvantum is a Qt STYLE, picked via style= in
# the *ct.conf above; it reads its own theme from ~/.config/Kvantum/w/. Three files:
#   • kvantum.kvconfig — points Kvantum at the active theme (theme=w);
#   • w/w.kvconfig     — the config: COPIED from the active theme's curated base
#     (themes/<t>/kvantum/default.kvconfig — geometry, [Hacks], behaviour) with its
#     colour keys re-tokenised per kvconfig-map.conf;
#   • w/w.svg          — the SVG shapes: COPIED from default.svg with every brand
#     hex re-tokenised per svg-map.conf (Kvantum draws much of the chrome from SVG,
#     so the shapes carry their own colours — themed here too);
#   • w/w.colors       — the KDE colour scheme: COPIED from default.colors with its
#     brand RGB roles re-tokenised per colors-map.conf. Not read for drawing (kvconfig
#     + svg do that); shipped so Kvantum Manager recognises the theme (docs convention).
# Nothing is hardcoded in w-style: both maps name W_QT_* tokens; colours come from
# the SAME tokens as the Fusion palette, so all engines track the theme identically.
# The base default.kvconfig/default.svg fall back to baseline `w` (resolve_theme_file)
# for themes that ship no kvantum/ dir. All files render every time, so flipping
# W_QT_STYLE needs no extra work — the *ct.conf style= line is the only switch.
# NOT live (read at Qt app startup).
#
# $1 = active theme directory (already resolved by the caller).
write_kvantum_config() {
  local theme_dir="$1"
  local base_kvconfig base_svg base_colors map_kvconfig map_svg map_colors
  base_kvconfig="$(resolve_theme_file "$theme_dir" kvantum/default.kvconfig)"
  base_svg="$(resolve_theme_file "$theme_dir" kvantum/default.svg)"
  base_colors="$(resolve_theme_file "$theme_dir" kvantum/default.colors)"
  map_kvconfig="$(resolve_theme_file "$theme_dir" kvantum/kvconfig-map.conf)"
  map_svg="$(resolve_theme_file "$theme_dir" kvantum/svg-map.conf)"
  map_colors="$(resolve_theme_file "$theme_dir" kvantum/colors-map.conf)"

  write_user_file "$KVANTUM_CONF_REL" <<EOF
# W Linux — generated by w-style. Do not edit; edit the theme's theme.conf.
[General]
theme=w
EOF

  # The qt6ct proxy re-creates the Kvantum QStyle only when the style NAME changes,
  # so live updates flip between the "kvantum" and "kvantum-dark" plugin keys (see
  # write_ct_config). "kvantum-dark" = Style(useDark=true), which makes Kvantum look
  # for a dark variant "wDark" first; without it the two keys differ only by the
  # useDark flag — an asymmetry that breaks live recolour of palette-driven surfaces
  # (window/base). We therefore ship wDark as a byte-identical twin of w so both keys
  # render the same theme. Kvantum has no file watcher (it re-reads on construction,
  # i.e. on the flip), so an in-place write_user_file refresh is enough — no atomic
  # rename needed here. Render each artifact once, then write the main + dark copy.
  local kvconfig svg
  kvconfig="$(render_ini_from_map "$base_kvconfig" "$map_kvconfig")"
  svg="$(render_svg_from_map "$base_svg" "$map_svg")"

  # Concept ③ — app window background translucency (effects axis). Patch the
  # [General] translucent_windows + reduce_window_opacity from W_FX_APP_BG_OPACITY
  # so the SAME effects.conf knob drives Kvantum (bg translucent, widgets opaque).
  # The baseline kvconfig always carries both keys, so a value swap is enough.
  local fx_tw fx_ro
  read -r fx_tw fx_ro < <(effects_kvantum_appbg "$theme_dir")
  kvconfig="$(printf '%s\n' "$kvconfig" | sed -E "s/^translucent_windows=.*/translucent_windows=${fx_tw}/; s/^reduce_window_opacity=.*/reduce_window_opacity=${fx_ro}/")"
  printf '%s\n' "$kvconfig" | write_user_file "$KVANTUM_THEME_REL"
  printf '%s\n' "$kvconfig" | write_user_file "$KVANTUM_DARK_THEME_REL"
  printf '%s\n' "$svg"      | write_user_file "$KVANTUM_SVG_REL"
  printf '%s\n' "$svg"      | write_user_file "$KVANTUM_DARK_SVG_REL"
  render_ini_from_map "$base_colors" "$map_colors" rgb      | write_user_file "$KVANTUM_COLORS_REL"
}

# Re-tokenise a curated INI file (Kvantum .kvconfig or KDE .colors): stream the base
# and, for any `key=value` whose [Section]+key is named in the map, replace the value
# with the resolved W_QT_* token; everything else (geometry, [Hacks], inherits=…, and
# unmapped keys like KDE's fixed semantic accents) passes through verbatim. The map
# mirrors the INI structure — section-scoped keys so a repeated key (text.focus.color,
# or ForegroundNormal across [Colors:*]) resolves differently per section.
# $1 = base path, $2 = map path, $3 = value format: "" → raw hex (#rrggbb, kvconfig),
# "rgb" → decimal "R,G,B" via kde_rgb (.colors). Emits the result on stdout.
render_ini_from_map() {
  local base="$1" map="$2" fmt="${3:-}"
  declare -A kvmap
  local section="" line key val token
  # Load the map: "[Section]" headers + "key=TOKEN" entries (inline #comments ok).
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" =~ ^\[(.+)\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"; continue
    fi
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; val="${line#*=}"
    val="${val%%#*}"                       # strip inline comment
    token="${val//[[:space:]]/}"           # token is a single word
    [[ -n "$token" ]] && kvmap["$section|$key"]="$token"
  done < "$map"

  echo "# W Linux — generated by w-style. Do not edit; edit the theme's theme.conf."
  section=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\[(.+)\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"; printf '%s\n' "$line"; continue
    fi
    if [[ "$line" == *=* ]]; then
      key="${line%%=*}"; token="${kvmap["$section|$key"]:-}"
      if [[ -n "$token" ]]; then
        if [[ "$fmt" == rgb ]]; then printf '%s=%s\n' "$key" "$(kde_rgb "${!token}")"
        else printf '%s=%s\n' "$key" "${!token}"; fi
        continue
      fi
    fi
    printf '%s\n' "$line"
  done < "$base"
}

# Re-tokenise a Kvantum SVG: replace every source hex listed in the map with the
# resolved W_QT_* token's colour. Map lines are "TOKEN=#h1,#h2,…" — one W_QT_* token
# per line, listing the neutral source hexes it should repaint. The `#` prefix and a
# trailing word boundary keep replacements from touching gradient IDs or longer hexes.
# $1 = base .svg path, $2 = svg-map.conf path. Emits the result on stdout.
render_svg_from_map() {
  local base="$1" map="$2"
  local line token hexes hex sed_args=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *=* ]] && continue
    token="${line%%=*}"; token="${token//[[:space:]]/}"
    hexes="${line#*=}"; hexes="${hexes%%#[[:space:]]*}"   # keep #hex, drop trailing comment
    [[ -z "${!token:-}" ]] && continue
    IFS=',' read -ra arr <<< "$hexes"
    for hex in "${arr[@]}"; do
      hex="${hex//[[:space:]]/}"
      [[ -z "$hex" ]] && continue
      sed_args+=(-e "s/${hex}\\b/${!token}/Ig")
    done
  done < "$map"
  sed "${sed_args[@]}" "$base"
}

render_user() {
  local theme_dir; theme_dir="$(w_userscope_theme_dir)"
  load_conf "$theme_dir"
  load_font "$(resolve_theme_file "$theme_dir" font.conf)"
  echo "w-style: rendering Qt (Qt5 qt5ct + Qt6 qt6ct)..."

  local home_dir
  if [[ $EUID -eq 0 ]]; then home_dir="/etc/skel"; else home_dir="$HOME"; fi

  # Per-theme widget engine: normalise W_QT_STYLE to an engine token (fusion is the
  # safe fallback for older themes that predate the token). write_ct_config resolves
  # the concrete style= line (and, for kvantum, the live twin-name flip).
  local qt_engine
  case "${W_QT_STYLE,,}" in
    kvantum) qt_engine="kvantum" ;;
    *)       qt_engine="fusion" ;;
  esac

  write_ct_config "$QT5CT_CONF_REL" "$QT5CT_COLORS_REL" "$home_dir/$QT5CT_COLORS_REL" "$qt_engine"
  write_ct_config "$QT6CT_CONF_REL" "$QT6CT_COLORS_REL" "$home_dir/$QT6CT_COLORS_REL" "$qt_engine"
  write_color_scheme
  write_kdeglobals
  write_kvantum_config "$theme_dir"

  echo "w-style: Qt done (engine=$qt_engine)."
}
