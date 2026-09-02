# modules/gpu.sh — detect installed GPU(s) and install the matching driver stack.
# apply.sh context: runs on the live/installed system as root, on the TARGET
# hardware — this is where GPU detection belongs, NOT at ISO build time. The ISO
# is generic (built on a dev box); the actual GPU is only known once W boots on
# the machine, and shipping all three vendor stacks in the image would bloat it.
# Same reasoning as sensors.sh (hardware probe on the live system). Runs in the
# firstboot stage (apply --all); the final firstboot reboot activates early-KMS.
#
# Owns: vendor detection (lspci), driver-package install, and — for NVIDIA — the
# generation→driver mapping plus Hyprland/Wayland glue (modeset, early-KMS,
# session env, suspend services). Driver packages are hardware-specific, so they
# are installed imperatively here (like lm_sensors in sensors.sh), NOT listed in
# packages/pacman.txt (which installs unconditionally on every machine).
#
# NOTE: 64-bit only for now. lib32-* (multilib) variants for native Steam/Wine are
# deliberately deferred to a future gaming stack — they need the multilib repo.
# NOTE: a `w-gpu status` CLI (show GPUs/active driver/modeset state) is a future
# add; the module is self-contained without it.
# See package-gpu.md, installer.md (Session B), package-hyprland.md (env-hyprland).

# All display-class controllers (VGA 0300, 3D 0302, Display 0380), one per line,
# in `lspci -nn` form so both the vendor id ([10de:…]) and the chip codename
# (e.g. "AD104 [GeForce RTX 4070]") are available to the callers below.
gpu_lines() {
  lspci -nn 2>/dev/null \
    | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true
}

# NVIDIA chip codename → generation → correct package for our DKMS-on-zen setup.
# lspci pulls the codename from pci.ids (hwdata); its prefix is the nouveau family
# code, which matches the Arch driver table verbatim. Echoes "<repo>:<pkg>":
#   official:nvidia-open-dkms  — Turing and newer (upstream-recommended, extra repo)
#   aur:nvidia-580xx-dkms      — Volta/Pascal/Maxwell (legacy, still supported)
#   aur:nvidia-470xx-dkms      — Kepler (legacy, unsupported branch)
#   nouveau:                   — Fermi and older → no proprietary driver, mesa only
# The mainline nvidia branch (580+) dropped everything below Turing, hence the AUR
# legacy branches. Missing codename (brand-new card not yet in pci.ids) falls
# through to nvidia-open-dkms — safe, since the newest cards REQUIRE the open modules.
nvidia_pick_driver() {
  local code="$1"
  case "$code" in
    GB*|AD*|GA*|TU*)   echo "official:nvidia-open-dkms" ;;
    GV*|GP*|GM*)       echo "aur:nvidia-580xx-dkms"     ;;
    GK*)               echo "aur:nvidia-470xx-dkms"     ;;
    GF*|GT*|G[0-9]*)   echo "nouveau:"                  ;;
    *)                 echo "official:nvidia-open-dkms" ;;   # unknown → newest/open
  esac
}

# Merge a module list into mkinitcpio.conf's MODULES=(...), preserving any existing
# unmanaged entries and staying idempotent (re-running never duplicates tokens).
set_initramfs_modules() {
  local want="$1" cur kept new
  cur=$(grep -oP '^MODULES=\(\K[^)]*' /etc/mkinitcpio.conf 2>/dev/null || true)
  # Drop any tokens we manage, keep the rest, then append the desired set.
  kept=$(echo "$cur" | tr ' ' '\n' \
    | grep -vE '^(i915|nvidia|nvidia_modeset|nvidia_uvm|nvidia_drm)$' | tr '\n' ' ' || true)
  new=$(echo "$kept $want" | xargs || true)   # xargs normalises whitespace
  if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
    sed -i "s|^MODULES=(.*)|MODULES=($new)|" /etc/mkinitcpio.conf
  else
    echo "MODULES=($new)" >> /etc/mkinitcpio.conf
  fi
}

# ── NVIDIA ──────────────────────────────────────────────────────────────────────
gpu_setup_nvidia() {
  local codename="$1" hybrid="$2"   # hybrid=1 when an Intel iGPU is also present
  info "NVIDIA GPU detected (chip: ${codename:-unknown})."

  local pick repo pkg
  pick=$(nvidia_pick_driver "$codename"); repo="${pick%%:*}"; pkg="${pick#*:}"

  if [[ "$repo" == "nouveau" ]]; then
    echo "  WARN: NVIDIA $codename is Fermi-or-older — no supported proprietary driver." >&2
    echo "  WARN: falling back to the open-source nouveau/mesa stack." >&2
    return 0
  fi

  # DKMS relies on the running kernel's headers; linux-zen-headers is in base.txt
  # (paired by w-kernel on a kernel switch), so nvidia*-dkms rebuilds cleanly on zen.
  info "Installing $pkg (+ userspace + VA-API) from $repo..."
  case "$repo" in
    official) w_pac -S --needed --noconfirm "$pkg" nvidia-utils libva-nvidia-driver ;;
    aur)
      # nvidia-utils + egl-wayland are pulled as deps of the AUR legacy driver.
      local bu; bu=$(aur_build_user)
      [[ -n "$bu" ]] || die "No unprivileged user to build $pkg from AUR."
      run_yay "$bu" -S --needed --noconfirm --removemake \
              --answerdiff None --answerclean None "$pkg" \
        || die "AUR NVIDIA driver build failed ($pkg)."
      ;;
  esac

  # Kernel-mode-setting is mandatory for Wayland; fbdev auto-enables with modeset
  # (>=570.86.16). PreserveVideoMemoryAllocations set as a module option keeps VRAM
  # across suspend without touching the per-bootloader kernel cmdline. Own the file.
  info "Writing /etc/modprobe.d/nvidia.conf (modeset + suspend VRAM)..."
  cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# Managed by W mod_gpu. Enable DRM KMS (required for Wayland/Hyprland) and preserve
