# modules/sensors.sh — hardware sensors (lm_sensors) for the bar temp block
# apply.sh context: runs on the live/installed system as root, on the TARGET
# hardware — so this is where sensor detection belongs (not at ISO build time).
#
# Owns: lm_sensors package + one-shot hardware probe. Without a probe `sensors -j`
# returns "{}" / "No sensors found": most CPU temp drivers (coretemp/k10temp) are
# auto-loaded by the kernel, but Super-I/O chips and many boards are not probed for
# safety until sensors-detect maps them. `sensors-detect --auto` runs fully non-
# interactively, accepts the safe defaults, and writes the modules it found to
# /etc/conf.d/lm_sensors (HWMON_MODULES/BUS_MODULES), which lm_sensors.service
# modprobes on every boot — no extra service to enable. On hardware without
# sensors (VMs) it finds nothing and is a harmless no-op; the bar temp block
# then just auto-hides.
# Consumed by the Quickshell bar temp block (sensors -j). See quickshell-bar.md.
# Some hwmon drivers (e.g. coretemp on older MacBooks) lose their binding across
# suspend/resume even though the module stays loaded — the sleep hook
# /usr/lib/systemd/system-sleep/w-sensors detects and reloads just that.

mod_sensors() {
  info "Installing lm_sensors..."
  w_pac -S --needed --noconfirm lm_sensors

  info "Detecting hardware sensors (sensors-detect --auto)..."
  # --auto answers every prompt with the safe default and auto-writes the modules
  # to /etc/modules-load.d/lm_sensors.conf. Tolerate a non-zero exit (e.g. nothing
  # to probe in a VM) so a sensorless machine doesn't fail the deploy under set -e.
  sensors-detect --auto || true

  info "Loading detected sensor modules..."
  # Apply the freshly written modules-load.d list now, without a reboot. Harmless
  # if the probe found nothing (the file is absent/empty).
  systemctl restart systemd-modules-load.service || true

  info "lm_sensors configured. Verify with: sensors -j"
}
