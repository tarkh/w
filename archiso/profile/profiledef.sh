#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="w"
iso_label="W_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="W Linux <https://github.com/tarkh/w>"
iso_application="W Linux Live/Install Medium"

# ISO version = <release>-<build date>, e.g. 0.1.0-2026.08.26, so the filename says
# both which release this is and when it was assembled — the two facts a rolling
# distro needs, and exactly what tells nightly rebuilds of one release apart.
# The release is read from the payload os-release that build-iso.sh has already
# staged next to this file. If it is not there (profile built by hand, outside
# build-iso.sh), fall back to the plain date rather than failing the build.
_w_date="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
_w_release="$(sed -n 's/^IMAGE_VERSION=//p' \
  "$(dirname "${BASH_SOURCE[0]}")/airootfs/root/w/rootfs/etc/os-release" 2>/dev/null | tr -d '"')"
iso_version="${_w_release:+${_w_release}-}${_w_date}"
install_dir="w"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  # mkarchiso copies profile/airootfs/ with `cp -af --no-preserve=ownership,mode`
  # (see _make_custom_airootfs in /usr/bin/mkarchiso) — EVERY mode bit from this
  # checkout is discarded on the way into the image, regardless of what git or the
  # host filesystem says. This array is the only thing mkarchiso actually applies
  # afterwards, so every executable build-iso.sh stages under /root/w/ has to be
  # re-declared here, or it silently comes out 644 (bit us twice: install.sh first,
  # then every rootfs/usr/bin/w-* script on a real firstboot run). Directory
  # entries (trailing "/") apply recursively, harmlessly covering config/library
  # files alongside the actual scripts in the same tree.
  ["/root/w/scripts/"]="0:0:755"
  ["/root/w/rootfs/usr/bin/"]="0:0:755"
  # /usr/lib/w is listed file-by-file, not as a directory: unlike usr/bin it mixes
  # executables with sourced libraries and Python modules, and a recursive 755 here
  # would ship those 755 from an ISO install but 644 from a repo apply — the same
  # file, two modes, depending on how the machine was built. check/paths.sh asserts
  # this list covers every executable in the tree, so it cannot be forgotten.
  ["/root/w/rootfs/usr/lib/w/papirus-folders"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-authd"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-fp-gate"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-update-refresh"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-firstboot"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-ai-actuate"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-hub-actuate"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-pacnew-reconcile"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-power-monitor"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-kbdlight-boot"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-wait-notifications"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-snapshot-notify"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-i18n"]="0:0:755"
  ["/root/w/rootfs/usr/lib/w/w-theme/palette.py"]="0:0:755"
  ["/root/w/rootfs/usr/lib/systemd/system-sleep/w-power"]="0:0:755"
  ["/root/w/rootfs/usr/lib/systemd/system-sleep/w-sensors"]="0:0:755"
  # mkinitcpio install + runtime hooks: sourced by name, but mkinitcpio's own
  # add_runscript re-installs the runtime one 755 into the image, and a 644
  # install hook is skipped outright — so the whole tree is executable by nature.
  ["/root/w/rootfs/etc/initcpio/"]="0:0:755"
  ["/root/w/rootfs/usr/share/w/ai/skills/hyprland/install.sh"]="0:0:755"
  ["/root/w/rootfs/etc/greetd/w-greeter-wrapper.sh"]="0:0:755"
)
