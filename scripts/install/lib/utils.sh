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

# Secure Boot as the firmware enforces it: the data byte after the 4 attribute bytes
# of the efivar — on | off | unknown. (The kernel's own "Secure boot" line is no
# witness: Limine does not hand the state over.) W_EFIVARS is a test seam.
sb_state() {
  case "$(od -An -tu1 -j4 -N1 "${W_EFIVARS:-/sys/firmware/efi/efivars}/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c" 2>/dev/null | tr -d ' ')" in
    1) echo on ;; 0) echo off ;; *) echo unknown ;;
  esac
}
sb_enforcing() { [[ "$(sb_state)" == on ]]; }

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
