# w-style module: plymouth (system-scope) — the boot splash colours. Renders 2x2
# solid swatches (bar + bar background) and pulls the active theme's logo into the
# Plymouth theme dir, then rebuilds the initramfs (Plymouth runs from there, not
# /usr/share). Source is the system-fallback theme. Not live: takes effect on next
# boot. Band 900 = system-scope surfaces.
DESC="boot splash colours (Plymouth)"

PLYMOUTH_DIR="/usr/share/plymouth/themes/w"

render_system() {
  require_root "apply plymouth"
  require_magick "Plymouth"
  load_conf "$(w_system_theme_dir)"
  echo "w-style: rendering Plymouth colors..."

  [[ -d "$PLYMOUTH_DIR" ]] || { echo "w-style: Plymouth theme not found: $PLYMOUTH_DIR" >&2; exit 1; }

  # 2x2 solid swatches; opacity is applied by w.script, not baked here
  magick -size 2x2 "xc:$W_PLYMOUTH_BAR"    "$PLYMOUTH_DIR/bar.png"
  magick -size 2x2 "xc:$W_PLYMOUTH_BAR_BG" "$PLYMOUTH_DIR/bar-bg.png"

  # Password-prompt dot placeholder (LUKS unlock) — a filled brand circle, 32px so w.script
  # can scale it down crisply. Same accent as the bar fill; the underline reuses the bar swatch.
  magick -size 32x32 xc:none -fill "$W_PLYMOUTH_BAR" -draw 'circle 15.5,15.5 15.5,1' \
    "$PLYMOUTH_DIR/bullet.png"

  # Flat lock glyph under the password field — shackle arc + rounded body, keyhole punched
  # out (DstOut of a white mask). 64px, scaled by w.script. Brand accent.
  magick -size 64x64 xc:none \
    -stroke "$W_PLYMOUTH_BAR" -strokewidth 8 -fill none -draw 'arc 20,13 44,41 180,360' \
    -stroke none -fill "$W_PLYMOUTH_BAR" -draw 'roundrectangle 14,32 50,59 6,6' \
    \( -size 64x64 xc:none -fill white \
       -draw 'circle 32,43 32,47' -draw 'polygon 30,43 34,43 36,54 28,54' \) \
    -alpha on -compose DstOut -composite \
    "$PLYMOUTH_DIR/lock.png"

  # Pull the active theme's logo (baseline fallback) into the Plymouth theme dir
  cp "$(resolve_theme_file "$(w_system_theme_dir)" "$THEME_LOGO_REL")" "$PLYMOUTH_DIR/logo.png"

  # Plymouth runs from the initramfs, not /usr/share — rebuild so colors apply. w-mkinitcpio
  # calls the real /usr/bin/mkinitcpio (bypassing the limine-mkinitcpio-hook prompt that
  # would otherwise appear under `sudo w-theme`) and restages the ESP on Limine systems.
  echo "  Rebuilding initramfs (Plymouth theme is bundled there)..."
  w-mkinitcpio

  echo "w-style: Plymouth done (takes effect on next boot)."
}
