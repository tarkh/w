# w-style module: ardour (user-scope) — Ardour colour theme.
#
# Ships INSIDE the audio W-Pack (source of truth); `w-pack install audio` drops
# this axis into the w-style modules.d drop-in root, `w-pack remove` takes it
# back. Core w-style carries no reference to Ardour → the axis exists iff the
# bundle is installed (packs.md "bundle self-containment", pack-audio.md).
#
# Ardour draws its whole UI itself (a private GTK2 fork + its own canvas), so
# neither the gtk nor the qt axis reaches it. Its look is one XML file,
# <name>-ardour.colors: ~56 named palette <Color>s, ~430 <ColorAlias>es that
# point every UI element at one of them, and <Modifier>s (alpha tweaks). The
# stock themes share the alias layer almost entirely and differ in the palette
# — so this axis does not hand-write a theme: it takes the installed
# dark-ardour.colors (aliases + modifiers exactly as this Ardour version ships
# them) and swaps only the palette values for W tokens, keeping each colour's
# own alpha byte. A new Ardour release brings its new aliases along for free.
#
# Targets: ~/.config/ardour<N>/themes/w-ardour.colors (and clearlooks.rc, see
# render_user) — Ardour searches its user config dir before /usr/share, and
# selects the theme by name: ui_config's `color-file` = "w" (seeded by the
# bundle's manifest, guarded-set by setup-user.sh). Not live: Ardour reads the theme at start (or on picking it
# again in Preferences → Appearance → Colors). A colour the user edits there is
# saved as my-w-ardour.colors, which Ardour prefers over this file — theirs.
#
# Mapping principles: the surface ramp (W_BG → W_APP_BG → SURFACE_DIM →
# SURFACE → SURFACE_VARIANT) for borders/canvas/rulers/window, buttons and
# dropdowns one step above it (SURFACE_VARIANT + a touch of text) so they read
# off the window; text tones W_ON_SURFACE*; the accent split fill/ink
# (W_PRIMARY fills, the INK tokens draw); signal colours (meters, alerts, MIDI
# lanes) from the ANSI wheel so green/yellow/red keep their meaning; the dark
# tints Ardour needs for track and processor bases are mixes of a hue into
# W_APP_BG/W_SURFACE, so they stay right on a light theme too — MIDI tracks,
# green-grey in stock, take the soft accent instead (green into violet is mud).
# No new theme.conf tokens. Band 400 = per-app GUI.
DESC="Ardour colour theme"

# Mix two #rrggbb colours: <a> <b> <percent of b> → rrggbb (no '#').
ardour_mix() {
  local a="${1#\#}" b="${2#\#}" p="$3" i out=""
  for i in 0 2 4; do
    out+="$(printf '%02x' $(( (16#${a:i:2} * (100 - p) + 16#${b:i:2} * p) / 100 )))"
  done
  printf '%s' "$out"
}

