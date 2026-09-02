# w-style module: font (dual-scope) — the first theme axis spanning BOTH scopes.
# The source is the active theme's font.conf, falling back to the `w` baseline when
# omitted. Channels:
#   user (render_user)   → ~/.config fontconfig aliases · GTK gtk-font-name ·
#                          ghostty font-family/size · Quickshell font.json (Fonts singleton)
#   system (render_system) → /etc/fonts/local.conf · GRUB PF2
# Run as a user it touches only $HOME; run as root it renders the user channel into
# /etc/skel AND the system channels (so `sudo w-theme set` updates boot/greeter,
# matching the appearance↔grub scope split). User font changes are not live for
# already-running GTK/Qt apps (read at startup) — same limitation as appearance;
# ghostty is live via SIGUSR2, Quickshell live via FileView.
# Band 400 = toolkit palettes.
DESC="fonts (fontconfig + GTK + ghostty + Quickshell; system: local.conf + GRUB PF2)"

FONTCONFIG_USER_REL=".config/fontconfig/fonts.conf"
GTK3_SETTINGS_REL=".config/gtk-3.0/settings.ini"
GTK4_SETTINGS_REL=".config/gtk-4.0/settings.ini"
GHOSTTY_CONFIG_REL=".config/ghostty/config"
FOOT_CONFIG_REL=".config/foot/foot.ini"
QS_FONT_REL=".config/quickshell/w/core/font.json"

FONTCONFIG_SYSTEM="/etc/fonts/local.conf"       # system aliases (greeter + global fallback)
GRUB_THEME_DIR="/boot/grub/themes/w"
GRUB_THEME_TXT="$GRUB_THEME_DIR/theme.txt"
GRUB_FONT_FILE="$GRUB_THEME_DIR/w-font.pf2"     # generated PF2

# Locate a TTF for a family (prefer static .ttf over .ttc — grub-mkfont handles
# .ttf cleanly). Used for GRUB PF2 generation.
find_ttf() {
  local family="$1" style="${2:-Regular}" path
  # `|| true` on each: a `grep` with no match (or empty fc-list) returns non-zero →
  # `pipefail` would trip `set -e` before the next fallback runs. We want to fall
  # through to the broader query (and an empty $path is handled by the caller).
  path=$(fc-list "${family}:style=${style}" : file | grep -i '\.ttf' | head -1 | cut -d: -f1 | xargs) || true
  [[ -z "$path" ]] && { path=$(fc-list "${family}" : file | grep -i '\.ttf' | head -1 | cut -d: -f1 | xargs) || true; }
  [[ -z "$path" ]] && { path=$(fc-list "${family}" : file | head -1 | cut -d: -f1 | xargs) || true; }
  echo "$path"
}

# Patch ghostty's font-family/font-size in place (scope-aware), if a config exists.
# $1 = mono family, $2 = size. Ghostty re-reads this on SIGUSR2 (sent by w-theme),
# so a running terminal picks up the new font live.
patch_ghostty_font() {
  local family="$1" size="$2" target
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$GHOSTTY_CONFIG_REL"; else target="$HOME/$GHOSTTY_CONFIG_REL"; fi
  [[ -f "$target" ]] || return 0
  sed -i \
    -e "s|^font-family = .*|font-family = ${family}|" \
    -e "s|^font-size = .*|font-size = ${size}|" \
    "$target"
}

# Patch foot's `font=` line in place (scope-aware), if a config exists. Foot bundles
# family + size on one line: `font=<family>:size=<n>`. Not live (foot has no config-
# reload signal; SIGUSR1/2 only toggle color themes) — applies on next foot launch.
# $1 = mono family, $2 = size.
patch_foot_font() {
  local family="$1" size="$2" target
  if [[ $EUID -eq 0 ]]; then target="/etc/skel/$FOOT_CONFIG_REL"; else target="$HOME/$FOOT_CONFIG_REL"; fi
  [[ -f "$target" ]] || return 0
  sed -i "s|^font=.*|font=${family}:size=${size}|" "$target"
}

