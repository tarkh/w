# modules/gpu.sh — detect installed GPU(s) and install the matching driver stack.
# apply.sh context: runs on the live/installed system as root, on the TARGET
# hardware — this is where GPU detection belongs, NOT at ISO build time. The ISO
# is generic (built on a dev box); the actual GPU is only known once W boots on
# the machine, and shipping all three vendor stacks in the image would bloat it.
# Same reasoning as sensors.sh (hardware probe on the live system). Runs in the
# firstboot stage (apply --all); the final firstboot reboot activates early-KMS.
#
# Detection (vendor id, NVIDIA codename→driver mapping) lives in the shared
# w-gpu-lib.sh seam (sourced by apply.sh via lib/gpu.sh — see gaming-plan.md
# Session 1), because packs/ai-extra and packs/comfyui need the exact same
# classifier and a third copy would have been the drift this project gates
# away. This module stays the owner of INSTALLATION and the NVIDIA/Hyprland
# glue (modeset, early-KMS, session env, suspend services). Driver packages
# are hardware-specific, so they are installed imperatively here (like
# lm_sensors in sensors.sh), NOT listed in packages/pacman.txt (which installs
# unconditionally on every machine).
#
# NOTE: 64-bit only here. lib32-* (multilib) for native Steam/Wine lives in
# w_gpu_lib32_packages — it belongs to the `gaming` pack (gaming-plan.md), not
# to this module: multilib itself is a repo the pack's pre.sh enables, and this
# module runs long before any pack does.
# NOTE: a `w-gpu status` CLI (show GPUs/active driver/modeset state) is a future
# add; the module is self-contained without it.
# See package-gpu.md, installer.md (Session B), package-hyprland.md (env-hyprland).

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
  pick=$(w_gpu_nvidia_driver "$codename"); repo="${pick%%:*}"; pkg="${pick#*:}"

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

  local lines; lines=$(w_gpu_lines)
  if [[ -z "$lines" ]]; then
    echo "  WARN: no display controller reported by lspci — installing generic mesa only." >&2
  else
    echo "$lines" | sed 's/^/  /'
  fi

  # Generic userspace is always safe and covers the dev VM's virtio-gpu (venus/virgl
  # via mesa) — the vendor branches below simply add nothing there.
  info "Installing generic Mesa + Vulkan loader..."
  w_pac -S --needed --noconfirm mesa vulkan-icd-loader

  local has_intel=0
  w_gpu_has intel && has_intel=1

  if [[ "$has_intel" == "1" ]]; then
    info "Intel GPU detected — installing vulkan-intel + intel-media-driver (VA-API)..."
    w_pac -S --needed --noconfirm vulkan-intel intel-media-driver
  fi

  if w_gpu_has amd; then
    info "AMD GPU detected — installing vulkan-radeon + AMDGPU TOP"
    w_pac -S --needed --noconfirm vulkan-radeon libva-mesa-driver amdgpu_top
  fi

  if w_gpu_has nvidia; then
    local codename; codename=$(w_gpu_nvidia_codename)
    gpu_setup_nvidia "$codename" "$has_intel"
  else
    # Idempotency: a machine without NVIDIA must not carry stale nvidia glue (e.g.
    # after a GPU swap + re-apply). Leave mkinitcpio alone if nothing to strip.
    [[ -f /etc/w/gpu-env.sh ]] && { rm -f /etc/w/gpu-env.sh; info "Removed stale /etc/w/gpu-env.sh."; }
  fi

  info "GPU setup done. NVIDIA changes take effect after the next reboot."
}
