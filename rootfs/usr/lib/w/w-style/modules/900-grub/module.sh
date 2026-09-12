# w-style module: grub (system-scope) — bootloader menu colors + logo + selection.
# Defines only render_system (no user channel) → the orchestrator runs it solely
# under `apply all`/root, never at login. Band 900 = system-scope (boot/greeter).
# Self-contained: owns its GRUB_* paths (item_font is the font axis's, not ours).
DESC="GRUB bootloader colors + logo (next boot)"

GRUB_THEME_DIR="/boot/grub/themes/w"
GRUB_THEME_TXT="$GRUB_THEME_DIR/theme.txt"
GRUB_SELECT_DIR="$GRUB_THEME_DIR/select"

render_system() {
  require_root "apply grub"
  # Bootloader detection: on a Limine system GRUB is only an unsigned fallback loader —
  # skip theming it (saves the expensive grub-mkconfig + magick; the limine axis renders
  # the active menu instead). /etc/default/limine exists only on the encrypted/Limine path.
  [[ -f /etc/default/limine ]] && { echo "w-style: Limine active — skipping GRUB axis"; return 0; }
  require_magick "GRUB"
  load_conf "$(w_system_theme_dir)"
  echo "w-style: rendering GRUB colors..."

  [[ -f "$GRUB_THEME_TXT" ]] || { echo "w-style: GRUB theme not found: $GRUB_THEME_TXT" >&2; exit 1; }

  # Patch color keys in place (item_font is owned by the font axis: cmd_apply_font_grub)
  sed -i \
    -e "s|^desktop-color: .*|desktop-color: \"$W_GRUB_BG\"|" \
    -e "s|^\(\s*\)item_color = .*|\1item_color = \"$W_GRUB_ITEM\"|" \
    -e "s|^\(\s*\)selected_item_color = .*|\1selected_item_color = \"$W_GRUB_ITEM_SELECTED\"|" \
    "$GRUB_THEME_TXT"

  # Pull the active theme's logo into the GRUB theme dir. A theme's own mark is
  # copied verbatim; the inherited baseline is tinted in the theme's W_GRUB_LOGO
  # (-colorize 100 swaps every pixel's RGB, alpha — the anti-aliased edge — stays).
  # No W_GRUB_LOGO (a theme.conf generated before the key existed) → the baseline
  # mark as is, same as plymouth-logo.sh — never an unbound variable under set -u.
  local own; own="$(w_system_theme_dir)/$THEME_LOGO_REL"
  if [[ -f "$own" ]]; then cp "$own" "$GRUB_THEME_DIR/logo.png"
  elif [[ -n "${W_GRUB_LOGO:-}" ]]; then
    magick "$DEFAULT_THEME_DIR/$THEME_LOGO_REL" -fill "$W_GRUB_LOGO" -colorize 100 \
      "PNG32:$GRUB_THEME_DIR/logo.png"
  else cp "$DEFAULT_THEME_DIR/$THEME_LOGO_REL" "$GRUB_THEME_DIR/logo.png"; fi

  # Recolor the flat selection 9-patch in place (keeps each tile's dimensions;
  # no `identify` dependency — legacy tools may be absent in ImageMagick 7)
  if [[ -d "$GRUB_SELECT_DIR" ]]; then
    local f
    for f in "$GRUB_SELECT_DIR"/*.png; do
      magick "$f" -alpha off -fill "$W_GRUB_SELECT_BG" -colorize 100 "$f"
    done
  fi

  echo "  Regenerating GRUB config..."
  grub-mkconfig -o /boot/grub/grub.cfg
  echo "w-style: GRUB done (takes effect on next boot)."
}