# video memory across suspend/hibernate. See package-gpu.md.
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

  # Early KMS: load the nvidia modules from the initramfs so the console/greeter come
  # up on the nvidia DRM node. On Intel+NVIDIA hybrids, i915 MUST precede nvidia or
  # Electron/CEF apps stall for up to a minute after boot (Hyprland wiki).
  local mods="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
  [[ "$hybrid" == "1" ]] && mods="i915 $mods"
  info "Enabling early KMS in mkinitcpio (MODULES: $mods)..."
  set_initramfs_modules "$mods"
  info "Regenerating initramfs..."
  # w-mkinitcpio rebuilds the bootloader-aware way: `limine-mkinitcpio` on the Limine
  # kernel-install/BLS path (rebuild + ESP staging in one step), classic `mkinitcpio -P`
  # on GRUB. mod_gpu runs after mod_limine, so the Limine tooling is already present.
  w-mkinitcpio

  # VRAM save/restore across sleep — the units ship with nvidia-utils. Guard: a given
  # branch may not carry all three.
  info "Enabling NVIDIA suspend/resume services..."
  systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service || true

  # Session env for the Wayland stack, sourced by env-hyprland (which reads
  # /etc/w/gpu-env.sh via a guard line). Only NVIDIA needs these; GBM_BACKEND is
  # intentionally NOT set (Hyprland wiki dropped it). See package-hyprland.md.
  info "Rendering /etc/w/gpu-env.sh (Wayland session env)..."
  install -d -m 755 /etc/w
  cat > /etc/w/gpu-env.sh <<'EOF'
# Managed by W mod_gpu — NVIDIA Wayland session environment.
# Sourced by /etc/xdg/uwsm/env-hyprland at graphical-session-pre. See package-gpu.md.
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
}

# ── Main ────────────────────────────────────────────────────────────────────────
mod_gpu() {
  info "Detecting GPU(s)..."
  command -v lspci &>/dev/null || w_pac -S --needed --noconfirm pciutils

  local lines; lines=$(gpu_lines)
  if [[ -z "$lines" ]]; then
    echo "  WARN: no display controller reported by lspci — installing generic mesa only." >&2
  else
    echo "$lines" | sed 's/^/  /'
  fi

  # Generic userspace is always safe and covers the dev VM's virtio-gpu (venus/virgl
  # via mesa) — the vendor branches below simply add nothing there.
  info "Installing generic Mesa + Vulkan loader..."
  w_pac -S --needed --noconfirm mesa vulkan-icd-loader

  local has_intel=0 has_amd=0 has_nvidia=0
  echo "$lines" | grep -qi '\[8086:' && has_intel=1
  echo "$lines" | grep -qi '\[1002:' && has_amd=1
  echo "$lines" | grep -qi '\[10de:' && has_nvidia=1

  if [[ "$has_intel" == "1" ]]; then
    info "Intel GPU detected — installing vulkan-intel + intel-media-driver (VA-API)..."
    w_pac -S --needed --noconfirm vulkan-intel intel-media-driver
  fi

  if [[ "$has_amd" == "1" ]]; then
    info "AMD GPU detected — installing vulkan-radeon + VA-API/VDPAU..."
    w_pac -S --needed --noconfirm vulkan-radeon libva-mesa-driver mesa-vdpau
  fi

  if [[ "$has_nvidia" == "1" ]]; then
    local codename
    codename=$(echo "$lines" | grep -i '\[10de:' \
      | grep -oiE '\b(GB|AD|GA|TU|GV|GP|GM|GK|GF|GT)[0-9]{2,3}\b' | head -1 || true)
    gpu_setup_nvidia "$codename" "$has_intel"
  else
    # Idempotency: a machine without NVIDIA must not carry stale nvidia glue (e.g.
    # after a GPU swap + re-apply). Leave mkinitcpio alone if nothing to strip.
    [[ -f /etc/w/gpu-env.sh ]] && { rm -f /etc/w/gpu-env.sh; info "Removed stale /etc/w/gpu-env.sh."; }
  fi

  info "GPU setup done. NVIDIA changes take effect after the next reboot."
}
