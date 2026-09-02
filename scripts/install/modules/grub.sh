# modules/grub.sh — GRUB customization (theme, branding, boot UX)
# Works in both install context (MNT/chroot) and live system (apply.sh).
# In install context: MNT and chroot_run/chroot_sh must be set by caller.
# In apply context: operates directly on /, MNT="".

# Compatibility shim: apply.sh uses info(), install context uses ui_info()
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

# Idempotent setter for /etc/default/grub: replace KEY= line, or append it.
# Single source of truth — re-running always converges to <value>.
grub_set_kv() {
  local file="$1" key="$2" val="$3"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$file"
  else
    echo "${key}=\"${val}\"" >> "$file"
  fi
}

mod_grub() {
  local mnt="${MNT:-}"
  local grub_default="${mnt}/etc/default/grub"
  local theme_dest="${mnt}/boot/grub/themes/w"
  local theme_path="/boot/grub/themes/w/theme.txt"

  # ── Settings ────────────────────────────────────────────────────────────────
  local grub_distributor="W"          # menu entry name → "W Linux"
  local grub_terminal_output="gfxterm" # graphical terminal — required for theme
  local grub_timeout_style="hidden"   # menu hidden; Shift/Esc to reveal
  local grub_timeout=1                 # seconds to wait before booting

  ui_info "Deploying GRUB theme..."
  mkdir -p "$theme_dest/select"
  rsync -a --chown=root:root "$SRC/rootfs/boot/grub/themes/w/" "$theme_dest/"

  # Seed the logo from the baseline theme (w-style later swaps it per active theme)
  cp "$SRC/rootfs/etc/w/themes/w/logo/W-logo-256x256.png" "$theme_dest/logo.png"

  # Copy unicode font (not stored in rootfs — large file, always present on system)
  local font_src
  if [[ -f "${mnt}/usr/share/grub/unicode.pf2" ]]; then
    font_src="${mnt}/usr/share/grub/unicode.pf2"
  else
    font_src="/usr/share/grub/unicode.pf2"
  fi
  cp "$font_src" "$theme_dest/unicode.pf2"

  ui_info "Patching /etc/default/grub..."
  grub_set_kv "$grub_default" GRUB_DISTRIBUTOR     "$grub_distributor"
  grub_set_kv "$grub_default" GRUB_TERMINAL_OUTPUT "$grub_terminal_output"
  grub_set_kv "$grub_default" GRUB_TIMEOUT_STYLE   "$grub_timeout_style"
  grub_set_kv "$grub_default" GRUB_TIMEOUT         "$grub_timeout"
  grub_set_kv "$grub_default" GRUB_THEME           "$theme_path"

  ui_info "Silencing GRUB boot messages (patching 10_linux)..."
  local linux_script="${mnt}/etc/grub.d/10_linux"
  [[ -f "$linux_script" ]] && sed -i '/echo.*message.*grub_quote/d' "$linux_script"

  ui_info "Deploying pacman hook for grub updates..."
  mkdir -p "${mnt}/etc/pacman.d/hooks"
  cp "$SRC/rootfs/etc/pacman.d/hooks/grub-silence.hook" "${mnt}/etc/pacman.d/hooks/grub-silence.hook"

  ui_info "Regenerating GRUB config..."
  if [[ -n "$mnt" ]]; then
    chroot_run grub-mkconfig -o /boot/grub/grub.cfg
  else
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}
