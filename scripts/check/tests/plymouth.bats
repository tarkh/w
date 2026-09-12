#!/usr/bin/env bats
# plymouth.bats — the boot splash's half of the "one logo, one size" contract.
#
# The brand mark is baked into every wallpaper master at a fixed pixel size and the
# wallpaper is cover-fitted to the panel, so the greeter and the desktop show it at
# <baked px> x <cover factor>. Plymouth draws a sprite instead and has no wallpaper
# to measure, so lib/w/plymouth-logo.sh renders logo.png at that size when the
# initramfs is built, and the theme's w.script repeats the arithmetic at boot as a
# fallback for a display that changed since.
#
# Two things therefore need holding still, and neither has a linter:
#   * the sizing helper — pure bash, tested here against a fake DRM sysfs;
#   * w.script's copy of the tier ladder — a different language entirely, so the
#     drift check below is the only thing standing between it and w-wallpaper.

load helpers

setup() {
  W_WALLPAPER_BIN="$REPO/rootfs/usr/bin/w-wallpaper"
  # shellcheck source=/dev/null
  source "$REPO/rootfs/usr/lib/w/plymouth-logo.sh"
  W_PLYMOUTH_BASE_THEME="$REPO/rootfs/etc/w/themes/w"   # the helper hardcodes /etc; point at the repo copy
  DRM="$BATS_TEST_TMPDIR/drm"
  mkdir -p "$DRM"
}

# Fake a DRM connector: <name> <status> [mode ...]
drm_connector() {
  local name="$1" status="$2"; shift 2
  mkdir -p "$DRM/card1-$name"
  echo "$status" > "$DRM/card1-$name/status"
  printf '%s\n' "$@" > "$DRM/card1-$name/modes"
}

@test "plymouth_panel_geometry: preferred mode of a single connected output" {
  drm_connector DP-1 connected 3840x2160 2560x1440
  [[ "$(plymouth_panel_geometry "$DRM")" == "3840x2160" ]]
}

@test "plymouth_panel_geometry: the internal panel wins over a bigger external one" {
  drm_connector DP-1 connected 3840x2160
  drm_connector eDP-1 connected 2880x1800
  [[ "$(plymouth_panel_geometry "$DRM")" == "2880x1800" ]]
}

@test "plymouth_panel_geometry: widest connected output when there is no internal panel" {
  drm_connector HDMI-A-1 connected 1920x1080
  drm_connector DP-2 connected 2560x1440
  [[ "$(plymouth_panel_geometry "$DRM")" == "2560x1440" ]]
}

@test "plymouth_panel_geometry: disconnected outputs are ignored" {
  drm_connector DP-1 disconnected
  drm_connector HDMI-A-1 connected 1920x1080
  [[ "$(plymouth_panel_geometry "$DRM")" == "1920x1080" ]]
}

@test "plymouth_panel_geometry: fails when nothing reports a mode (headless, no KMS)" {
  drm_connector DP-1 connected ""
  run plymouth_panel_geometry "$DRM"
  [[ "$status" -ne 0 ]]
  [[ -z "$output" ]]
}

@test "plymouth_logo_px: master size x the cover factor of the displayed tier" {
  # 2880x1800 displays the 2560x1440 master; 1800/1440 = 1.25 → 256 * 1.25.
  [[ "$(plymouth_logo_px "$W_PLYMOUTH_BASE_THEME" 2880x1800)" == "320" ]]
}

@test "plymouth_logo_px: a panel that is its tier keeps the master size" {
  [[ "$(plymouth_logo_px "$W_PLYMOUTH_BASE_THEME" 1920x1080)" == "256" ]]
}

@test "plymouth_logo_px: falls back to the master size when the panel is unknown" {
  # No geometry to be had (no KMS): the answer must still be usable, never empty.
  [[ "$(plymouth_logo_px "$W_PLYMOUTH_BASE_THEME" "not-a-geometry")" == "256" ]]
}

@test "plymouth_logo_px: unresolvable cover factor still yields the master size" {
  W_WALLPAPER_BIN="$BATS_TEST_TMPDIR/absent"
  [[ "$(plymouth_logo_px "$W_PLYMOUTH_BASE_THEME" 2880x1800)" == "256" ]]
}

@test "plymouth_logo_source_png: theme's own logo wins, baseline is the fallback" {
  local theme="$BATS_TEST_TMPDIR/theme"
  mkdir -p "$theme/logo"
  [[ "$(plymouth_logo_source_png "$theme")" == "$W_PLYMOUTH_BASE_THEME/$W_PLYMOUTH_LOGO_PNG_REL" ]]
  touch "$theme/$W_PLYMOUTH_LOGO_PNG_REL"
  [[ "$(plymouth_logo_source_png "$theme")" == "$theme/$W_PLYMOUTH_LOGO_PNG_REL" ]]
}

