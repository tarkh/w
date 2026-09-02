# w-theme/wallpaper.sh — turn one arbitrary image into a theme's wallpaper set.
#
# Sourced by w-theme (not executable on its own). Everything here is ImageMagick;
# the colour work lives in palette.py.
#
# A theme ships one master per resolution tier ([[w-wallpaper]]), and the tiers
# are all 16:9. The picked file is whatever the user had — any aspect, any size,
# possibly a 1080p JPEG or a 6000px panorama — so the job is:
#
#   1. cover-crop to 16:9 about the centre (never letterbox: a wallpaper with
#      bars is worse than a wallpaper missing its edges),
#   2. render every tier from that crop, scaling up as readily as down — the
#      smaller tiers must exist even when the source is small, or a 1080p pick
#      would leave 4K monitors with no master at all,
#   3. write webp WHATEVER came in (png, jpeg, avif, …) — the format the
#      baseline theme uses (Qt reads it through qt6-imageformats, hyprpaper
#      natively), so a theme directory never carries the source format.
#
# Upscaling a small source is soft by definition; that is a property of the
# input, not a failure, and the UI says so before the user picks.

# Quality of the masters that land in the theme. Measured on the shipped 5K
# wallpaper: 95 costs ~1.2 MB per tier, while 100 — the value at which
# ImageMagick switches libwebp to LOSSLESS — costs ~6.9 MB and 6x the encode
# time for a difference no eye resolves on a desktop background.
WTHEME_WALLPAPER_QUALITY=95
# Renders that never ship at full size: the intermediate frame the palette is
# extracted from, and the small Hub preview tile.
WTHEME_WORK_QUALITY=90
WTHEME_PREVIEW_SIZE="640x480"   # Hub tiles are a hard 4:3

# Everything ImageMagick needs to know about an image, in one call.
# Prints "<width> <height> <format>".
wallpaper_probe() { # <file>
  magick identify -quiet -format '%w %h %m' "$1[0]" 2>/dev/null
}

# Reject what cannot become a wallpaper before doing minutes of work on it.
wallpaper_validate() { # <file>  → prints "<w> <h>", or a reason on stderr
  local file="$1" info w h fmt
  [[ -f "$file" ]] || { echo "w-theme: no such file: $file" >&2; return 1; }
  [[ -r "$file" ]] || { echo "w-theme: not readable: $file" >&2; return 1; }
  info="$(wallpaper_probe "$file")" || true
  [[ -n "$info" ]] || { echo "w-theme: not an image ImageMagick can read: $file" >&2; return 1; }
  read -r w h fmt <<<"$info"
  case "$fmt" in
    PNG|JPEG|WEBP|AVIF|HEIC|TIFF|BMP|JXL) ;;
    *) echo "w-theme: unsupported image format '$fmt' (use png/jpeg/webp/avif/heic/tiff/bmp/jxl)" >&2; return 1 ;;
  esac
  # Below this there is nothing left to upscale from — even the HD tier would be
  # a blur, and the palette extraction would be sampling noise.
  if (( w < 640 || h < 360 )); then
    echo "w-theme: image too small (${w}x${h}); 1920x1080 or larger is recommended" >&2
    return 1
  fi
  echo "$w $h"
}

# Render one tier. `^` resizes to COVER the box (the smaller side matches), then
# the centred crop takes the box out of it — the standard cover fit. `-strip`
# drops EXIF (orientation is already applied by then, and metadata has no place
# in a shipped theme); the sRGB conversion keeps wide-gamut sources from
# rendering differently in hyprpaper and Qt.
wallpaper_render_tier() { # <src> <WxH> <dest> [quality]
  magick "$1[0]" -quiet -auto-orient -colorspace sRGB -strip \
    -filter Lanczos -resize "$2^" -gravity center -extent "$2" \
    -quality "${4:-$WTHEME_WALLPAPER_QUALITY}" "$3"
}

# Build the full wallpaper/ directory of a theme plus its Hub preview.
# The tier list comes from w-wallpaper so there is one definition of it.
wallpaper_build_set() { # <src> <theme dir>
  local src="$1" dir="$2" tier rc=0
  install -d "$dir/wallpaper"
  while read -r tier; do
    [[ -n "$tier" ]] || continue
    wallpaper_render_tier "$src" "$tier" "$dir/wallpaper/wallpaper-$tier.webp" || rc=1
  done < <(w-wallpaper tiers --porcelain)
  (( rc == 0 )) || { echo "w-theme: wallpaper conversion failed" >&2; return 1; }

  # The preview is cropped from the same source rather than downscaled from a
  # tier: 4:3 out of the original keeps more of the image than 4:3 out of a
  # 16:9 crop would.
  wallpaper_render_tier "$src" "$WTHEME_PREVIEW_SIZE" "$dir/preview.webp" "$WTHEME_WORK_QUALITY"
}
