#!/usr/bin/env bash
# Start W Linux VM with virtiofs shared project directory
# shellcheck disable=SC2054  # QEMU option strings (`-device a,b=c`) contain commas by design
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VFSD_SOCK="/tmp/w-vfsd.sock"

source "$SCRIPT_DIR/arch-iso.conf"
OVMF_VARS="$SCRIPT_DIR/OVMF_VARS.fd"

# --install:    boot w-test.qcow2 from ISO to run install.sh
# --iso=PATH:   with --install, boot this ISO instead of the stock Arch ISO from
#            arch-iso.conf (vm/e2e.sh boots the built W ISO from archiso/out/).
# --headless:  no window (-display none, plain virtio-vga, null audio) — for the
#            unattended E2E harness. The guest console still exists; dialog
#            renders to it unseen.
# --no-reboot: a guest reboot/poweroff exits QEMU instead of restarting it —
#            lets the E2E harness drive each boot of the multi-reboot install
#            flow as a separate QEMU run.
# --bt:         pass the host's motherboard Bluetooth radio (USB-backed, 0489:e10a —
#            Foxconn/MediaTek combo) into the guest via usb-host. Only the BT radio is
#            grabbed (Wi-Fi phy0 is a separate PCIe function, untouched); the host btusb
#            driver detaches while the VM runs and re-binds on exit. No host reboot / VFIO.
#            For visually testing the blueman tray applet (see quickshell-bar.md).
# --fp:         pass the host's USB fingerprint reader (05ba:000a, DigitalPersona
#            U.are.U 4000B — libfprint's uru4000 driver) into the guest, same
#            usb-host mechanism as --bt and fully independent of it: passing one
#            device never touches the other. The ONLY way to exercise the auth
#            card's fingerprint mode (quickshell-auth.md), since no VM has a
#            reader and the test laptop has no sensor. Note the guest takes the
#            device exclusively — while the VM runs, the HOST has no reader, so
#            sudo/polkit there falls back to a password. Fingerprints live on the
#            machine they were enrolled on, so the guest needs its own one-time
#            `fprintd-enroll`; it survives guest reboots, not a reinstall.
# --secureboot: use the SMM/Secure-Boot OVMF build on a q35+smm machine with a
#            dedicated NVRAM file (OVMF_VARS.secboot.fd, Setup Mode → guest enrolls
#            its own keys via `w-secureboot setup`). Needed to test the Limine SB stack.
# --tpm:     attach an emulated TPM 2.0 via swtpm (host `swtpm` package). Needed to
#            test LUKS TPM2 auto-unlock (systemd-cryptenroll --tpm2-device=auto).
# --force-iso: with --install, force-boot the ISO even if w-base.qcow2 already holds
#            an installed system. QEMU/OVMF honor explicit bootindex over `-boot order`,
#            so plain --install (HDD bootindex=0, CD=1) only reaches the CD on an empty
#            disk. This flips it (CD=0, HDD=1) to test the installer TUI without wiping
#            the test VM.
# --extra-mon=N: give the guest N ADDITIONAL monitors on top of the base one
#            (--extra-mon=2 → 3 heads). Raises the virtio-gpu scanout count, so the guest
#            gets that many real DRM connectors ("Virtual-N") — for testing the
#            multi-monitor stack (w-monitor, the Hub Displays panel, per-monitor bars,
#            the greeter's login card placement). Implies the GTK display backend (each head
#            is a tab) plus a QMP socket for host-side introspection — see MEDIA_ARGS below.
#            Default 0 = today's single-head SDL behaviour, byte-for-byte unchanged.
#            Note: virtio-gpu's mode list is EDID-synthetic (one preferred mode + a few
#            standard ones) — resolution/refresh switching still wants real hardware.
# --display=sdl|gtk: force the display backend instead of letting --extra-mon pick it.
INSTALL_MODE=0
BT_MODE=0
FP_MODE=0
SECBOOT_MODE=0
TPM_MODE=0
HEADLESS_MODE=0
NO_REBOOT=0
FORCE_ISO_MODE=0
ISO_OVERRIDE=""
EXTRA_MON=0
DISPLAY_OVERRIDE=""
for arg in "$@"; do
  [[ "$arg" == "--install" ]] && INSTALL_MODE=1
  [[ "$arg" == "--force-iso" ]] && FORCE_ISO_MODE=1
  [[ "$arg" == "--bt" ]] && BT_MODE=1
  [[ "$arg" == "--fp" ]] && FP_MODE=1
  [[ "$arg" == "--secureboot" ]] && SECBOOT_MODE=1
  [[ "$arg" == "--tpm" ]] && TPM_MODE=1
  [[ "$arg" == "--headless" ]] && HEADLESS_MODE=1
  [[ "$arg" == "--no-reboot" ]] && NO_REBOOT=1
  [[ "$arg" == --extra-mon=* ]] && EXTRA_MON="${arg#--extra-mon=}"
  [[ "$arg" == --display=* ]] && DISPLAY_OVERRIDE="${arg#--display=}"
  [[ "$arg" == --iso=* ]] && ISO_OVERRIDE="${arg#--iso=}"