# The tint contract: a theme without a logo/ inherits the brand vector and gets
# it in its own W_PLYMOUTH_LOGO; a theme with its own mark keeps it untouched.
# Both need ImageMagick (the renderer) — skipped where it is absent.
ink_pixel()  { magick "$1" -format '%[hex:p{128,128}]' info:; } # centre of the mark (256px)

@test "plymouth_logo_install: inherited mark is tinted in W_PLYMOUTH_LOGO, alpha intact" {
  command -v magick &>/dev/null || skip "imagemagick not installed"
  local theme="$BATS_TEST_TMPDIR/theme" out="$BATS_TEST_TMPDIR"
  mkdir -p "$theme"
  plymouth_logo_install "$theme" "$out/plain.png" 1920x1080 >/dev/null
  W_PLYMOUTH_LOGO="#2e7d32" plymouth_logo_install "$theme" "$out/tint.png" 1920x1080 >/dev/null
  [[ "$(ink_pixel "$out/tint.png")" == "2E7D32FF" ]]
  [[ "$(ink_pixel "$out/plain.png")" == "643670FF" ]]
  # tinting only touches RGB: the anti-aliased edge (alpha) is the same raster
  local ae; ae="$(magick compare -metric AE \( "$out/plain.png" -alpha extract \) \
                                         \( "$out/tint.png" -alpha extract \) null: 2>&1)"
  [[ "${ae%% *}" == "0" ]]   # "0 (0)" — absolute error count, then normalised
}

@test "plymouth_logo_install: a theme's own mark is never tinted" {
  command -v magick &>/dev/null || skip "imagemagick not installed"
  local theme="$BATS_TEST_TMPDIR/theme" out="$BATS_TEST_TMPDIR/own.png"
  mkdir -p "$theme/logo"
  sed 's/fill:#643670/fill:#0000ff/' "$W_PLYMOUTH_BASE_THEME/$W_PLYMOUTH_LOGO_SVG_REL" \
    > "$theme/$W_PLYMOUTH_LOGO_SVG_REL"
  W_PLYMOUTH_LOGO="#2e7d32" plymouth_logo_install "$theme" "$out" 1920x1080 >/dev/null
  [[ "$(ink_pixel "$out")" == "0000FFFF" ]]
}

@test "w.script: its tier ladder still matches w-wallpaper's" {
  local script="$REPO/rootfs/usr/share/plymouth/themes/w/w.script"
  # The ladder as w.script spells it: tier_w[0] = 5120; tier_h[0] = 2880;
  local from_script
  from_script="$(sed -n 's/^tier_w\[[0-9]\+\] *= *\([0-9]\+\); *tier_h\[[0-9]\+\] *= *\([0-9]\+\);.*/\1x\2/p' "$script")"
  local from_tool
  from_tool="$(bash "$W_WALLPAPER_BIN" tiers --porcelain)"
  [[ -n "$from_script" ]]
  [[ "$from_script" == "$from_tool" ]]
  # TIER_COUNT must agree too, or the loop would walk past the ladder.
  local declared count
  declared="$(sed -n 's/^TIER_COUNT *= *\([0-9]\+\);.*/\1/p' "$script")"
  count="$(wc -l <<< "$from_tool")"
  [[ "$declared" == "$count" ]]
}

@test "w.script: LOGO_MASTER_PX still matches the theme's logo asset" {
  local script="$REPO/rootfs/usr/share/plymouth/themes/w/w.script"
  local declared asset
  declared="$(sed -n 's/^LOGO_MASTER_PX *= *\([0-9]\+\);.*/\1/p' "$script")"
  # The asset carries its size in its name (w-style's THEME_LOGO_REL).
  asset="$(sed -n 's|^THEME_LOGO_REL="logo/W-logo-\([0-9]\+\)x[0-9]\+\.png"|\1|p' \
             "$REPO/rootfs/usr/lib/w/w-style/lib/core.sh")"
  [[ -n "$declared" && -n "$asset" ]]
  [[ "$declared" == "$asset" ]]
  [[ "$declared" == "$(sed -n 's|^W_PLYMOUTH_LOGO_PNG_REL="logo/W-logo-\([0-9]\+\)x[0-9]\+\.png"|\1|p' \
                         "$REPO/rootfs/usr/lib/w/plymouth-logo.sh")" ]]
}
