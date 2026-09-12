# plymouth-logo.sh — size and render the boot splash logo (sourced, no side effects).
#
# The brand W appears on three screens in a row: the Plymouth splash, the login
# wallpaper and the desktop wallpaper. The wallpapers carry it baked in at a fixed
# pixel size and are cover-fitted to the panel, so its on-screen size there is
#   <baked px> x <cover factor of the master that gets displayed>
# (see wallpaper_cover_factor in w-wallpaper — the one definition of that number).
# Plymouth draws a sprite instead, so to land on the same size it must render the
# logo at exactly that many pixels. That is what this file does, at the moment the
# initramfs is built, which is also the only moment the panel's resolution is
# knowable — Plymouth itself runs long before anything can query a display.
#
# Rendering here rather than scaling at boot is deliberate: Plymouth's own scaler
# (ply_pixel_buffer_resize) is a bare bilinear sampler with no area averaging, while
# ImageMagick rasterises the vector master at the target size. The theme's w.script
# keeps a fallback rescale for the case where the display changed since this ran.
#
# Colour: a theme that ships its own logo/ owns the mark verbatim. A theme
# without one inherits the brand vector and gets it tinted in its own accent —
# W_PLYMOUTH_LOGO from theme.conf, visible here when the caller has sourced the
# theme (w-style's load_conf). Unset → the inherited mark keeps its baked fill,
# which is what apply.sh and the installer want for the baseline.
#
# Sourced by: w-style's 900-plymouth module (theme switch), apply.sh (--plymouth)
# and the installer's mod_plymouth (install-time initramfs). Callers that are not
# on a live W system point W_WALLPAPER_BIN at their own copy of w-wallpaper.

# Where the tier ladder and the cover factor live. Overridable so the installer and
# apply.sh can use the repo copy before /usr/bin is populated.
W_WALLPAPER_BIN="${W_WALLPAPER_BIN:-/usr/bin/w-wallpaper}"

# Logo assets inside a theme, mirroring w-style's core.sh (this file is sourced in
# contexts where that SDK is not available, so the two names are repeated here; the
# `paths` suite keeps them in sync).
W_PLYMOUTH_LOGO_PNG_REL="logo/W-logo-256x256.png"
W_PLYMOUTH_LOGO_SVG_REL="logo/W-logo.svg"
W_PLYMOUTH_BASE_THEME="/etc/w/themes/w"

# Panel Plymouth will draw on, as WIDTHxHEIGHT physical pixels, read from DRM
# sysfs (available in the installer chroot and on a live system alike, with or
# without a compositor). The internal panel wins when there is one — that is the
# screen a laptop boots on; otherwise the widest connected output. Prints nothing
# and fails when no output reports a mode (headless, VM without KMS).
plymouth_panel_geometry() { # [sysfs drm root]
  local root="${1:-/sys/class/drm}" conn status mode name best="" best_w=0
  for conn in "$root"/card*-*; do
    [[ -r "$conn/status" && -r "$conn/modes" ]] || continue
    read -r status < "$conn/status" || continue
    [[ "$status" == "connected" ]] || continue
    mode=""; read -r mode < "$conn/modes" || true
    [[ "$mode" =~ ^([0-9]+)x([0-9]+) ]] || continue
    name="${conn##*/}"
    case "$name" in
      *eDP*|*LVDS*|*DSI*) echo "${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"; return 0 ;;
    esac
    if (( BASH_REMATCH[1] > best_w )); then
      best_w="${BASH_REMATCH[1]}"
      best="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
    fi
  done
  if [[ -n "$best" ]]; then echo "$best"; return 0; fi
  return 1
}

# Pixel size the logo must be drawn at on this machine. Falls back to the baked
# size of the theme's own master (i.e. today's behaviour) whenever the panel or the
# factor cannot be determined — never fails, so no caller has to branch on it.
plymouth_logo_px() { # <theme dir> [WIDTHxHEIGHT]
  local dir="$1" panel="${2:-}" nominal factor png
  png=$(plymouth_logo_source_png "$dir")
  nominal=$(magick identify -quiet -format '%w' "$png" 2>/dev/null) || nominal=""
  [[ "$nominal" =~ ^[0-9]+$ ]] || nominal=256

  [[ -n "$panel" ]] || panel=$(plymouth_panel_geometry) || panel=""
  [[ "$panel" =~ ^([0-9]+)x([0-9]+)$ ]] || { echo "$nominal"; return 0; }

  factor=$(plymouth_cover_factor "$dir" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}") || factor=""
  [[ "$factor" =~ ^[0-9.]+$ ]] || { echo "$nominal"; return 0; }

  awk -v n="$nominal" -v f="$factor" 'BEGIN { printf "%d\n", int(n * f + 0.5) }'
}

