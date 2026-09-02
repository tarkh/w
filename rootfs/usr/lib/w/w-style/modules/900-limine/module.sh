# w-style module: limine (system-scope) — Limine boot menu palette + centered logo.
# Defines only render_system (no user channel) → runs under `apply all`/root, next boot.
# Band 900 = system-scope (boot/greeter). Self-contained: owns the ESP limine.conf theme
# header (top-level keys) + the staged logo PNG. limine-entry-tool only ADDS/updates kernel
# entries and leaves the top-level settings intact, so these survive kernel updates.
#
# Bootloader detection: this axis is a no-op unless a Limine ESP config is present, and the
# grub axis is a no-op when Limine is active — only the active bootloader is themed (the
# other stays default to save the expensive grub-mkconfig/magick or a pointless render).
DESC="Limine bootloader palette + centered logo (next boot)"

render_system() {
  require_root "apply limine"

  # ESP path (Limine can't read the LUKS root; the config + staged files live on the ESP).
  local esp="/boot/efi"
  [[ -f /etc/default/limine ]] && esp="$(awk -F'"' '/^ESP_PATH=/{print $2}' /etc/default/limine)"
  esp="${esp:-/boot/efi}"
  local conf="$esp/limine.conf"

  # Detection: only theme an actual Limine system.
  [[ -f "$conf" ]] || { echo "w-style: no Limine config ($conf) — skipping limine axis"; return 0; }

  load_conf "$(w_system_theme_dir)"
  echo "w-style: rendering Limine palette..."

  # Drop any stale logo staged by an older render (menu sat over a centered logo — the
  # logo now lives only in GRUB/Plymouth; Limine is a plain branded solid background).
  rm -f "$esp/w-logo.png"

  # Limine colours are RRGGBB with NO leading '#'. Build the 8+8 ANSI palettes.
  local pal palb
  pal="$(hexcat "$W_TERM_ANSI_BLACK" "$W_TERM_ANSI_RED" "$W_TERM_ANSI_GREEN" "$W_TERM_ANSI_YELLOW" \
                "$W_TERM_ANSI_BLUE" "$W_TERM_ANSI_MAGENTA" "$W_TERM_ANSI_CYAN" "$W_TERM_ANSI_WHITE")"
  palb="$(hexcat "$W_TERM_ANSI_BRIGHT_BLACK" "$W_TERM_ANSI_BRIGHT_RED" "$W_TERM_ANSI_BRIGHT_GREEN" \
                 "$W_TERM_ANSI_BRIGHT_YELLOW" "$W_TERM_ANSI_BRIGHT_BLUE" "$W_TERM_ANSI_BRIGHT_MAGENTA" \
                 "$W_TERM_ANSI_BRIGHT_CYAN" "$W_TERM_ANSI_BRIGHT_WHITE")"

  # Idempotent top-level key patches (replace-or-insert). No logo: a plain solid brand
  # background. Without a wallpaper the screen fill is term_background (the terminal fills
  # the screen at term_margin 0), NOT backdrop (which only paints centered-wallpaper gaps).
  # term_background takes an opaque 6-digit RRGGBB; backdrop is set to match as a fallback.
  limine_del_kv "$conf" "wallpaper"
  limine_del_kv "$conf" "wallpaper_style"
  limine_set_kv "$conf" "backdrop"                  "${W_BG#\#}"
  limine_set_kv "$conf" "term_background"           "${W_BG#\#}"
  limine_set_kv "$conf" "term_palette"              "$pal"
  limine_set_kv "$conf" "term_palette_bright"       "$palb"
  limine_set_kv "$conf" "term_foreground"           "${W_TERM_FG#\#}"
  limine_set_kv "$conf" "interface_branding"        "W Linux"
  limine_set_kv "$conf" "interface_branding_colour" "${W_PRIMARY#\#}"
  limine_set_kv "$conf" "interface_help_hidden"     "yes"
  limine_set_kv "$conf" "interface_help_colour"     "${W_ON_SURFACE_VARIANT#\#}"

  # Under Secure Boot the config hash is enrolled into the signed binary → re-enroll now
  # that limine.conf changed (cheap: recompute BLAKE2B + re-sign; no disk re-encryption).
  # The hash-free fallback Limine keeps a botched enroll from ever blocking boot.
  if command -v w-secureboot &>/dev/null \
     && grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=yes' /etc/default/limine 2>/dev/null; then
    echo "  Secure Boot active → re-enrolling Limine config hash..."
    w-secureboot reenroll || echo "w-style: limine config-hash re-enroll failed (fallback boot still works)" >&2
  fi

  echo "w-style: Limine done (takes effect on next boot)."
}

# Join HEX colours ('#rrggbb' → 'rrggbb') with ';' for a Limine term_palette value.
hexcat() {
  local out="" c
  for c in "$@"; do out="${out:+$out;}${c#\#}"; done
  echo "$out"
}

# Delete a top-level `key: value` line from limine.conf (idempotent — a no-op if absent).
# Needed because limine_set_kv can only replace-or-insert, never remove a retired key.
limine_del_kv() {
  local file="$1" key="$2"
  sed -i "/^${key}:/d" "$file"
}

# Replace-or-insert a top-level `key: value` line in limine.conf. Insert goes right after
# the leading comment header so entries (which start with '/') are never disturbed.
limine_set_kv() {
  local file="$1" key="$2" val="$3"
  if grep -q "^${key}:" "$file"; then
    sed -i "s|^${key}:.*|${key}: ${val}|" "$file"
  else
    # Insert after the last leading comment line (before the first non-comment line).
    sed -i "0,/^[^#]/s|^\([^#]\)|${key}: ${val}\n\1|" "$file"
  fi
}
