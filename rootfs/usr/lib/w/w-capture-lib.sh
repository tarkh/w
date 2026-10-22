# w-capture-lib.sh — shared helpers for W's screen-capture front-ends.
#
# Sourced by /usr/bin/w-screenshot and /usr/bin/w-record. Everything here is a
# question BOTH have to answer identically, which is the whole reason the file
# exists: a still and a recording of "the focused window" that disagreed about
# what the focused window is would be a bug nobody could see until it bit.
#
# Defines functions only — no side effects on source, and no `set -e` assumptions
# about the caller.
#
# Geometry contract: "x,y WxH", in the compositor's GLOBAL LOGICAL coordinates.
# That is one string understood verbatim by slurp (it prints it), grim (-g) and
# wf-recorder (-g, which resolves the output from it via xdg_output logical
# size/position). Flameshot is the one consumer that does NOT speak it — it wants
# monitor-local PHYSICAL pixels — so its conversion stays inside w-screenshot
# where the reason for it is written down.

# ── Save locations ────────────────────────────────────────────────────────────

# An XDG user folder as xdg-user-dirs names it (~/Pictures on an English system,
# ~/Изображения on a Russian one — and wherever the user moved it), never a
# literal name. `xdg-user-dir` answers with the home ITSELF when nothing is
# configured yet (a session that received the subsystem and has not logged in
# again) or the folder was deleted; a capture does not belong loose in the home,
# so both cases — and a system without the package — fall back to the English
# name under $HOME.
#
#   w_capture_userdir PICTURES Pictures
#   w_capture_userdir VIDEOS   Videos
w_capture_userdir() { # <XDG_NAME> <fallback-basename>
  local d; d="$(xdg-user-dir "$1" 2>/dev/null || true)"
  if [[ -n "$d" && "$d" != "$HOME" ]]; then echo "$d"; else echo "$HOME/$2"; fi
}

# ── Notifications ─────────────────────────────────────────────────────────────

# "Saved <file>" whose click opens the file in its default app — the macOS/Windows
# habit. W's notification server reports a click on the card as the `default`
# action; hearing it takes `notify-send --wait`, which blocks until the card closes,
# so the listener runs detached and the capture returns at once. A still rides along
# as the card's picture (the `image-path` hint). Needs `w_t` (w-i18n-lib) from the
# caller — both front-ends source it.
#
#   w_capture_notify_saved "W Screenshot" "$(w_t screenshot.saved)" "$out"
w_capture_notify_saved() { # <app> <summary> <file>
  command -v notify-send >/dev/null 2>&1 || return 0
  local image=()
  [[ "$3" == *.png ]] && image=(-h "string:image-path:$3")
  setsid -f bash -c '[[ "$(notify-send "${@:2}")" == default ]] && exec xdg-open "$1"' _ \
    "$3" -a "$1" "${image[@]}" --action="default=$(w_t capture.open)" --wait "$2" "$3" \
    </dev/null >/dev/null 2>&1 || true
}

# ── Geometry ──────────────────────────────────────────────────────────────────

# The focused window as Hyprland DRAWS it: `activewindow` JSON plus `.border` and
# `.rounding`, in logical pixels, empty when nothing is focused. Both are the
# window's own props (`getprop`), so a window rule (`border_size = 0`,
# `rounding = 0`) is seen exactly as the screen shows it, and so is the theme: the
# compositor takes a theme switch within the crossfade, and until then the screen
# still shows the old frame. A capture records the screen, so the screen's values
# are the right ones — there is no theme file to agree with.
#
# getprop does not know about fullscreen: it keeps answering the window's border and
# rounding while the compositor draws neither. So fullscreen (bit 2 of the mode) is
# zeroed here. Maximised (1) is not — a maximised window keeps both, measured.
w_capture_active_window() {
  local win addr b=0 r=0
  win=$(hyprctl -j activewindow 2>/dev/null) || return 0
  addr=$(jq -r '.address // empty' <<<"$win" 2>/dev/null); [[ -n "$addr" ]] || return 0
  if [[ "$(jq -r '(.fullscreen // 0) >= 2' <<<"$win")" == false ]]; then
    b=$(hyprctl -j getprop "address:$addr" border_size 2>/dev/null | jq -r '.border_size // 0' 2>/dev/null)
    r=$(hyprctl -j getprop "address:$addr" rounding 2>/dev/null | jq -r '.rounding // 0' 2>/dev/null)
  fi
  [[ "$b" =~ ^[0-9]+$ ]] || b=0; [[ "$r" =~ ^[0-9]+$ ]] || r=0
  jq -c --argjson b "$b" --argjson r "$r" '. + {border: $b, rounding: $r}' <<<"$win"
}

# Name of the focused output, empty if Hyprland cannot be reached.
w_capture_output_name() {
  hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)) | .name // empty'
}

