# w-style module: audacity (user-scope) — Audacity light/dark theme.
#
# Ships INSIDE the audio W-Pack (source of truth); `w-pack install audio` drops
# this axis into the w-style modules.d drop-in root, `w-pack remove` takes it
# back (packs.md "bundle self-containment", pack-audio.md).
#
# Audacity 3.x is wxGTK3, but only its dialogs are GTK — the main window paints
# from Audacity's own theme set, chosen by one key: audacity.cfg [GUI]
# Theme=light|dark|high-contrast|classic|custom (lib-theme GUITheme(), default
# "light"). A W palette cannot be poured into it (a custom theme is a packed
# image atlas, not colours), so the axis does the one honest thing: it follows
# W's appearance — dark W theme, dark Audacity; light, light.
#
# Ownership: only light ↔ dark is W's. A theme the user picked themselves
# (high-contrast, classic, custom) is left alone, the same three-state rule the
# graphics bundle applies to Krita's theme key. Audacity rewrites audacity.cfg
# on exit from memory, so a switch made while it runs is undone when it quits
# and comes back at the next render — not live, read at start.
DESC="Audacity light/dark theme (follows the W appearance)"

AUDACITY_CFG_REL=".config/audacity/audacity.cfg"

render_user() {
  local theme_dir want target current
  theme_dir="$(w_userscope_theme_dir)"
  load_conf "$theme_dir"
  [[ "$W_APPEARANCE" == light ]] && want=light || want=dark
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$AUDACITY_CFG_REL"; else target="$HOME/$AUDACITY_CFG_REL"; fi

  if [[ -f "$target" ]]; then
    current="$(awk '/^\[/{s=($0=="[GUI]")} s && /^Theme=/{sub(/^Theme=/,""); print; exit}' "$target")"
    case "$current" in
      "$want") echo "w-style: audacity — theme already $want."; return 0 ;;
      ""|light|dark) ;;
      *) echo "w-style: audacity — user theme '$current' kept."; return 0 ;;
    esac
    # Set the key inside [GUI] (replace or add), or append the section.
    awk -v want="$want" '
      /^\[/ { if (gui && !done) { print "Theme=" want; done = 1 } gui = ($0 == "[GUI]") }
      gui && /^Theme=/ { print "Theme=" want; done = 1; next }
      { print }
      END { if (!done) { if (!gui) print "[GUI]"; print "Theme=" want } }
    ' "$target" | write_user_file "$AUDACITY_CFG_REL"
  else
    printf '[GUI]\nTheme=%s\n' "$want" | write_user_file "$AUDACITY_CFG_REL"
  fi
  echo "w-style: audacity done (theme $want; Audacity reads it at its next start)."
}
