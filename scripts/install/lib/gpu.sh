# gpu.sh — the installer/apply entry point to the GPU-detection seam.
#
# The seam itself is NOT here any more: it ships to the machine as
# rootfs/usr/lib/w/w-gpu-lib.sh, and this file only sources it. Same move as
# lib/pac.sh (installer.md §5) and for the same reason — packs/ai-extra and
# packs/comfyui source the machine copy directly (rootfs ships long before
# `w-pack` runs), and giving them a second implementation of the vendor
# classifier would have been exactly the drift this project gates away.
#
# The path is resolved relative to this file, not to /usr/lib/w: apply.sh must
# use the seam from the checkout it is running out of, and on the ISO
# /usr/lib/w does not exist yet at all.
# shellcheck source=../../../rootfs/usr/lib/w/w-gpu-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../rootfs/usr/lib/w" && pwd)/w-gpu-lib.sh"
