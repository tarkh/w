#!/usr/bin/env bats
# gpu-lib.bats — rootfs/usr/lib/w/w-gpu-lib.sh: the shared GPU-detection seam
# (gaming-plan.md Session 1). Every fixture goes through W_GPU_LINES, so lspci
# is never actually invoked here. The empty-VM fixture is deliberately a SET
# empty string ("") rather than an unset variable — w_gpu_lines distinguishes
# the two on purpose (checks.md rule 11), and getting that wrong would make
# this whole suite quietly shell out to the real machine's lspci instead.

load helpers

setup() {
  source "$REPO/rootfs/usr/lib/w/w-gpu-lib.sh"
}

@test "AMD discrete: vendors=amd, lib32 has vulkan-radeon, no nvidia" {
  W_GPU_LINES='03:00.0 VGA compatible controller [0300]: AMD Navi 31 [1002:744c]'
  [[ "$(w_gpu_vendors)" == "amd" ]]
  [[ "$(w_gpu_lib32_packages)" == *lib32-vulkan-radeon* ]]
  [[ "$(w_gpu_lib32_packages)" != *nvidia* ]]
}

@test "Intel iGPU: not discrete, lib32 has vulkan-intel" {
  W_GPU_LINES='00:02.0 VGA compatible controller [0300]: Intel [8086:46a6]'
  ! w_gpu_intel_discrete
  [[ "$(w_gpu_lib32_packages)" == *lib32-vulkan-intel* ]]
}

@test "Intel Arc A770 (DG2/Alchemist): discrete rc 0" {
  W_GPU_LINES='00:02.0 VGA compatible controller [0300]: Intel DG2 [Arc A770] [8086:56a0]'
  w_gpu_intel_discrete
}

@test "Intel Battlemage: discrete rc 0" {
  W_GPU_LINES='00:02.0 VGA compatible controller [0300]: Intel Battlemage [8086:e20b]'
  w_gpu_intel_discrete
}

@test "Intel DG1: deliberately unsupported, discrete rc 1" {
  W_GPU_LINES='00:02.0 VGA compatible controller [0300]: Intel DG1 [8086:4905]'
  ! w_gpu_intel_discrete
}

@test "NVIDIA Ada (AD104): official nvidia-open-dkms, lib32 nvidia-utils" {
  W_GPU_LINES='01:00.0 VGA compatible controller [0300]: NVIDIA AD104 [GeForce RTX 4070] [10de:2786]'
  [[ "$(w_gpu_nvidia_driver)" == "official:nvidia-open-dkms" ]]
  [[ "$(w_gpu_lib32_packages)" == *lib32-nvidia-utils* ]]
}

@test "NVIDIA Pascal (GP106): AUR 580xx, lib32 AUR 580xx-utils" {
  W_GPU_LINES='01:00.0 VGA compatible controller [0300]: NVIDIA GP106 [GeForce GTX 1060] [10de:1c03]'
  [[ "$(w_gpu_nvidia_driver)" == "aur:nvidia-580xx-dkms" ]]
  [[ "$(w_gpu_lib32_packages)" == *aur:lib32-nvidia-580xx-utils* ]]
}

@test "NVIDIA Kepler (GK104): AUR 470xx, lib32 AUR 470xx-utils" {
  W_GPU_LINES='01:00.0 VGA compatible controller [0300]: NVIDIA GK104 [GeForce GTX 770] [10de:1184]'
  [[ "$(w_gpu_nvidia_driver)" == "aur:nvidia-470xx-dkms" ]]
  [[ "$(w_gpu_lib32_packages)" == *aur:lib32-nvidia-470xx-utils* ]]
}

@test "NVIDIA Fermi (GF119): nouveau, lib32 has no nvidia token" {
  W_GPU_LINES='01:00.0 VGA compatible controller [0300]: NVIDIA GF119 [NVS 315] [10de:1057]'
  [[ "$(w_gpu_nvidia_driver)" == "nouveau:" ]]
  [[ "$(w_gpu_lib32_packages)" != *nvidia* ]]
}

@test "NVIDIA with no recognised codename: falls back to official nvidia-open-dkms" {
  W_GPU_LINES='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation [10de:ffff]'
  [[ "$(w_gpu_nvidia_driver)" == "official:nvidia-open-dkms" ]]
}

@test "Hybrid Intel+NVIDIA: vendors is stable order 'intel nvidia'" {
  W_GPU_LINES="00:02.0 VGA compatible controller [0300]: Intel [8086:46a6]
01:00.0 VGA compatible controller [0300]: NVIDIA AD104 [GeForce RTX 4070] [10de:2786]"
  [[ "$(w_gpu_vendors)" == "intel nvidia" ]]
}

@test "Empty (virtio-VM): no vendors, lib32 is only the generic pair" {
  W_GPU_LINES=""
  [[ -z "$(w_gpu_vendors)" ]]
  [[ "$(w_gpu_lib32_packages)" == "official:lib32-mesa official:lib32-vulkan-icd-loader" ]]
}
