# w-gpu-lib.sh — the one GPU-detection seam every consumer sources (shared).
#
# Before this file the same `lspci -nn` pipe and NVIDIA codename→driver mapping
# existed three times: modules/gpu.sh (the installer/apply module that actually
# installs the drivers), packs/ai-extra/setup.sh (Ollama backend pick) and
# packs/comfyui/setup.sh (comfy-cli GPU flag). A fourth copy was about to be
# born in the `gaming` pack (lib32 vendor packages) — this file replaces all
# three and is the base the fourth builds on. See package-gpu.md, gaming-plan.md.
#
# Sourced from two sides, same as w-pac-lib.sh:
#   • installer / apply.sh — via scripts/install/lib/gpu.sh, a two-line shim
#     (runs off the ISO or the source checkout, where /usr/lib/w does not exist
#     yet);
#   • the installed machine — /usr/lib/w/w-gpu-lib.sh, sourced directly by the
#     packs (rootfs ships long before `w-pack` ever runs a pack's setup.sh).
#
# Test override: W_GPU_LINES, when SET (checked with ${VAR+x}, not just
# non-empty — a fixture for "no display controller" is a set-but-empty string,
# and treating that the same as "unset" would fall through to the live
# machine's real lspci during a test run). See checks.md rule 11.
#
# Memoisation: w_gpu_lines shells out to lspci at most once per process — every
# other function in this file goes through it, so a caller that asks five
# questions does not pay for five lspci invocations.

_W_GPU_LINES_CACHED=0
_W_GPU_LINES_CACHE=""

# w_gpu_lines — every VGA/3D/Display-class controller line from `lspci -nn`,
# one per line (both the vendor:device id and, for NVIDIA, the chip codename).
# `|| true` on the lspci|grep pipe: no controller found is not an error (landmine
# on fresh-boot under set -e, see checks.md/dev-workflow.md).
w_gpu_lines() {
  if [[ -n "${W_GPU_LINES+x}" ]]; then
    printf '%s\n' "$W_GPU_LINES"
    return 0
  fi
  if [[ "$_W_GPU_LINES_CACHED" == 0 ]]; then
    _W_GPU_LINES_CACHE=$(lspci -nn 2>/dev/null \
      | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
    _W_GPU_LINES_CACHED=1
  fi
  printf '%s\n' "$_W_GPU_LINES_CACHE"
}

# w_gpu_has <intel|amd|nvidia> — rc 0 if that vendor's PCI id shows up.
w_gpu_has() {
  local id
  case "$1" in
    intel)  id='8086' ;;
    amd)    id='1002' ;;
    nvidia) id='10de' ;;
    *) return 1 ;;
  esac
  w_gpu_lines | grep -qi "\[$id:"
}

# w_gpu_vendors — space-separated vendors present, in a FIXED order
# (intel amd nvidia), not lspci's own order — so a hybrid machine always
# prints the same string regardless of PCI enumeration order. Empty = nothing
# found (e.g. virtio-VM).
w_gpu_vendors() {
  local v out=()
  for v in intel amd nvidia; do
    w_gpu_has "$v" && out+=("$v")
  done
  echo "${out[*]}"
}

# w_gpu_intel_discrete — rc 0 for a discrete Intel Arc card (DG2/Alchemist or
# Battlemage), rc 1 otherwise (including Intel iGPUs and DG1, which torch-XPU
# does not support). Device-id ranges, never the marketing name: lspci prints
# the name BEFORE the [vendor:device] pair, so a name-based regex is not a
# contract. Verified live in comfyui/setup.sh before this file existed.
w_gpu_intel_discrete() {
  w_gpu_lines | grep -qiE '\[8086:(4f8[0-9a-f]|56[0-9a-f]{2}|e2[0-9a-f]{2})\]'
}

# w_gpu_nvidia_codename — the chip codename prefix (e.g. "AD104") off the
# [10de:] line, or empty if none/unrecognised. lspci pulls it from pci.ids
# (hwdata); the prefix matches the Arch driver table's family names verbatim.
w_gpu_nvidia_codename() {
  w_gpu_lines | grep -i '\[10de:' \
    | grep -oiE '\b(GB|AD|GA|TU|GV|GP|GM|GK|GF|GT)[0-9]{2,3}\b' | head -1 || true
}

# w_gpu_nvidia_driver [codename] — "<repo>:<pkg>" for our DKMS-on-zen setup.
# Codename defaults to w_gpu_nvidia_codename when omitted.
#   official:nvidia-open-dkms  — Turing and newer (upstream-recommended, extra)
#   aur:nvidia-580xx-dkms      — Volta/Pascal/Maxwell (legacy, AUR)
#   aur:nvidia-470xx-dkms      — Kepler (legacy, unsupported branch, AUR)
#   nouveau:                   — Fermi and older → no proprietary driver
# The mainline nvidia branch (580+) dropped everything below Turing, hence the
# AUR legacy branches. Missing/unrecognised codename (brand-new card not yet in
# pci.ids) falls through to nvidia-open-dkms — safe, since the newest cards
# REQUIRE the open modules.
w_gpu_nvidia_driver() {
  local code="${1:-}"
  [[ -n "$code" ]] || code="$(w_gpu_nvidia_codename)"
  case "$code" in
    GB*|AD*|GA*|TU*)   echo "official:nvidia-open-dkms" ;;
    GV*|GP*|GM*)       echo "aur:nvidia-580xx-dkms"     ;;
    GK*)               echo "aur:nvidia-470xx-dkms"     ;;
    GF*|GT*|G[0-9]*)   echo "nouveau:"                  ;;
    *)                 echo "official:nvidia-open-dkms" ;;   # unknown → newest/open
  esac
}

# w_gpu_lib32_packages — space-separated "<repo>:<pkg>" tokens for the 32-bit
# (multilib) stack native Steam/Wine needs, mirroring w_gpu_nvidia_driver.
# Always includes the generic mesa+loader; vendor branches add on top. The
# NVIDIA legacy branches are the load-bearing fact here: lib32-nvidia-580xx-
# utils and lib32-nvidia-470xx-utils exist ONLY in the AUR — getting this
# wrong means a black-screen Steam on an old card.
w_gpu_lib32_packages() {
  local pkgs=("official:lib32-mesa" "official:lib32-vulkan-icd-loader")
  w_gpu_has amd   && pkgs+=("official:lib32-vulkan-radeon")
  w_gpu_has intel && pkgs+=("official:lib32-vulkan-intel")
  if w_gpu_has nvidia; then
    case "$(w_gpu_nvidia_driver)" in
      official:nvidia-open-dkms) pkgs+=("official:lib32-nvidia-utils") ;;
      aur:nvidia-580xx-dkms)     pkgs+=("aur:lib32-nvidia-580xx-utils") ;;
      aur:nvidia-470xx-dkms)     pkgs+=("aur:lib32-nvidia-470xx-utils") ;;
      nouveau:) : ;;   # no proprietary driver → nothing extra
    esac
  fi
  echo "${pkgs[*]}"
}
