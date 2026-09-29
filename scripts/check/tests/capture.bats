#!/usr/bin/env bats
# capture.bats — w-capture-lib.sh, the geometry and save-folder contract shared by
# w-screenshot and w-record.
#
# The arithmetic here is worth a gate because getting it wrong is INVISIBLE. An
# untrimmed window rectangle does not make wf-recorder fail: with one monitor it
# throws the region away and records the whole screen, so "record this window"
# quietly becomes "record everything". W's own default border already puts a
# maximised Hyprland window two pixels outside its monitor, which is why the clamp
# is the ordinary path rather than the defensive one — see the numbers below,
# measured on a real 1904x1021 output.
#
# None of it needs a compositor: hyprctl is a PATH stub and xdg-user-dir another,
# so every case is a frozen input. The clamp is pure jq over two rectangles.

load helpers

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  hyprctl_offline          # no live compositor unless a test stubs one
  export W_STYLE_LIB="$BATS_TEST_TMPDIR/no-w-style"   # no theme unless a test installs one
  source "$REPO/rootfs/usr/lib/w/w-capture-lib.sh"
}

# hyprctl answering `monitors`, `activewindow` and `getoption general:border_size`
# with frozen JSON. The border defaults to 0 so the clamp cases stay bare rectangles;
# `decoration:rounding` likewise (the outline cases set it).
hypr_geom_stub() { # <monitors-json> <activewindow-json> [border-size] [rounding]
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in\n  monitors) echo %s; exit 0 ;;\n  activewindow) echo %s; exit 0 ;;\n  general:border_size) echo %s; exit 0 ;;\n  decoration:rounding) echo %s; exit 0 ;;\nesac; done\nexit 1\n' \
    "'$1'" "'$2'" "'{\"int\":${3:-0}}'" "'{\"int\":${4:-0}}'" > "$bin/hyprctl"
  chmod 755 "$bin/hyprctl"
  PATH="$bin:$PATH"
}

# The 1904x1021 output every geometry case below is framed against.
MON='[{"name":"Virtual-1","focused":true,"x":0,"y":0,"width":1904,"height":1021,"scale":1}]'

win() { # <x> <y> <w> <h>
  echo "{\"address\":\"0x1\",\"at\":[$1,$2],\"size\":[$3,$4]}"
}

xdg_stub() { # <answer>  (empty = the tool exists but prints nothing)
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s\n' "'$1'" > "$bin/xdg-user-dir"
  chmod 755 "$bin/xdg-user-dir"
  PATH="$bin:$PATH"
}

# ── Save folders ──────────────────────────────────────────────────────────────

@test "userdir: the folder xdg-user-dirs names, whatever language it is in" {
  xdg_stub "$HOME/Изображения"
  run w_capture_userdir PICTURES Pictures
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/Изображения" ]
}

@test "userdir: an unconfigured folder answers with \$HOME and must not be used" {
  # xdg-user-dir prints the home itself when the folder is not configured or was
  # deleted. A capture dropped loose in the home is the bug this guards.
  xdg_stub "$HOME"
  run w_capture_userdir VIDEOS Videos
  [ "$output" = "$HOME/Videos" ]
}

@test "userdir: no xdg-user-dirs installed falls back to the English name" {
  run w_capture_userdir VIDEOS Videos
  [ "$output" = "$HOME/Videos" ]
}

# ── Window geometry ───────────────────────────────────────────────────────────

@test "window geom: a window inside its monitor is passed through untouched" {
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)"
  run w_capture_window_geom
  [ "$output" = "10,48 1884x963" ]
}

@test "window geom: --clamp leaves a contained window alone" {
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)"
  run w_capture_window_geom --clamp
  [ "$output" = "10,48 1884x963" ]
}

@test "window geom: --clamp trims W's own -2,-2 maximised window" {
  # The measured case: W's default border puts a maximised window at -2,-2 with
  # the monitor's full size. Untrimmed, wf-recorder recorded the whole screen;
  # trimmed, it recorded this rectangle. Both origin AND size have to move.
  # (The mp4 comes out a pixel shorter than the clamp asks for — h264 needs even
  # dimensions and x264 rounds 1019 down. That happens in the encoder, not here.)
  hypr_geom_stub "$MON" "$(win -2 -2 1904 1021)"
  run w_capture_window_geom --clamp
  [ "$output" = "0,0 1902x1019" ]
}

