#!/usr/bin/env bash
# 3d bundle — PREPARE step. Run by `w-pack install` BEFORE pkgs.txt, always as
# root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Cycles renders on the GPU only through a vendor compute runtime the blender
# package lists as OPTIONAL — which one is a property of this machine, so it is
# picked here by w-gpu-lib.sh rather than named in pkgs.txt:
#   AMD           → hip-runtime-amd + hiprt (HIP, HIP-RT ray tracing)
#   Intel (Arc)   → intel-compute-runtime (oneAPI / Level Zero); integrated
#                   Intel GPUs are not Cycles devices — nothing to add
#   NVIDIA        → nothing: the driver's libcuda runs Blender's precompiled
#                   CUDA/OptiX kernels; the 5 GiB `cuda` toolkit is only needed
#                   to compile kernels and stays the user's call (pack-3d.md)
# --asdeps: pulled in FOR blender, not asked for by name. An optional
# dependency of an installed package is not an orphan (`pacman -Qdt`), so it
# lives exactly as long as Blender does.
#
# Not run by `w-pack refresh` (no network on refresh). Idempotent; best-effort —
# Blender works on the CPU without any of this.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

GPU_LIB="${W_GPU_LIB:-/usr/lib/w/w-gpu-lib.sh}"
if [[ ! -r "$GPU_LIB" ]]; then
  warn "w-gpu-lib.sh missing — cannot detect the GPU; Cycles stays on the CPU."
  exit 0
fi
# shellcheck source=/dev/null
source "$GPU_LIB"

runtime=()
w_gpu_has amd && runtime+=(hip-runtime-amd hiprt)
w_gpu_intel_discrete && runtime+=(intel-compute-runtime)
w_gpu_has nvidia && info "NVIDIA: Cycles CUDA/OptiX runs on the driver — no extra runtime."

if (( ${#runtime[@]} )); then
  info "Installing the Cycles GPU runtime: ${runtime[*]}..."
  pacman -S --needed --asdeps --noconfirm "${runtime[@]}" \
    || warn "Cycles GPU runtime install failed — Blender renders on the CPU. Retry: w-pack install 3d"
else
  info "No Cycles GPU runtime to add for this machine."
fi

info "3d prepare step complete."
exit 0