render_user() {
  local base ver rel theme_dir
  # Highest installed Ardour generation (/usr/share/ardour9, ardour10, …).
  base="$(printf '%s\n' /usr/share/ardour*/themes/dark-ardour.colors | sort -V | tail -n1)"
  if [[ ! -f "$base" ]]; then
    echo "w-style: ardour — Ardour is not installed, nothing to render."
    return 0
  fi
  ver="${base#/usr/share/ardour}"; ver="${ver%%/*}"
  rel=".config/ardour$ver/themes/w-ardour.colors"

  theme_dir="$(w_userscope_theme_dir)"
  load_conf "$theme_dir"
  echo "w-style: rendering Ardour colour theme..."

  local map
  map=$(cat <<EOF
alert:blue	${W_TERM_ANSI_BLUE}
alert:cyan	${W_TERM_ANSI_CYAN}
alert:green	${W_TERM_ANSI_GREEN}
alert:greenish	$(ardour_mix "$W_APP_BG" "$W_TERM_ANSI_GREEN" 70)
alert:orange	${W_TERM_ANSI_YELLOW}
alert:red	${W_DANGER}
alert:ruddy	${W_TERM_ANSI_RED}
alert:yellow	${W_TERM_ANSI_BRIGHT_YELLOW}
meter color0	${W_TERM_ANSI_GREEN}
meter color1	${W_TERM_ANSI_GREEN}
meter color2	${W_TERM_ANSI_BRIGHT_GREEN}
meter color3	${W_TERM_ANSI_BRIGHT_GREEN}
meter color4	${W_TERM_ANSI_BRIGHT_YELLOW}
meter color5	${W_TERM_ANSI_BRIGHT_YELLOW}
meter color6	${W_TERM_ANSI_YELLOW}
meter color7	${W_TERM_ANSI_YELLOW}
meter color8	${W_DANGER}
meter color9	${W_DANGER}
midi meter 52	${W_TERM_ANSI_BRIGHT_GREEN}
midi meter 53	${W_TERM_ANSI_BRIGHT_YELLOW}
midi meter 54	${W_TERM_ANSI_YELLOW}
midi meter 55	${W_TERM_ANSI_BRIGHT_RED}
midi meter 56	${W_TERM_ANSI_RED}
neutral:background	${W_APP_BG}
neutral:background2	${W_SURFACE_VARIANT}
neutral:backgroundest	${W_BG}
neutral:foreground	${W_ON_SURFACE}
neutral:foreground2	${W_ON_SURFACE_VARIANT}
neutral:foregroundest	${W_ON_SURFACE_BRIGHT}
neutral:midground	${W_ON_SURFACE_FAINT}
pianoroll: insensitive bender line	${W_TERM_ANSI_BLUE}
pianoroll: insensitive expression line	${W_TERM_ANSI_YELLOW}
pianoroll: insensitive modulation line	${W_TERM_ANSI_GREEN}
pianoroll: insensitive pressure line	${W_TERM_ANSI_CYAN}
pianoroll: user1 line	${W_TERM_ANSI_RED}
pianoroll: user2 line	${W_TERM_ANSI_MAGENTA}
pianoroll: user3 line	${W_TERM_ANSI_BRIGHT_BLUE}
pianoroll: velocity	${W_TERM_ANSI_BRIGHT_YELLOW}
theme:bg	${W_SURFACE}
theme:bg1	${W_SURFACE_DIM}
theme:bg2	${W_APP_BG}
theme:contrasting	${W_ON_SURFACE_VIVID}
theme:contrasting alt	${W_TERM_ANSI_YELLOW}
theme:contrasting clock	${W_ON_SURFACE_ACCENT}
theme:contrasting less	${W_TERM_ANSI_GREEN}
theme:contrasting selection	${W_PRIMARY}
widget:bg	$(ardour_mix "$W_SURFACE_VARIANT" "$W_ON_SURFACE" 12)
widget:blue	${W_PRIMARY_CONTAINER}
widget:blue darker	$(ardour_mix "$W_SURFACE" "$W_PRIMARY_CONTAINER" 35)
widget:blue lighter	${W_PRIMARY}
widget:gray	${W_SURFACE_VARIANT}
widget:green	$(ardour_mix "$W_SURFACE" "$W_TERM_ANSI_GREEN" 60)
widget:green darker	$(ardour_mix "$W_SURFACE" "$W_PRIMARY_SOFT" 10)
widget:orange	$(ardour_mix "$W_APP_BG" "$W_TERM_ANSI_YELLOW" 60)
widget:ruddy	$(ardour_mix "$W_APP_BG" "$W_TERM_ANSI_RED" 55)
widget:yellow	${W_TERM_ANSI_BRIGHT_YELLOW}
EOF
)

  # The one place the alias layer is touched: Ardour's dark theme draws
  # SELECTION in its red family (alert:red/ruddy, widget:ruddy), the same
  # family as record/solo/clip. In W selection is the accent, and record stays
  # red — so these aliases are pointed at the accent entries of the palette
  # above; everything else that shares the red family keeps it.
  local alias
  alias=$(cat <<'EOF'
@gtk_track_header_selected	widget:blue
@selected region base	widget:blue
@selected time axis frame	theme:contrasting selection
@selection	theme:contrasting selection
@selection rect	theme:contrasting selection
@midi note selected	widget:blue lighter
@midi note selected outline	neutral:foregroundest
@selected waveform fill	widget:blue lighter
@control point selected fill	widget:blue lighter
EOF
)

  # Swap the value of every mapped palette <Color> (keeping its alpha byte) and
  # the target of every listed <ColorAlias>; modifiers and comments pass
  # through untouched. Prints the swap count last (stripped below) — the
  # sentinel against a token typo or an upstream rename leaving part of it stock.
  local out
  out="$(awk -F'\t' '
    NR == FNR && /^@/ { amap[substr($1, 2)] = $2; want++; next }
    NR == FNR { v = tolower($2); sub(/^#/, "", v); map[$1] = v; want++; next }
    /<Ardour theme-name=/ { sub(/theme-name="[^"]*"/, "theme-name=\"W\"") }
    /<ColorAlias name="/ {
      n = $0; sub(/.*<ColorAlias name="/, "", n); sub(/".*/, "", n)
      if (n in amap) { sub(/alias=("[^"]*"|\x27[^\x27]*\x27)/, "alias=\"" amap[n] "\""); done++ }
    }
    /<Color name="/ {
      n = $0; sub(/.*<Color name="/, "", n); sub(/".*/, "", n)
      if (n in map) {
        v = $0; sub(/.*value="/, "", v); sub(/".*/, "", v)
        alpha = (length(v) >= 8) ? substr(v, length(v) - 1) : "ff"
        sub(/value="[^"]*"/, "value=\"" map[n] alpha "\"")
        done++
      }
    }
    { print }
    END { print want == done ? "OK" : "MISMATCH " done "/" want }
  ' <(printf '%s\n%s\n' "$map" "$alias") "$base")"

  if [[ "${out##*$'\n'}" != OK ]]; then
    echo "w-style: ardour — palette swap incomplete (${out##*$'\n'}): token typo or a renamed Ardour colour; refusing to write." >&2
    return 1
  fi
  printf '%s\n' "${out%$'\n'*}" | write_user_file "$rel"

  # Ardour's widget rc is tuned for its mid-grey stock theme, and two of its
  # choices vanish on a dark W surface: insensitive labels (greyed-out menu
  # items) are shade(0.7, background), and popup menus — the dropdowns' lists
  # too — share the window background. Ardour reads clearlooks.rc from the user
  # config dir first, so the installed one is copied there with the first rule
  # turned into a text/background mix and a menu style appended, lifted off the
  # window by a touch of the text colour — both readable on any palette, light
  # or dark. No match (upstream changed the line) → no copy: stock rc, nothing
  # stale shadowing it.
  local rc="/etc/ardour$ver/clearlooks.rc" rule='^  fg\[INSENSITIVE\]     = shade\(0\.7, @background\)$'
  if [[ -f "$rc" ]] && grep -qE "$rule" "$rc"; then
    { sed -E "s/$rule/  fg[INSENSITIVE]     = mix(0.5, @foreground, @background)/" "$rc"
      printf '\nstyle "w_menu" { bg[NORMAL] = mix(0.1, @foreground, @background) }\n'
      printf 'class "GtkMenu" style:highest "w_menu"\n'
    } | write_user_file ".config/ardour$ver/clearlooks.rc"
  else
    echo "w-style: ardour — clearlooks.rc rule not found, greyed-out labels stay stock."
  fi

  if [[ $EUID -eq 0 ]]; then
    echo "w-style: ardour done (skel template; live accounts pick it up at their next login render)."
  else
    echo "w-style: ardour done (Ardour shows it at its next start)."
  fi
}
