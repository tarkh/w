# modules/printing.sh — printing + scanning stack (driverless-first, 2026)
#
# One module owns the whole "printing" concern (essentials.md boundary rule).
# Philosophy: IPP Everywhere / AirPrint. Nearly every printer built in the last
# ~decade — and effectively every network printer — is driverless: CUPS finds it
# over mDNS and prints via IPP with no vendor PPD. We deliberately ship NO driver
# databases (gutenprint/foomatic/hplip): they add weight and a maintenance/CVE
# surface for a case modern hardware no longer needs.
#
#   • Server  — cups (lp/lpr/lpadmin CLI + web UI on localhost:631). Socket-
#               activated (cups.socket) so the daemon starts on first use.
#   • Admin   — cups-pk-helper: system-config-printer edits queues through polkit
#               (→ the W auth agent w-authd + fingerprint), no sudoers entry needed.
#   • Filters — cups-filters + ghostscript rasterize PDF → PWG-Raster/URF for
#               printers that don't accept PDF directly.
#   • USB     — ipp-usb: driverless USB. Exposes an IPP-over-USB (AirPrint) device
#               as a local IPP service, so printing AND eSCL scanning work over USB
#               with no vendor driver. udev-triggered when a printer is plugged in.
#   • GUI     — system-config-printer (GTK3, auto-themed live by the w-style gtk
#               axis). The CUPS web UI (localhost:631 in Firefox) is the fallback.
#   • Scan    — sane + sane-airscan (driverless eSCL/WSD over network & ipp-usb) +
#               simple-scan (GTK GUI). No saned/daemon — client-side only.
#
# Discovery relies on avahi + nss-mdns, which apply.sh --files already installs and
# enables (mDNS resolves *.local and browses DNS-SD). No skel config is shipped:
# driverless printing is zero-config. No firewalld change is needed either — the
# `home` zone already passes mDNS, client IPP is outbound, and ipp-usb is localhost.
#
# Security: cups-browsed (the component behind the 2024 CUPS RCE chain,
# CVE-2024-47176 et al.) is masked. Driverless discovery via avahi covers our needs
# without it.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_printing() {
  ui_info "Installing printing + scanning stack (driverless / IPP Everywhere)..."
  w_pac -S --needed --noconfirm \
    cups cups-pk-helper cups-filters ghostscript ipp-usb \
    system-config-printer \
    sane sane-airscan simple-scan

  ui_info "Enabling CUPS (socket-activated) + ipp-usb (driverless USB bridge)..."
  # cups.socket starts the daemon on first access — lighter than a resident service.
  systemctl enable --now cups.socket
  # ipp-usb self-arms via udev when a USB IPP printer appears; enabling is harmless
  # and covers a device already plugged in at apply time.
  systemctl enable --now ipp-usb.service

  # Mask cups-browsed: it drove the 2024 CUPS RCE chain and we don't rely on it
  # (avahi handles discovery). On current Arch it may be a separate package that
  # isn't installed — then the unit is absent and mask is a harmless no-op.
  if systemctl list-unit-files cups-browsed.service &>/dev/null \
     && systemctl list-unit-files cups-browsed.service | grep -q cups-browsed; then
    ui_info "Masking cups-browsed (CVE-2024-47176 attack surface; unused)..."
    systemctl disable --now cups-browsed.service 2>/dev/null || true
    systemctl mask cups-browsed.service
  fi

  ui_info "Printing ready. Driverless printers appear automatically; manage via"
  ui_info "system-config-printer, the CUPS web UI (http://localhost:631), or lpadmin."
}
