# modules/wifi.sh — on chips unsupported by the in-kernel brcmsmac/brcmfmac
# drivers, install broadcom-wl-dkms and blacklist the competing drivers instead.
#
# Some older/rare Broadcom 802.11 chips have an 802.11-core "corerev" that isn't
# in brcmsmac's supported-hardware table at all — lspci shows no
# "Kernel driver in use" whatsoever, not even a firmware-loading failure, and
# `modprobe bcma brcmsmac` binds nothing. Confirmed on real hardware: BCM43142
# [14e4:4365] (Lenovo laptop) — its Wi-Fi worked live because the ISO carried the
# driver, but that only helps the live session; the target needs it installed too.
#
# ⚠️ The live half of that is no longer true by default. Arch dropped the prebuilt
# `broadcom-wl` on 2026-09-01 and upstream archiso removed the line rather than
# replacing it, so W's ISO no longer covers these chips in the live session unless
# it is built with `build-iso.sh --broadcom-wl` (the DKMS route costs ~570 MiB of
# compiler in the image — see the option's comment there, and the README section).
# THIS module is unaffected: the target gets the driver either way.
#
# Both the install AND the blacklist are gated on lspci actually finding a known
# chip — not just the blacklist. broadcom-wl's own kernel module has an overly
# broad PCI alias (pci:v*d*sv*sd*bc02sc80i* — vendor/device wildcarded, matched
# only by PCI class "Network controller/Other", i.e. any Wi-Fi card of any
# vendor; a known quirk of the old Broadcom STA driver). If `wl.ko` were present
# on a machine that doesn't need it, it could race the correct driver for an
# unrelated card (Intel/Atheros/Realtek, or even a normal Broadcom chip that
# works fine with brcmfmac, e.g. BCM4356) — so it must only exist on machines
# confirmed to need it. Install-time module (like network.sh/bootloader.sh), not
# firstboot/apply.sh: the live ISO boots on the exact same physical hardware
# being installed to, and broadcom-wl-dkms is official `extra` (no AUR needed).

# PCI [vendor:device] IDs of chips confirmed to need broadcom-wl-dkms over
# brcmsmac/brcmfmac. Extend as more unsupported chips are confirmed on hardware.
BROADCOM_WL_PCI_IDS=(14e4:4365 14e4:43a0)  # BCM43142, BCM4360

mod_wifi() {
  local lines id needs_wl=0
  lines=$(lspci -nn 2>/dev/null | grep -Ei 'Network controller' || true)
  for id in "${BROADCOM_WL_PCI_IDS[@]}"; do
    echo "$lines" | grep -qi "\[$id\]" && needs_wl=1
  done
  (( needs_wl )) || return 0

  ui_info "Installing broadcom-wl-dkms (Wi-Fi chip unsupported by brcmsmac)..."
  w_pac -S --needed --noconfirm broadcom-wl-dkms

  # Arch wiki's Broadcom wireless page: blacklist the in-kernel drivers that would
  # otherwise race `wl` for the same PCI device (wl binds directly via a broad
  # PCI-class alias, not through bcma — see modinfo wl on the live ISO).
  install -d -m 755 "$MNT/etc/modprobe.d"
  cat > "$MNT/etc/modprobe.d/broadcom-wl.conf" <<'EOF'
# Managed by W (scripts/install/modules/wifi.sh). These would otherwise race
# broadcom-wl (wl) for the same PCI device on chips broadcom-wl-dkms was
# installed for.
blacklist brcmsmac
blacklist brcmfmac
blacklist bcma
blacklist b43
blacklist ssb
EOF
}
