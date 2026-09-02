# utils.sh — common helpers

MNT="/mnt"

die() {
  # Force to the terminal: during the work phase stderr is redirected to the log.
  { clear; echo -e "\033[1;31mERROR:\033[0m $*"; } >/dev/tty 2>&1
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Installer must be run as root."
}

require_uefi() {
  [[ -d /sys/firmware/efi ]] || die "UEFI boot not detected. W Linux requires UEFI."
}

# Run a command inside the target chroot
chroot_run() {
  arch-chroot "$MNT" "$@"
}

# Run a command inside chroot via bash -c (for pipes, redirects)
chroot_sh() {
  arch-chroot "$MNT" bash -c "$1"
}

# Partition name helper: /dev/sda 1 → /dev/sda1; /dev/nvme0n1 1 → /dev/nvme0n1p1
part() {
  local disk="$1" n="$2"
  if [[ "$disk" == *nvme* || "$disk" == *mmcblk* ]]; then
    echo "${disk}p${n}"
  else
    echo "${disk}${n}"
  fi
}