done

# Capped at 3 extra heads (4 total): enough for any layout test, and a fat-fingered
# --extra-mon=20 doesn't try to open 20 windows.
[[ "$EXTRA_MON" =~ ^[0-3]$ ]] \
  || { echo "ERROR: --extra-mon must be 0..3 (extra monitors added to the base one)"; exit 1; }
[[ -z "$DISPLAY_OVERRIDE" || "$DISPLAY_OVERRIDE" =~ ^(sdl|gtk)$ ]] \
  || { echo "ERROR: --display must be sdl or gtk"; exit 1; }

# Secure Boot uses a separate NVRAM so it never clobbers the plain-boot vars.
OVMF_VARS_SECBOOT="$SCRIPT_DIR/OVMF_VARS.secboot.fd"
if [[ $SECBOOT_MODE -eq 1 ]]; then
  # Seed the Secure-Boot NVRAM from the Setup-Mode template (the plain OVMF_VARS)
  # on first use, then switch code+vars to the SB pair.
  [[ -f "$OVMF_VARS_SECBOOT" ]] || cp "$OVMF_VARS" "$OVMF_VARS_SECBOOT"
  OVMF_CODE="$OVMF_CODE_SECBOOT"
  OVMF_VARS="$OVMF_VARS_SECBOOT"
fi

# Host Bluetooth USB radio (stable vendor:product id; survives bus renumbering).
BT_VENDOR_ID="0x0489"
BT_PRODUCT_ID="0xe10a"

# Host USB fingerprint reader (--fp). Independent of the BT ids above: each flag
# passes its own device and neither implies the other.
FP_VENDOR_ID="0x05ba"
FP_PRODUCT_ID="0x000a"    # DigitalPersona U.are.U 4000B (libfprint uru4000)