# Cover factor via w-wallpaper's resolver — sourced, not executed, so it can be
# asked about a SPECIFIC theme directory (the installer has no active theme yet, and
# root's HOME must not decide which theme the splash is built for). The source runs
# in a subshell: w-wallpaper sets shell options and defines its own `usage`/`cmd_*`,
# neither of which may leak into a caller like apply.sh.
plymouth_cover_factor() { # <theme dir> <width> <height>
  local dir="$1" w="$2" h="$3"
  [[ -r "$W_WALLPAPER_BIN" ]] || return 1
  (
    # shellcheck source=/dev/null
    source "$W_WALLPAPER_BIN" || exit 1
    wallpaper_cover_factor "$dir/wallpaper" "$w" "$h"
  )
}

# The PNG master of a theme's logo, with the baseline fallback (a theme without a
# logo/ inherits the brand mark, exactly as w-style's resolve_theme_file does).
plymouth_logo_source_png() { # <theme dir>
  local dir="$1"
  if [[ -f "$dir/$W_PLYMOUTH_LOGO_PNG_REL" ]]; then echo "$dir/$W_PLYMOUTH_LOGO_PNG_REL"
  else echo "$W_PLYMOUTH_BASE_THEME/$W_PLYMOUTH_LOGO_PNG_REL"; fi
}

# Render <theme dir>'s logo into <dest> at the size this machine needs.
#
# Source preference: the theme's OWN vector master (any size, crisp) → the theme's
# own PNG (a theme that ships a recoloured mark must not be rendered from another
# theme's vector) → the baseline vector → the baseline PNG. PNG sources go through
# Lanczos; the vector is rasterised at >=2x the target and downsampled, which keeps
# the curved edges clean at any size. An inherited baseline is tinted with
# W_PLYMOUTH_LOGO when set: -colorize 100 replaces every pixel's RGB and leaves the
# alpha alone, so the anti-aliased edge survives and the ink is one flat colour.
plymouth_logo_install() { # <theme dir> <dest> [WIDTHxHEIGHT]
  local dir="$1" dest="$2" panel="${3:-}" px src density tint=()

  px=$(plymouth_logo_px "$dir" "$panel")

  if   [[ -f "$dir/$W_PLYMOUTH_LOGO_SVG_REL" ]]; then src="$dir/$W_PLYMOUTH_LOGO_SVG_REL"
  elif [[ -f "$dir/$W_PLYMOUTH_LOGO_PNG_REL" ]]; then src="$dir/$W_PLYMOUTH_LOGO_PNG_REL"
  else
    if [[ -f "$W_PLYMOUTH_BASE_THEME/$W_PLYMOUTH_LOGO_SVG_REL" ]]; then
      src="$W_PLYMOUTH_BASE_THEME/$W_PLYMOUTH_LOGO_SVG_REL"
    else src=$(plymouth_logo_source_png "$dir"); fi
    [[ -z "${W_PLYMOUTH_LOGO:-}" ]] || tint=(-fill "$W_PLYMOUTH_LOGO" -colorize 100)
  fi

  if [[ "$src" == *.svg ]]; then
    # 96 dpi renders the master at its natural size; scale the dpi so the raster is
    # at least twice the target, never below the natural size.
    density=$(awk -v px="$px" 'BEGIN { d = 96 * 2 * px / 998; if (d < 96) d = 96; printf "%d\n", d + 1 }')
    magick -background none -density "$density" "$src" \
      -filter Lanczos -resize "${px}x${px}" \
      -background none -gravity center -extent "${px}x${px}" "${tint[@]}" "PNG32:$dest"
  else
    magick "$src" -background none -filter Lanczos -resize "${px}x${px}" \
      -background none -gravity center -extent "${px}x${px}" "${tint[@]}" "PNG32:$dest"
  fi
  echo "  logo: ${px}px (${panel:-$(plymouth_panel_geometry || echo 'panel unknown')})${tint[1]:+, tint ${tint[1]}}"
}
