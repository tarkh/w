# pac.sh — the installer/apply entry point to the package-transaction seam.
#
# The seam itself is NOT here any more: it ships to the machine as
# rootfs/usr/lib/w/w-pac-lib.sh, and this file only sources it. The move
# came with Ф.3 (installer.md §5) for one reason — the three runtime scripts that
# install packages on an already-installed machine (w-pack, w-kernel,
# w-actuate-lib.sh) cannot see scripts/install/lib at all, so until now they ran
# bare `pacman -S` with no retry and no way to change mirrors between attempts.
# Giving them a second implementation of the classifier would have been the exact
# drift the project keeps gating away; giving them THIS one costs a source line.
#
# The path is resolved relative to this file, not to /usr/lib/w: apply.sh must use
# the seam from the checkout it is running out of (the same rule that makes w-sync
# run apply.sh from the freshly pulled tree), and on the ISO /usr/lib/w does
# not exist yet at all.
# shellcheck source=../../../rootfs/usr/lib/w/w-pac-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../rootfs/usr/lib/w" && pwd)/w-pac-lib.sh"