# Resolve the /dev/bus/usb/BUS/DEV node for a device by vid:pid. The bus/dev numbers
# are NOT stable across replug, so we look them up from sysfs each run (vid:pid is stable).
usb_node() { # <0xVID> <0xPID>
  local d v p
  for d in /sys/bus/usb/devices/*; do
    [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
    v="0x$(<"$d/idVendor")"; p="0x$(<"$d/idProduct")"
    if [[ "$v" == "$1" && "$p" == "$2" ]]; then
      printf '/dev/bus/usb/%03d/%03d' "$(<"$d/busnum")" "$(<"$d/devnum")"
      return 0
    fi
  done
  return 1
}

bt_usb_node() { usb_node "$BT_VENDOR_ID" "$BT_PRODUCT_ID"; }
fp_usb_node() { usb_node "$FP_VENDOR_ID" "$FP_PRODUCT_ID"; }

if [[ $INSTALL_MODE -eq 1 ]]; then
  DISK="$SCRIPT_DIR/w-base.qcow2"
  ISO="${ISO_OVERRIDE:-$SCRIPT_DIR/$ARCH_ISO_FILE}"
  [[ -f "$ISO" ]] || { echo "ERROR: ISO not found: $ISO"; exit 1; }
else
  DISK="$SCRIPT_DIR/w-base.qcow2"
fi

if [[ ! -f "$DISK" ]]; then
  echo "ERROR: VM disk not found: $DISK"
  [[ $INSTALL_MODE -eq 1 ]] && echo "Run: qemu-img create -f qcow2 $DISK 40G" \
                             || echo "Run: bash scripts/bootstrap.sh"
  exit 1
fi

if [[ ! -f "$OVMF_VARS" ]]; then
  echo "ERROR: OVMF_VARS.fd not found. Run: bash scripts/bootstrap.sh"
  exit 1
fi

# Start virtiofsd unless a LIVE one is already serving this socket. Keying on the
# socket file alone (-S) is fooled by a stale socket left behind when a previous
# virtiofsd was killed without cleaning up (e.g. an interrupted E2E run) — the guard
# then skips the start and QEMU hits "Connection refused" on the dead socket. Check
# for a running process bound to this exact path instead, and clear any stale socket
# before (re)starting. pgrep -f matches the full cmdline (no comm 15-char truncation).
if ! pgrep -f "virtiofsd.*--socket-path=$VFSD_SOCK" >/dev/null 2>&1; then
  echo "Starting virtiofsd..."
  rm -f "$VFSD_SOCK"
  /usr/lib/virtiofsd \
    --socket-path="$VFSD_SOCK" \
    --shared-dir="$PROJECT_DIR" \
    --cache=auto \
    --sandbox=none &
  sleep 1
fi

# --tpm: emulated TPM 2.0 via swtpm. State persists in $SWTPM_DIR (survives reboots
# so an enrolled TPM2 LUKS key keeps working across VM restarts).
SWTPM_SOCK="$SWTPM_DIR/swtpm-sock"
if [[ $TPM_MODE -eq 1 ]]; then
  command -v swtpm &>/dev/null || { echo "ERROR: swtpm not installed on host. Install: sudo pacman -S swtpm"; exit 1; }
  mkdir -p "$SWTPM_DIR"
  # Same stale-socket guard as virtiofsd above: a killed swtpm leaves its control
  # socket behind, so key on a live process bound to this path, not the socket file.
  # Only the socket is cleared — $SWTPM_DIR state (the enrolled TPM2 key) persists.
  if ! pgrep -f "swtpm.*path=$SWTPM_SOCK" >/dev/null 2>&1; then
    echo "Starting swtpm (TPM 2.0 emulator)..."
    rm -f "$SWTPM_SOCK"
    swtpm socket --tpm2 \
      --tpmstate dir="$SWTPM_DIR" \
      --ctrl type=unixio,path="$SWTPM_SOCK" \
      --flags startup-clear &
    sleep 1
  fi
fi

# Machine topology. Secure Boot needs SMM (q35,smm=on) plus the pflash "secure"
# property so the firmware can lock the varstore; plain boot stays on the default
# i440fx machine (whose empty FDC needs isa-fdc silencing).
if [[ $SECBOOT_MODE -eq 1 ]]; then
  MACHINE_ARGS=(
    -machine q35,smm=on
    -global driver=cfi.pflash01,property=secure,value=on
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
    -drive if=pflash,format=raw,file="$OVMF_VARS"
  )
else
  MACHINE_ARGS=(
    # No floppy: the i440fx default empty FDC makes the guest kernel log
    # "I/O error, dev fd0" on every boot. Drop drive A to silence it.
    -global isa-fdc.fdtypeA=none
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
    -drive if=pflash,format=raw,file="$OVMF_VARS"
  )
fi

# Video/audio: headless drops the window and the host audio backend (a CI shell
# may have no PulseAudio session; the guest still sees an HDA device either way).
# virtio-vga-gl needs a GL-capable display backend, so headless uses plain
# virtio-vga.
#
# HEADS = virtio-gpu scanouts (1 + --extra-mon) = DRM connectors the guest sees. The
# display backend has to be able to SHOW the extra heads: SDL has no UI for secondary
# consoles, while GTK exposes each head as a tab (View menu) that detaches into its own
# window. So multi-head switches to GTK and single-head stays on SDL — the known-quantity
# path for everyday runs (see the VM hover quirk in dev-workflow.md). --display= overrides
# the pick either way.
#
# The GPU carries an explicit id so the host can introspect it over QMP, and multi-head
# adds the QMP socket itself: `screendump` takes a per-head argument, which is the only way
# to ask QEMU what it believes head N holds — independent of whether the widget paints it.
#   python3 -c 'import socket,json
#   s=socket.socket(socket.AF_UNIX); s.connect("/tmp/w-qmp.sock"); f=s.makefile("rw")
#   f.readline(); [ (f.write(json.dumps(c)+"\n"), f.flush(), print(f.readline())) for c in
#     ({"execute":"qmp_capabilities"},
#      {"execute":"screendump","arguments":{"filename":"/tmp/h1.ppm","device":"gpu0","head":1}}) ]'
#
# GPU model: single head keeps virgl (virtio-vga-gl); multi-head drops to the 2D virtio-vga,
# because NO GL variant presents anything beyond scanout 0 on this host — measured, not
# assumed. All of these leave head 2 permanently blank while the guest itself is fine
# (Hyprland lists the head, puts a workspace/bar/animating windows on it, input routes to
# it, `grim -o` renders it):
#   virtio-vga-gl                 tabbed and detached — blank
#   virtio-vga-gl,blob=on         dmabuf path instead of texture blit — blank
#   virtio-gpu-gl-pci             no VGA-compat console 0 — blank (and no greeter: the
#                                 default -vga std sneaks back in as a second GPU)
#   virtio-vga (2D, no virgl)     BOTH heads work, windows move between them, bar is fine
# The cost is llvmpipe in the guest: laggy, and effects that need real GL degrade. That is
# the price of a visible second monitor today; single-head runs keep full virgl.
# W_VM_GPU overrides the model (id= and max_outputs= are always appended, so pass just the
# model plus properties) — for re-testing GL after a QEMU/mesa bump:
#   W_VM_GPU=virtio-vga-gl bash vm/start.sh --extra-mon=1
HEADS=$((1 + EXTRA_MON))
if [[ -n "${W_VM_GPU:-}" ]];  then GPU_DEV="$W_VM_GPU"
elif [[ $EXTRA_MON -gt 0 ]];  then GPU_DEV="virtio-vga"
else                               GPU_DEV="virtio-vga-gl"
fi
QMP_SOCK="/tmp/w-qmp.sock"
if [[ $HEADLESS_MODE -eq 1 ]]; then
  MEDIA_ARGS=(-device virtio-vga,id=gpu0,max_outputs="$HEADS" -display none -audiodev none,id=snd0)
else
  if [[ -n "$DISPLAY_OVERRIDE" ]]; then
    DISPLAY_BACKEND="$DISPLAY_OVERRIDE"
  elif [[ $EXTRA_MON -gt 0 ]]; then
    DISPLAY_BACKEND=gtk
    echo "$HEADS monitors: using the GTK display backend — each head is a tab (View menu),"
    echo "detachable into its own window. Override with --display=sdl."
  else
    DISPLAY_BACKEND=sdl
  fi
  # gl=on stays on the backend in both cases: a 2D device simply never uses the UI's GL
  # path, and leaving it enables W_VM_GPU=<a -gl model> without a second knob.
  MEDIA_ARGS=(-device "$GPU_DEV,id=gpu0,max_outputs=$HEADS"
              -display "$DISPLAY_BACKEND",gl=on -audiodev pa,id=snd0)
  if [[ $EXTRA_MON -gt 0 ]]; then
    rm -f "$QMP_SOCK"
    MEDIA_ARGS+=(-qmp "unix:$QMP_SOCK,server=on,wait=off")
    echo "GPU: $GPU_DEV — 2D, no virgl: the guest runs on llvmpipe and will feel slow."
    echo "     Every GL variant leaves head 2 blank (see start.sh); override: W_VM_GPU=."
    echo "QMP socket: $QMP_SOCK (per-head screendump — see start.sh MEDIA_ARGS comment)."
  fi
fi

# Explicit bootindex wins over `-boot order` in OVMF/SeaBIOS, so this is the real
# HDD-vs-CD priority. --force-iso flips it to reach the CD on an already-installed disk.
HDD_BOOTINDEX=0
CD_BOOTINDEX=1
[[ $INSTALL_MODE -eq 1 && $FORCE_ISO_MODE -eq 1 ]] && { HDD_BOOTINDEX=1; CD_BOOTINDEX=0; }

QEMU_ARGS=(
  -enable-kvm -cpu host -m 8G -smp 4
  "${MACHINE_ARGS[@]}"
  -drive file="$DISK",format=qcow2,if=none,id=hd0
  -device virtio-blk-pci,drive=hd0,bootindex="$HDD_BOOTINDEX"
  -chardev socket,id=char0,path="$VFSD_SOCK"
  -device vhost-user-fs-pci,chardev=char0,tag=w-src
  -object memory-backend-memfd,id=mem,size=8G,share=on
  -numa node,memdev=mem
  "${MEDIA_ARGS[@]}"
  -device intel-hda -device hda-duplex,audiodev=snd0
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22
)
[[ $NO_REBOOT -eq 1 ]] && QEMU_ARGS+=(-no-reboot)

if [[ $INSTALL_MODE -eq 1 ]]; then
  QEMU_ARGS+=(-drive file="$ISO",media=cdrom,readonly=on,if=none,id=cd0
              -device ide-cd,drive=cd0,bootindex="$CD_BOOTINDEX" -boot order=d)
else
  QEMU_ARGS+=(-boot order=c)
fi

# --bt / --fp: attach a USB controller + the named host device(s). usb-host auto-detaches
# the host kernel driver on grab and restores it when QEMU exits. QEMU needs rw on the
# device node (/dev/bus/usb/...), which is root-owned, so we chown it to the invoking user
# before launch (sudo) and restore root ownership on exit/Ctrl+C via a trap. The node is
# ephemeral (devtmpfs recreates it root-owned on replug/reboot), so the restore is just
# tidiness, not a hard requirement.
#
# The two flags are independent — either, both, or neither — but they SHARE the controller
# and the trap, and must: a second `-device qemu-xhci,id=xhci` is a duplicate-id error, and
# a second `trap ... EXIT` REPLACES the first, silently leaving one node user-owned. Hence
# one node list built here rather than a self-contained block per device.
USB_NODES=()
usb_passthrough() { # <label> <0xVID> <0xPID> <resolver-fn>
  local label="$1" vid="$2" pid="$3" node
  echo "Passing host $label ($vid:$pid) to the VM."
  echo "The host loses $label while the VM runs; it returns on exit."
  node="$("$4" || true)"
  if [[ -n "$node" ]]; then
    echo "Granting $USER rw on $node (sudo chown)..."
    sudo chown "$USER" "$node"
    USB_NODES+=("$node")
  else
    echo "WARN: $label $vid:$pid not found on host — passthrough will be skipped."
  fi
  QEMU_ARGS+=(-device usb-host,vendorid="$vid",productid="$pid")
}

if [[ $BT_MODE -eq 1 || $FP_MODE -eq 1 ]]; then
  QEMU_ARGS+=(-device qemu-xhci,id=xhci)
  [[ $BT_MODE -eq 1 ]] && usb_passthrough Bluetooth "$BT_VENDOR_ID" "$BT_PRODUCT_ID" bt_usb_node
  [[ $FP_MODE -eq 1 ]] && usb_passthrough "fingerprint reader" "$FP_VENDOR_ID" "$FP_PRODUCT_ID" fp_usb_node
  # Restore root ownership when QEMU exits or the script is interrupted. May re-prompt
  # for sudo at shutdown if the auth timestamp has expired — and with --fp it will be a
  # PASSWORD prompt, because the reader is inside the guest until QEMU is gone.
  restore_usb_nodes() {
    local n
    for n in "${USB_NODES[@]}"; do
      echo "Restoring root ownership of $n..."
      sudo chown root "$n" 2>/dev/null || true
    done
  }
  # Explicit `if`, not `(( … )) && trap`: a trailing && that evaluates false makes
  # the block return 1, and under `set -e` that kills the script right before QEMU
  # launches — for the entirely normal case of "the device was not plugged in".
  if (( ${#USB_NODES[@]} )); then
    trap restore_usb_nodes EXIT INT TERM
  fi
fi

if [[ $TPM_MODE -eq 1 ]]; then
  QEMU_ARGS+=(-chardev socket,id=chrtpm,path="$SWTPM_SOCK"
              -tpmdev emulator,id=tpm0,chardev=chrtpm
              -device tpm-tis,tpmdev=tpm0)
fi

# Not `exec`: the script must stay alive past QEMU so the --bt/--fp EXIT trap can restore the
# USB node ownership (exec would replace the shell and drop the trap).
qemu-system-x86_64 "${QEMU_ARGS[@]}"