# GRUB PF2 (heavy: grub-mkfont + grub-mkconfig). Skipped when the embedded font
# already matches, so same-font theme switches don't pay the cost. W_FONT_* must
# already be loaded by the caller.
font_grub() {
  # Bootloader detection: on a Limine system GRUB is only an unsigned fallback loader —
  # skip theming it (saves the expensive grub-mkconfig + magick; the limine axis renders
  # the active menu instead). /etc/default/limine exists only on the encrypted/Limine path.
  [[ -f /etc/default/limine ]] && { echo "w-style: Limine active — skipping GRUB font axis"; return 0; }

  [[ -d "$GRUB_THEME_DIR" ]] \
    || { echo "  GRUB theme dir not found ($GRUB_THEME_DIR) — skipping GRUB font." >&2; return 0; }

  local pf2_name="${W_FONT_UI} Regular ${W_FONT_GRUB_SIZE}"
  if [[ -f "$GRUB_FONT_FILE" ]] && grep -q "item_font = \"${pf2_name}\"" "$GRUB_THEME_TXT" 2>/dev/null; then
    echo "  GRUB font unchanged (${pf2_name}) — skipping PF2 regen."
    return 0
  fi

  local ttf; ttf="$(find_ttf "$W_FONT_UI")"
  [[ -n "$ttf" ]] || { echo "  font not found: $W_FONT_UI — is it installed? Skipping GRUB font." >&2; return 0; }
  echo "  GRUB PF2: $pf2_name  ($ttf)"
  grub-mkfont -s "$W_FONT_GRUB_SIZE" --name "$pf2_name" "$ttf" -o "$GRUB_FONT_FILE" 2>/dev/null
  sed -i "s|item_font = .*|item_font = \"${pf2_name}\"|" "$GRUB_THEME_TXT"
  echo "  Regenerating GRUB config..."
  grub-mkconfig -o /boot/grub/grub.cfg
}

render_user() {
  load_font "$(resolve_theme_file "$(w_userscope_theme_dir)" font.conf)"
  echo "w-style: rendering fonts (user scope)..."

  # 1) Per-user fontconfig aliases (sans/serif → UI, monospace → mono).
  write_user_file "$FONTCONFIG_USER_REL" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- W Linux — generated by w-style. Do not edit; edit the theme's font.conf. -->
  <alias><family>sans-serif</family><prefer><family>${W_FONT_UI}</family></prefer></alias>
  <alias><family>serif</family><prefer><family>${W_FONT_UI}</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>${W_FONT_MONO}</family></prefer></alias>
</fontconfig>
EOF

  # 2) GTK3/4 default UI font (patch one key, preserve icon-theme/prefer-dark).
  patch_gtk_key "$GTK3_SETTINGS_REL" gtk-font-name "${W_FONT_UI} ${W_FONT_UI_SIZE}"
  patch_gtk_key "$GTK4_SETTINGS_REL" gtk-font-name "${W_FONT_UI} ${W_FONT_UI_SIZE}"

  # 3) Ghostty terminal font (mono); live via SIGUSR2 from w-theme.
  patch_ghostty_font "${W_FONT_MONO}" "${W_FONT_MONO_SIZE}"

  # 3b) Foot fallback terminal font (mono); live via SIGUSR1 from the foot axis.
  patch_foot_font "${W_FONT_MONO}" "${W_FONT_MONO_SIZE}"

  # 4) Quickshell font.json — Fonts.qml singleton reads it via FileView{watchChanges},
  #    so a running shell re-fonts live with no signal, like Colors/Motion.
  write_user_file "$QS_FONT_REL" <<EOF
{
  "_comment": "W Linux — generated by w-style. Do not edit; edit the theme's font.conf.",
  "ui":       "${W_FONT_UI}",
  "mono":     "${W_FONT_MONO}",
  "uiSize":   ${W_FONT_UI_SIZE},
  "monoSize": ${W_FONT_MONO_SIZE}
}
EOF

  echo "w-style: fonts done (user)."
}

# System-scope font channels (root): system fontconfig (greeter + global fallback)
# and GRUB PF2. Sourced from the system-fallback theme's font.conf.
render_system() {
  load_font "$(resolve_theme_file "$(w_system_theme_dir)" font.conf)"
  echo "w-style: rendering fonts (system scope)..."

  cat > "$FONTCONFIG_SYSTEM" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- W Linux system font aliases — generated by w-style. Edit the theme's font.conf. -->
  <alias><family>sans-serif</family><prefer><family>${W_FONT_UI}</family></prefer></alias>
  <alias><family>serif</family><prefer><family>${W_FONT_UI}</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>${W_FONT_MONO}</family></prefer></alias>
</fontconfig>
EOF
  fc-cache -f &>/dev/null || true

  font_grub
  echo "w-style: fonts done (system)."
}