# Geometry of the focused window, empty when nothing is focused (a bare desktop,
# or a layer-shell surface holding focus). Callers decide what that means: both
# front-ends fall back to asking the user to drag a region.
#
# The rectangle INCLUDES the window border. Hyprland's `at`/`size` describe the
# surface, and the border is drawn OUTSIDE it, so the bare numbers cut the frame
# off along every straight edge while the rounded corners (which curve back inside
# the box) still show it. The window's own border width is added on each side
# (w_capture_active_window): none for a window a rule left borderless, or a
# fullscreen one, which then keep their bare rectangle.
#
# With --clamp, the rectangle is intersected with the focused MONITOR's own
# rectangle. wf-recorder requires its region to sit inside ONE output, and what it
# does when that fails is worse than an error: with several monitors it cannot tell
# which output the region belongs to and exits, but with a single monitor it
# silently DISCARDS the region and records the whole screen. So an untrimmed
# rectangle does not fail loudly — it quietly records the wrong thing. The clamp
# also trims the border where a window touches the monitor edge (gaps_out 0), which
# no capture backend could show anyway.
#
# grim has no such rule, which is why the clamp is opt-in for stills: a window
# hanging off the edge is better captured whole. Flameshot needs it as well — its
# preselection must lie inside the monitor widget.
w_capture_window_geom() { # [--clamp]
  local clamp=0; [[ "${1:-}" == --clamp ]] && clamp=1
  local win mons
  win=$(w_capture_active_window); [[ -n "$win" ]] || return 0
  if [[ $clamp -eq 0 ]]; then
    jq -r '.border as $b
      | "\(.at[0] - $b),\(.at[1] - $b) \(.size[0] + 2 * $b)x\(.size[1] + 2 * $b)"' <<<"$win"
    return 0
  fi
  mons=$(hyprctl -j monitors 2>/dev/null) || return 0
  # Intersection of the window rect with the focused monitor rect, as edges
  # rather than origin+size: clamping a width without moving its origin would
  # trim the wrong side when the window hangs off the LEFT edge.
  jq -r --argjson w "$win" '
    $w.border as $b
    | first(.[] | select(.focused)) as $m
    | ([$w.at[0] - $b, $m.x] | max)                                  as $x1
    | ([$w.at[1] - $b, $m.y] | max)                                  as $y1
    | ([$w.at[0] + $w.size[0] + $b, $m.x + $m.width]  | min)         as $x2
    | ([$w.at[1] + $w.size[1] + $b, $m.y + $m.height] | min)         as $y2
    | if $x2 > $x1 and $y2 > $y1
      then "\($x1),\($y1) \($x2 - $x1)x\($y2 - $y1)"
      else empty end' <<<"$mons"
}

# ── Window outline (mask + shadow) ────────────────────────────────────────────

# Outer corner radius of the focused window's frame, in LOGICAL pixels: the window's
# rounding plus its border, which is drawn outside the surface and curves with it.
# A square-cornered window (rounding 0, by theme or by rule) has square corners
# whatever its border, so the radius is 0 and nothing is rounded. Empty for a
# fullscreen window (no outline, nothing to dress) or when the compositor cannot be
# asked.
w_capture_window_radius() {
  local win; win=$(w_capture_active_window); [[ -n "$win" ]] || return 0
  jq -r 'if (.fullscreen // 0) >= 2 then empty
         elif .rounding > 0 then .rounding + .border else 0 end' <<<"$win"
}

# A capture of a window, dressed: stdin PNG -> stdout PNG.
#   <radius>   logical, from w_capture_window_radius
#   <logical-w> width of the captured rectangle in logical pixels; the pixel scale
#              is read off the image itself (grim emits logical x output scale),
#              so HiDPI and fractional scales need no monitor lookup
#   <shadow>   yes | no
# Corners outside the rounded outline turn transparent (a radius of 0 cuts nothing:
# ImageMagick's roundrectangle with a zero radius draws NOTHING, which would erase
# the whole frame); with shadow, a soft translucent one is cast slightly downward on
# a transparent margin, the way macOS does. Never fatal: without ImageMagick (or on
# any failure) the frame goes through untouched — an undressed capture beats a lost one.
w_capture_window_dress() { # <radius> <logical-w> <yes|no>
  local r="$1" lw="$2" shadow="$3" tmp w h s
  tmp=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/w-dress.XXXXXX") || { cat; return 0; }
  cat >"$tmp"
  if command -v magick >/dev/null 2>&1 &&
     read -r w h < <(magick identify -format '%w %h\n' "$tmp" 2>/dev/null) && [[ "$w" =~ ^[0-9]+$ && "$lw" -gt 0 ]]; then
    s=$(awk -v w="$w" -v l="$lw" 'BEGIN { printf "%.4f", w / l }')
    local -a cut=() shade=()
    (( r > 0 )) && cut=( \( -size "${w}x${h}" xc:none -fill white
      -draw "roundrectangle 0,0 $((w - 1)),$((h - 1)) $(awk -v r="$r" -v s="$s" 'BEGIN { printf "%.2f,%.2f", r * s, r * s }')" \)
      -compose DstIn -composite )
    # opacity 55 %, blur sigma 14 and a 12 px drop, all logical
    [[ "$shadow" == yes ]] && shade=( \( +clone -background black
      -shadow "$(awk -v s="$s" 'BEGIN { printf "55x%.1f+0+%d", 14 * s, 12 * s + 0.5 }')" \)
      +swap -background none -compose Over -layers merge +repage )
    if magick "$tmp" -alpha set "${cut[@]}" "${shade[@]}" -depth 8 png:- 2>/dev/null; then
      rm -f "$tmp"; return 0
    fi
  fi
  cat "$tmp"; rm -f "$tmp"
}