@test "window geom: --clamp trims the far edges, not just the origin" {
  hypr_geom_stub "$MON" "$(win 1800 900 400 400)"
  run w_capture_window_geom --clamp
  [ "$output" = "1800,900 104x121" ]
}

@test "window geom: --clamp keeps the origin put when only the size overflows" {
  # Clamping a width without moving its origin is right HERE and wrong for a
  # negative origin — which is why the jq works in edges, not origin+size.
  hypr_geom_stub "$MON" "$(win 0 0 2000 1100)"
  run w_capture_window_geom --clamp
  [ "$output" = "0,0 1904x1021" ]
}

@test "window geom: a window entirely off the focused monitor clamps to nothing" {
  # A non-empty answer here would be a zero- or negative-sized region, which the
  # backend reads as "no region" — i.e. the whole screen. Empty makes the caller
  # fall back to asking the user, which is the honest outcome.
  hypr_geom_stub "$MON" "$(win 2100 0 400 400)"
  run w_capture_window_geom --clamp
  [ "$output" = "" ]
}

@test "window geom: the border is part of the rectangle, on every side" {
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2
  run w_capture_window_geom
  [ "$output" = "8,46 1888x967" ]
}

@test "window geom: a fullscreen window has no border to add" {
  hypr_geom_stub "$MON" '{"address":"0x1","at":[0,0],"size":[1904,1021],"fullscreen":2}' 2
  run w_capture_window_geom
  [ "$output" = "0,0 1904x1021" ]
}

@test "window geom: --clamp adds the border first, then trims to the monitor" {
  hypr_geom_stub "$MON" "$(win 0 0 1904 1021)" 2
  run w_capture_window_geom --clamp
  [ "$output" = "0,0 1904x1021" ]
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2
  run w_capture_window_geom --clamp
  [ "$output" = "8,46 1888x967" ]
}

