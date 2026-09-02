# modules/kbdlight.sh — keyboard backlight (w-kbdlight + initramfs boot light).
# Userspace layer: wired into apply.sh only (post-boot; the installer stays
# minimal-base), same as mod_power.
#
# Runtime control needs no setup at all: brightnessctl is already in the base and
# reaches the LED through logind, so the media keys and the bar block work as soon
# as the rootfs overlay lands. The one thing that DOES need wiring is the light at
# the disk-password prompt, which lives inside the initramfs — this module puts
# W's hook into /etc/mkinitcpio.conf and rebuilds the image.
#
# Machines with no keyboard backlight (desktops, VMs, most cheap laptops) are left
# completely alone: no hook, no initramfs rebuild, and the bar block auto-hides
# itself. The rebuild is also stamped, so a routine `apply.sh --all` does not pay
# for it twice. See w-kbdlight.md.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

MKINITCPIO_CONF="/etc/mkinitcpio.conf"
KBDLIGHT_STAMP="/var/lib/w/kbdlight.initramfs"

# Put `w-kbdlight` into the HOOKS array, immediately before whichever hook asks for
# the disk password (sd-encrypt on W's encrypted installs, encrypt on a classic
# busybox one) — the light has to be on BEFORE the prompt, not after it. With no
# encryption hook at all it goes before `filesystems`, which is still early enough
# to cover a slow boot. Prints "changed" on stdout when it rewrote the file.
kbdlight_wire_hooks() {
  local line inner out=() h placed=0
  [[ -r "$MKINITCPIO_CONF" ]] || { echo "  WARN: kbdlight: $MKINITCPIO_CONF not found" >&2; return 1; }

  line="$(grep -E '^HOOKS=\(' "$MKINITCPIO_CONF" | tail -1)" || true
  [[ -n "$line" ]] || { echo "  WARN: kbdlight: no HOOKS=(...) line in $MKINITCPIO_CONF" >&2; return 1; }

  inner="${line#HOOKS=(}"; inner="${inner%)}"
  # shellcheck disable=SC2206  # deliberate word-splitting: HOOKS is a bare word list
  local hooks=($inner)

  for h in "${hooks[@]}"; do
    [[ "$h" == "w-kbdlight" ]] && return 0   # already wired, nothing to do
  done

  for h in "${hooks[@]}"; do
    if (( ! placed )) && [[ "$h" == "sd-encrypt" || "$h" == "encrypt" || "$h" == "filesystems" ]]; then
      out+=("w-kbdlight"); placed=1
    fi
    out+=("$h")
  done
  (( placed )) || out+=("w-kbdlight")

  # Rewrite in place. Anchored on the exact old line so a commented-out example
  # HOOKS= line elsewhere in the file is left alone.
  local new="HOOKS=(${out[*]})"
  OLD="$line" NEW="$new" awk '
    $0 == ENVIRON["OLD"] && !done { print ENVIRON["NEW"]; done=1; next }
    { print }
  ' "$MKINITCPIO_CONF" > "$MKINITCPIO_CONF.w-tmp"
  mv "$MKINITCPIO_CONF.w-tmp" "$MKINITCPIO_CONF"
  echo changed
}

# What the baked image depends on: the level (a build-time snapshot) plus the hook
# and setter themselves. Any change here means the image on disk is stale.
kbdlight_want_stamp() {
  local lvl sum
  lvl="$(w-conf get kbdlight BOOT_LEVEL 50 2>/dev/null || echo 50)"
  sum="$( { cat /etc/initcpio/install/w-kbdlight /usr/lib/w/w-kbdlight-boot 2>/dev/null || true; } | sha256sum | cut -d' ' -f1)"
  echo "$lvl $sum"
}

mod_kbdlight() {
  # Post-boot only: the installer runs this module through apply.sh at firstboot.
  [[ -n "${MNT:-}" ]] && return 0

  if ! w-kbdlight device >/dev/null 2>&1; then
    ui_info "No keyboard backlight on this machine — nothing to configure."
    return 0
  fi

  local dev; dev="$(w-kbdlight device)"
  local rebuild="" want have
  if [[ -n "$(kbdlight_wire_hooks || true)" ]]; then rebuild=1; fi

  install -d -m755 /var/lib/w
  want="$(kbdlight_want_stamp)"
  have="$(cat "$KBDLIGHT_STAMP" 2>/dev/null || true)"
  if [[ "$have" != "$want" ]]; then rebuild=1; fi

  if [[ -n "$rebuild" ]]; then
    ui_info "Rebuilding the initramfs so the keyboard lights up at the boot prompt..."
    if w-mkinitcpio; then
      printf '%s\n' "$want" > "$KBDLIGHT_STAMP"
    else
      echo "  WARN: kbdlight: initramfs rebuild failed — the boot-time light will be stale" >&2
    fi
  fi

  ui_info "Keyboard backlight active (device: $dev). Status: w-kbdlight status; boot level: sudo w-kbdlight boot <N|off>."
}
