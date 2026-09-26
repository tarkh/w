# w-style module: flameshot (user-scope) — screenshot annotation UI theming.
# Flameshot is a Qt6 app, so its settings dialog is already themed live by the
# `qt` axis (band 400). This axis owns what the CAPTURE OVERLAY exposes through
# flameshot's own config: the UI accent, the colour the dim around the selection
# is drawn in, the annotation palette, the text-annotation font, and the handful
# of behavioural defaults that make flameshot behave like the rest of W.
#
# Unlike every other axis here this one PATCHES keys instead of rendering the
# whole file: flameshot rewrites its own ini as you work (last colour, last tool,
# button set, window geometry), so a wholesale render would throw the user's state
# away on every theme switch. Band 400 = per-app GUI config, same as `qt`.
#
# Three keys are deliberately absent, all of them w-screenshot's, all set at the
# moment of the capture because only then is the answer known:
#   savePath/savePathFixed — this render lands in /etc/skel as root at install
#     time, where the target user's $HOME (and therefore their PICTURES folder,
#     whose name follows the system language) is unknown.
#   showHelp — it depends on the capture MODE, not on the theme: the cheat-sheet
#     is centred on the monitor and would land on the toolbar of a preselected
#     window, so w-screenshot turns it off for that one mode.
#
# NOT live in the useful sense: flameshot does watch this file, but no overlay is
# open while the theme changes, so this applies to the next capture.
DESC="flameshot screenshot overlay palette/font"

FLAMESHOT_CONFIG_REL=".config/flameshot/flameshot.ini"

# Set <key>=<value> under [General], preserving every other key. Scope-aware:
# $HOME for a user, /etc/skel as root. The same shape as core.sh's patch_gtk_key,
# kept module-local because [General] is flameshot's section, not a generic one —
# and w-screenshot carries the same helper for the keys it owns.
patch_flameshot_key() {
  local key="$1" value="$2" target
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$FLAMESHOT_CONFIG_REL"
  else target="$HOME/$FLAMESHOT_CONFIG_REL"; fi

  if [[ ! -f "$target" ]]; then
    install -Dm644 /dev/stdin "$target" <<EOF
[General]
$key=$value
EOF
    return
  fi
  if grep -q "^$key=" "$target"; then
    sed -i "s|^$key=.*|$key=$value|" "$target"
  elif grep -q '^\[General\]' "$target"; then
    sed -i "0,/^\[General\]/s||[General]\n$key=$value|" "$target"
  else
    printf '[General]\n%s=%s\n' "$key" "$value" >>"$target"
  fi
}

render_user() {
  local theme_dir; theme_dir="$(w_userscope_theme_dir)"
  load_conf "$theme_dir"
  load_font "$(resolve_theme_file "$theme_dir" font.conf)"
  echo "w-style: rendering flameshot config..."

  # Interface. uiColor paints the toolbar accent and the selection handles;
  # contrastUiColor is what the area OUTSIDE the selection is dimmed with, so it
  # has to be the theme's surface — a fixed dark tint would fight a light theme.
  patch_flameshot_key uiColor         "$W_PRIMARY"
  patch_flameshot_key contrastUiColor "$W_SURFACE"
  patch_flameshot_key fontFamily      "$W_FONT_UI"

  # Annotation colours: the brand accent is the default pen, the rest are the
  # theme's ANSI brights (bright, mutually distinct, and already tuned per theme),
  # `picker` keeps flameshot's own colour wheel at the end for anything else.
  # QSettings reads an unquoted comma-separated value back as a list.
  patch_flameshot_key drawColor  "$W_PRIMARY"
  patch_flameshot_key userColors "$W_PRIMARY, $W_TERM_ANSI_BRIGHT_RED, $W_TERM_ANSI_BRIGHT_YELLOW, $W_TERM_ANSI_BRIGHT_GREEN, $W_TERM_ANSI_BRIGHT_BLUE, $W_TERM_ANSI_BRIGHT_MAGENTA, $W_TERM_ANSI_BRIGHT_CYAN, $W_ON_SURFACE, picker"

  # Behaviour, the same role satty's [general] block plays in the 400-satty axis.
  # The filename matches w-screenshot's own --save pattern (strftime, as flameshot
  # parses it), so a capture is named identically whichever path produced it. No
  # tray icon and no autostart: W has no place for a second tray resident, and
  # every capture here is a one-shot CLI invocation. The abort notification is off
  # because pressing Esc is a decision, not an event worth a popup.
  patch_flameshot_key filenamePattern        "W-%Y-%m-%d_%H-%M-%S"
  patch_flameshot_key saveAsFileExtension    "png"
  patch_flameshot_key disabledTrayIcon       "true"
  patch_flameshot_key startupLaunch          "false"
  patch_flameshot_key showAbortNotification  "false"

  echo "w-style: flameshot done (applies to the next capture)."
}