@test "window geom: no focused window is empty, not an error" {
  hypr_geom_stub "$MON" '{}'
  run w_capture_window_geom
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "window geom: no compositor is empty, not an error" {
  run w_capture_window_geom
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── Output name ───────────────────────────────────────────────────────────────

@test "output name: the focused monitor, never the first one listed" {
  hypr_geom_stub \
    '[{"name":"HDMI-A-1","focused":false},{"name":"eDP-1","focused":true}]' '{}'
  run w_capture_output_name
  [ "$output" = "eDP-1" ]
}

@test "output name: no compositor is empty, not an error" {
  run w_capture_output_name
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── Themed selection ──────────────────────────────────────────────────────────

@test "slurp theme: a broken theme leaves slurp its own defaults, never aborts" {
  # The capture must survive a missing theme: load_conf exits, and that exit must
  # not be the caller's. Nothing is installed under /usr/lib/w here, so this is
  # the "no W on the machine" path as well.
  run _w_capture_slurp_theme
  [ "$status" -eq 0 ]
}

# ── Recording colour (w-record) ───────────────────────────────────────────────
#
# Measured on the VM against a grim still of the same frame: left to itself,
# wf-recorder's CPU path mapped RGB into 16-235 while tagging the stream
# full-range, so black played back at 15 and white at ~221 — the "pale haze". The
# fix is argv, and argv is what these cases pin, on both roads to the CPU: asked
# for directly, and reached as the fallback from a GPU that would not start.
#
# wf-recorder is a stub that logs its argv and lives long enough to pass the
# start-up check; a stub told to reject VAAPI dies at once, like a lying driver.

record_start() { # <ENCODER> [FORMAT] [MODE] [extra record.conf lines]
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin" "$HOME/.config/w" "$BATS_TEST_TMPDIR/run"
  printf '#!/usr/bin/env bash\nprintf "%%s " "$@" >> %q; echo >> %q\n[[ -e %q && "$*" == *h264_vaapi* ]] && exit 1\nsleep 30\n' \
    "$BATS_TEST_TMPDIR/argv" "$BATS_TEST_TMPDIR/argv" "$BATS_TEST_TMPDIR/vaapi-dies" > "$bin/wf-recorder"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/notify-send"
  chmod 755 "$bin/wf-recorder" "$bin/notify-send"
  printf 'ENCODER=%s\nFORMAT=%s\nAUDIO=none\n%s\n' "$1" "${2:-mp4}" "${4:-}" > "$HOME/.config/w/record.conf"
  hypr_geom_stub "$MON" "${WIN:-null}" "${BORDER:-0}" "${ROUNDING:-0}"
  xdg_stub "$BATS_TEST_TMPDIR/videos"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" WCONF_HOME="$HOME" \
         WCONF_ETC="$BATS_TEST_TMPDIR/etc" WCONF_VENDOR_DIR="$REPO/rootfs/usr/share/w/defaults" \
         W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh" \
         W_CAPTURE_LIB="$REPO/rootfs/usr/lib/w/w-capture-lib.sh" \
         W_VAAPI_NODE="$BATS_TEST_TMPDIR/renderD128"
  run "$REPO/rootfs/usr/bin/w-record" "${3:-output}" --start
}

teardown() {
  local st="$BATS_TEST_TMPDIR/run/w/record.state"
  [[ -f "$st" ]] && pkill -P "$(sed -n 's/^PID=//p' "$st")" sleep 2>/dev/null || true
}

@test "record colour: the CPU path converts to limited BT.709 and tags it so" {
  record_start cpu
  [ "$status" -eq 0 ]
  grep -q -- '-F scale=out_color_matrix=bt709:out_range=limited ' "$BATS_TEST_TMPDIR/argv"
  grep -q -- '-p color_range=tv ' "$BATS_TEST_TMPDIR/argv"
  grep -q -- '-p colorspace=bt709 ' "$BATS_TEST_TMPDIR/argv"
}

@test "record colour: VAAPI keeps wf-recorder's own conversion, no CPU filter" {
  touch "$BATS_TEST_TMPDIR/renderD128"
  record_start auto
  [ "$status" -eq 0 ]
  grep -q -- '-c h264_vaapi ' "$BATS_TEST_TMPDIR/argv"
  ! grep -q -- 'out_range=limited' "$BATS_TEST_TMPDIR/argv"
}

@test "record colour: the CPU fallback from a failed GPU start is corrected too" {
  touch "$BATS_TEST_TMPDIR/renderD128" "$BATS_TEST_TMPDIR/vaapi-dies"
  record_start auto
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/argv")" -eq 2 ]
  tail -n1 "$BATS_TEST_TMPDIR/argv" | grep -q -- '-F scale=out_color_matrix=bt709:out_range=limited '
  grep -q '^ENCODER=cpu$' "$BATS_TEST_TMPDIR/run/w/record.state"
}

@test "record codec: WebM gets VP9/Opus on the CPU, even with a render node" {
  # wf-recorder offers h264 whatever the container, and the WebM muxer refuses it.
  touch "$BATS_TEST_TMPDIR/renderD128"
  record_start auto webm
  [ "$status" -eq 0 ]
  grep -q -- '-c libvpx-vp9 -C libopus ' "$BATS_TEST_TMPDIR/argv"
  grep -q -- 'out_range=limited' "$BATS_TEST_TMPDIR/argv"
  ! grep -q -- 'h264_vaapi' "$BATS_TEST_TMPDIR/argv"
}

# ── Window outline: mask and shadow ───────────────────────────────────────────

need_magick() { command -v magick >/dev/null 2>&1 || skip "ImageMagick is not installed"; }
px() { magick "$1" -format "%[pixel:p{$2,$3}]" info:; }   # <png> <x> <y>

# A stand-in for w-style's SDK: the same three functions capture-lib calls, pointing
# at a theme dir the test owns. The real resolution (pin vs system) is w-style's own.
theme_stub() { # <rounding> <border>   (a geometry.conf that sets nothing when both empty)
  local lib="$BATS_TEST_TMPDIR/w-style" t="$BATS_TEST_TMPDIR/theme"
  mkdir -p "$lib" "$t"
  printf 'w_userscope_theme_dir() { echo %q; }\nresolve_theme_file() { echo "$1/$2"; }\nload_geometry() { source "$1"; }\n' "$t" > "$lib/core.sh"
  : > "$t/geometry.conf"
  [[ -z "$1" ]] || echo "W_GEO_WINDOW_ROUNDING=$1" >> "$t/geometry.conf"
  [[ -z "$2" ]] || echo "W_GEO_WINDOW_BORDER=$2"   >> "$t/geometry.conf"
  export W_STYLE_LIB="$lib"
}

@test "theme geometry: the active theme's geometry.conf wins over what the compositor draws" {
  theme_stub 0 3
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2 14
  [ "$(w_capture_theme_geo W_GEO_WINDOW_ROUNDING)" = 0 ]
  [ "$(w_capture_theme_geo W_GEO_WINDOW_BORDER)" = 3 ]
  [ "$(w_capture_window_radius)" = 0 ]                       # square windows: nothing to round, border or not
  [ "$(w_capture_window_geom)" = "7,45 1890x969" ]           # the theme's 3 px border, not the live 2
}

@test "theme geometry: an unreadable theme falls back to the compositor's own values" {
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2 14
  [ "$(w_capture_theme_geo W_GEO_WINDOW_BORDER)" = 2 ]
  [ "$(w_capture_theme_geo W_GEO_WINDOW_ROUNDING)" = 14 ]
}

@test "window radius: rounding plus the border, in logical pixels" {
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2 14
  [ "$(w_capture_window_radius)" = 16 ]
}

@test "window radius: a fullscreen window has no outline, so no radius" {
  hypr_geom_stub "$MON" '{"address":"0x1","at":[0,0],"size":[1904,1021],"fullscreen":2}' 2 14
  [ -z "$(w_capture_window_radius)" ]
}

@test "window dress: corners turn transparent, the middle stays, size is kept" {
  need_magick
  magick -size 200x100 xc:'#3060c0' "$BATS_TEST_TMPDIR/in.png"
  w_capture_window_dress 16 200 no < "$BATS_TEST_TMPDIR/in.png" > "$BATS_TEST_TMPDIR/out.png"
  [ "$(magick identify -format '%wx%h' "$BATS_TEST_TMPDIR/out.png")" = 200x100 ]
  [[ "$(px "$BATS_TEST_TMPDIR/out.png" 0 0)" == *",0)" ]]
  [[ "$(px "$BATS_TEST_TMPDIR/out.png" 100 50)" == "srgba(48,96,192,1)" ]]
}

@test "window dress: the shadow grows the canvas, the window is still on top" {
  need_magick
  magick -size 200x100 xc:'#3060c0' "$BATS_TEST_TMPDIR/in.png"
  w_capture_window_dress 16 200 yes < "$BATS_TEST_TMPDIR/in.png" > "$BATS_TEST_TMPDIR/out.png"
  read -r w h < <(magick identify -format '%w %h\n' "$BATS_TEST_TMPDIR/out.png")
  [ "$w" -gt 200 ] && [ "$h" -gt 100 ]
}

@test "window dress: HiDPI — the radius follows the image, not the logical size" {
  need_magick
  magick -size 400x200 xc:'#3060c0' "$BATS_TEST_TMPDIR/in.png"     # 200x100 logical at scale 2
  w_capture_window_dress 16 200 no < "$BATS_TEST_TMPDIR/in.png" > "$BATS_TEST_TMPDIR/out.png"
  [[ "$(px "$BATS_TEST_TMPDIR/out.png" 6 6)" == *",0)" ]]            # 32 px radius: cut here (a 16 px one would not)
  [[ "$(px "$BATS_TEST_TMPDIR/out.png" 40 40)" == "srgba(48,96,192,1)" ]]
}

@test "window dress: without ImageMagick the frame goes through untouched" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"
  ln -sf "$(command -v cat)" "$(command -v mktemp)" "$(command -v rm)" "$BATS_TEST_TMPDIR/bare/"
  printf 'PNGDATA' | PATH="$BATS_TEST_TMPDIR/bare" w_capture_window_dress 16 200 yes > "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = PNGDATA ]
}

@test "window mask: sized to the clamped frame, black outside the outline, clear inside" {
  need_magick
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2 14
  w_capture_window_mask "$BATS_TEST_TMPDIR/m.png"
  [ "$(magick identify -format '%wx%h' "$BATS_TEST_TMPDIR/m.png")" = 1888x967 ]
  [[ "$(px "$BATS_TEST_TMPDIR/m.png" 0 0)" == "srgba(0,0,0,1)" ]]
  [[ "$(px "$BATS_TEST_TMPDIR/m.png" 900 400)" == *",0)" ]]
}

@test "window mask: a side the monitor trimmed keeps no corner it never had" {
  need_magick
  # Flush with the top-left of the monitor, border trimmed: the frame starts INSIDE
  # the outline, so its very first pixel is window, not corner.
  hypr_geom_stub "$MON" "$(win 2 2 1900 1017)" 2 14
  w_capture_window_mask "$BATS_TEST_TMPDIR/m.png"
  [[ "$(px "$BATS_TEST_TMPDIR/m.png" 0 0)" == "srgba(0,0,0,1)" ]]
  hypr_geom_stub "$MON" "$(win -30 100 400 300)" 2 14
  w_capture_window_mask "$BATS_TEST_TMPDIR/m.png"
  [[ "$(px "$BATS_TEST_TMPDIR/m.png" 0 200)" == *",0)" ]]            # left edge cut: no corner arc there
}

@test "window mask: a square-cornered theme has nothing to mask" {
  need_magick
  theme_stub 0 2
  hypr_geom_stub "$MON" "$(win 10 48 1884 963)" 2 14
  ! w_capture_window_mask "$BATS_TEST_TMPDIR/m.png"
}

@test "window mask: fullscreen has nothing to mask" {
  need_magick
  hypr_geom_stub "$MON" '{"address":"0x1","at":[0,0],"size":[1904,1021],"fullscreen":2}' 2 14
  ! w_capture_window_mask "$BATS_TEST_TMPDIR/m.png"
  [ ! -e "$BATS_TEST_TMPDIR/m.png" ]
}

@test "record mask: window + WINDOW_MASK=yes overlays the mask ahead of the colour filter" {
  need_magick
  WIN="$(win 10 48 1884 963)" BORDER=2 ROUNDING=14 record_start cpu mp4 window WINDOW_MASK=yes
  [ "$status" -eq 0 ]
  grep -q -- "-F movie=$BATS_TEST_TMPDIR/run/w/record.mask.png\[m\];\[in\]\[m\]overlay=format=auto,scale=out_color_matrix=bt709:out_range=limited " "$BATS_TEST_TMPDIR/argv"
  [ -s "$BATS_TEST_TMPDIR/run/w/record.mask.png" ]
}

@test "record mask: it forces the CPU, past a render node and past an explicit vaapi" {
  need_magick
  touch "$BATS_TEST_TMPDIR/renderD128"
  WIN="$(win 10 48 1884 963)" BORDER=2 ROUNDING=14 record_start auto mp4 window WINDOW_MASK=yes
  [ "$status" -eq 0 ]
  ! grep -q -- 'h264_vaapi' "$BATS_TEST_TMPDIR/argv"
  teardown; rm -rf "$BATS_TEST_TMPDIR/run" "$BATS_TEST_TMPDIR/argv"
  WIN="$(win 10 48 1884 963)" BORDER=2 ROUNDING=14 record_start vaapi mp4 window WINDOW_MASK=yes
  [ "$status" -eq 0 ]
  ! grep -q -- 'h264_vaapi' "$BATS_TEST_TMPDIR/argv"
}

@test "record mask: off by default — the GPU stays in use and no mask is built" {
  touch "$BATS_TEST_TMPDIR/renderD128"
  WIN="$(win 10 48 1884 963)" BORDER=2 ROUNDING=14 record_start auto mp4 window
  [ "$status" -eq 0 ]
  grep -q -- '-c h264_vaapi ' "$BATS_TEST_TMPDIR/argv"
  ! grep -q -- 'movie=' "$BATS_TEST_TMPDIR/argv"
}

@test "record mask: it applies to window only" {
  need_magick
  WIN="$(win 10 48 1884 963)" BORDER=2 ROUNDING=14 record_start cpu mp4 output WINDOW_MASK=yes
  [ "$status" -eq 0 ]
  ! grep -q -- 'movie=' "$BATS_TEST_TMPDIR/argv"
}

# ── Settings (w-record / w-screenshot get/set) ────────────────────────────────
#
# The Hub's only way into the `record` and `screenshot` layers. What these pin is
# the part the Hub cannot check for itself: a value the tool would refuse at start
# never gets stored, and the vaapi+webm pair is refused whichever key arrives last.

conf_env() {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin" "$HOME/.config/w"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/wf-recorder"
  chmod 755 "$bin/wf-recorder"
  PATH="$bin:$PATH"
  xdg_stub "$BATS_TEST_TMPDIR/videos"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" WCONF_HOME="$HOME" \
         WCONF_ETC="$BATS_TEST_TMPDIR/etc" WCONF_VENDOR_DIR="$REPO/rootfs/usr/share/w/defaults" \
         W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh" \
         W_CAPTURE_LIB="$REPO/rootfs/usr/lib/w/w-capture-lib.sh"
}
rec()  { run "$REPO/rootfs/usr/bin/w-record" "$@"; }
shot() { run "$REPO/rootfs/usr/bin/w-screenshot" "$@"; }

@test "record get: every setting at its vendor default, plus the installed backends" {
  conf_env
  rec get
  [ "$status" -eq 0 ]
  [ "$output" = $'RECORDER=wf\nENCODER=auto\nAUDIO=system\nFORMAT=mp4\nFRAMERATE=30\nWINDOW_MASK=no\nBACKENDS=wf' ]
}

@test "record set: lands in the user layer and get reads it back" {
  conf_env
  rec set FRAMERATE 60
  [ "$status" -eq 0 ]
  grep -q '^FRAMERATE=60$' "$HOME/.config/w/record.conf"
  rec get FRAMERATE
  [ "$output" = 60 ]
}

@test "record set: unknown keys and out-of-range values are usage errors, nothing written" {
  conf_env
  rec set BITRATE 8M;        [ "$status" -eq 2 ]
  rec set AUDIO both;        [ "$status" -eq 2 ]
  rec set FORMAT avi;        [ "$status" -eq 2 ]
  rec set FRAMERATE 0;       [ "$status" -eq 2 ]
  rec set FRAMERATE 241;     [ "$status" -eq 2 ]
  rec set RECORDER gsr;      [ "$status" -eq 2 ]
  rec set WINDOW_MASK maybe; [ "$status" -eq 2 ]
  rec get BITRATE;           [ "$status" -eq 2 ]
  [ ! -f "$HOME/.config/w/record.conf" ]
}

@test "record set: vaapi + webm is refused whichever key comes second" {
  conf_env
  rec set FORMAT webm;   [ "$status" -eq 0 ]
  rec set ENCODER vaapi; [ "$status" -eq 1 ]
  rec get ENCODER;       [ "$output" = auto ]
  rec set FORMAT mp4;    [ "$status" -eq 0 ]
  rec set ENCODER vaapi; [ "$status" -eq 0 ]
  rec set FORMAT webm;   [ "$status" -eq 1 ]
  rec get FORMAT;        [ "$output" = mp4 ]
}

@test "screenshot get/set: both keys round-trip, anything else is refused" {
  conf_env
  shot get
  [ "$output" = $'ANNOTATOR=flameshot\nWINDOW_SHADOW=yes' ]
  shot set ANNOTATOR satty;  [ "$status" -eq 0 ]
  shot get ANNOTATOR;        [ "$output" = satty ]
  shot set WINDOW_SHADOW no; [ "$status" -eq 0 ]
  shot get WINDOW_SHADOW;    [ "$output" = no ]
  shot set ANNOTATOR gimp;   [ "$status" -eq 2 ]
  shot set WINDOW_SHADOW 1;  [ "$status" -eq 2 ]
  shot set EDITOR satty;     [ "$status" -eq 2 ]
  shot get EDITOR;           [ "$status" -eq 2 ]
  grep -q '^ANNOTATOR=satty$' "$HOME/.config/w/screenshot.conf"
  grep -q '^WINDOW_SHADOW=no$' "$HOME/.config/w/screenshot.conf"
}