# Mask for a recording, written to <png>: opaque black in the corners outside the
# window's rounded outline, transparent inside — overlaid on the video it turns
# the wallpaper behind the corners black (a video has no alpha to make them
# clear). Sized to the CLAMPED rectangle wf-recorder records, in physical pixels;
# the outline itself is drawn from the UNCLAMPED window, so a side the monitor
# edge trimmed off is not given a corner it never had. Returns 1, writing nothing,
# when there is nothing to mask (fullscreen, no window, square-cornered window, no
# ImageMagick). At a fractional scale the frame and this size may differ by a pixel
# (each rounds 1012.5 its own way); measured on the VM, the arc lands in the same
# place either way — the odd row or column just falls outside the frame.
w_capture_window_mask() { # <png>
  local png="$1" r gu gc mons sc
  command -v magick >/dev/null 2>&1 || return 1
  r=$(w_capture_window_radius); [[ -n "$r" && "$r" -gt 0 ]] || return 1
  gu=$(w_capture_window_geom); gc=$(w_capture_window_geom --clamp)
  [[ -n "$gu" && -n "$gc" ]] || return 1
  mons=$(hyprctl -j monitors 2>/dev/null) || return 1
  sc=$(jq -r 'first(.[] | select(.focused)) | .scale // 1' <<<"$mons")
  local -a u c
  read -ra u <<<"${gu//[,x]/ }"; read -ra c <<<"${gc//[,x]/ }"   # x y w h
  magick -size "$(awk -v w="${c[2]}" -v h="${c[3]}" -v s="$sc" 'BEGIN { printf "%dx%d", w * s + 0.5, h * s + 0.5 }')" xc:none \
    -fill white -draw "roundrectangle $(awk -v u="${u[*]}" -v c="${c[*]}" -v s="$sc" -v r="$r" 'BEGIN {
        split(u, a, " "); split(c, b, " ")
        printf "%.2f,%.2f %.2f,%.2f %.2f,%.2f", (a[1] - b[1]) * s, (a[2] - b[2]) * s,
          (a[1] - b[1] + a[3]) * s - 1, (a[2] - b[2] + a[4]) * s - 1, r * s, r * s }')" \
    -channel A -negate +channel -fill black -colorize 100 "PNG32:$png" 2>/dev/null
}

# ── Themed region selection ───────────────────────────────────────────────────

# slurp's colour/font flags from the ACTIVE theme, one argv entry per line.
#
# slurp has no config file — colours are command-line flags only — so there is no
# w-style axis to render here. Instead this reads the theme the way w-appearance
# does, through w-style's own SDK: a theme switch is therefore live, with no
# render step and no relogin, and there is no generated file to drift.
#
# Never fatal. A missing, older or hand-broken theme just leaves slurp its own
# defaults: a selection the user can still complete beats an aborted capture.
# Hence the subshell — `load_conf` exits on a missing theme.conf, and that exit
# must not take the capture with it.
_w_capture_slurp_theme() {
  ( set +eu
    # shellcheck source=../w-style/lib/core.sh
    source /usr/lib/w/w-style/lib/core.sh 2>/dev/null || exit 1
    dir="$(w_userscope_theme_dir)"
    [[ -f "$dir/theme.conf" ]] || exit 1
    load_conf "$dir" >/dev/null 2>&1
    font_conf="$(resolve_theme_file "$dir" font.conf)"
    [[ -f "$font_conf" ]] && load_font "$font_conf" >/dev/null 2>&1
    [[ -n "$W_PRIMARY" ]] || exit 1
    # slurp takes #rrggbbaa, the theme stores #rrggbb — the alpha is this file's
    # to choose. Everything here mirrors flameshot's overlay, so a selection reads
    # the same whichever tool drew it: outside dimmed plain black at 65 % (0xa6 —
    # flameshot's overlay colour is hardcoded black, only the depth is
    # configurable: contrastOpacity 166 in the 400-flameshot axis), inside left
    # untouched (fully transparent fill), and a 1 px accent frame.
    printf -- '-b\n#000000a6\n-c\n%sff\n-s\n#00000000\n-w\n1\n' "$W_PRIMARY"
    [[ -n "$W_FONT_UI" ]] && printf -- '-F\n%s\n' "$W_FONT_UI"
  ) || true
}

# Interactive region selection in W's colours. Prints "x,y WxH"; a non-zero
# return is the user cancelling, which every caller treats as success.
w_capture_select_region() { # [extra slurp args...]
  local -a theme=()
  local line
  while IFS= read -r line; do theme+=("$line"); done < <(_w_capture_slurp_theme)
  slurp -d "${theme[@]}" "$@"
}
