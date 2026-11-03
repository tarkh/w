#!/usr/bin/env bash
# vm/e2e.sh — unattended end-to-end install test (audit P2).
#
# Host-side, Arch + KVM only. Drives the full multi-reboot install pipeline as
# three headless QEMU runs of the built W ISO (each guest reboot/poweroff exits
# QEMU thanks to --no-reboot, handing control back here):
#
#   S1  ISO boot   → .zlogin finds vm/e2e/preset.conf on the virtiofs share and
#                    runs install.sh --preset (wipes the VM disk, pacstraps,
#                    stages firstboot) → reboot
#   S2  disk boot  → w-firstboot: apply --all + collect-logs, then writes
#                    vm/logs/e2e-firstboot-status ("ok" | "fail rc=N") through
#                    the share → reboot (ok) / poweroff (fail)
#   S3  disk boot  → the finished system; assertions over SSH (the key this
#                    script generates rides in the preset's ssh_authorized_key):
#                    0 failed units, 0 coredumps, greetd active, firstboot flag
#                    gone, plus the multi-user matrix — the update gate AND the
#                    config delivery (a second admin and a non-admin are created
#                    for it and removed afterwards);
#                    a final collect-logs bundle is pulled for the record.
#
# Usage:
#   bash vm/e2e.sh [--iso PATH] [--encrypted] [--dualboot] [--fault-mirror]
#                  [--secureboot own|shim] [--iso-sb]
#                                              # default ISO: newest archiso/out/*.iso
#
# --fault-mirror runs the Ф.4 scenario (installer.md §5): a local endpoint that
# serves at 0 bytes/s takes over the whole ranked mirrorlist between mirror
# selection and pacstrap, so the install meets a pool that was healthy when it was
# chosen and stalled a minute later — the failure that killed three release-gate
# runs in a row and that a run against live mirrors can only reproduce by luck.
# Off by default: the gate stays exactly what it was unless asked.
#
# Scenarios (each has its own gitignored working preset, seeded from the
# matching versioned sample on first run — edit the working copy to vary a run):
#   default      plain btrfs + GRUB        preset-plain.conf     ← preset-plain.sample.conf
#   --encrypted  LUKS2 + Limine + TPM2     preset-encrypted.conf ← preset-encrypted.sample.conf
#   --dualboot   plain, installed into the free space next to a fake "Windows"
#                (vm/fake-windows.sh)   preset-dualboot-plain.conf ← preset-dualboot-plain.sample.conf
#   --dualboot --encrypted   the same next to Windows, encrypted stack
#                                        preset-dualboot.conf  ← preset-dualboot.sample.conf
# The selected working copy is installed as vm/e2e/preset.conf — the machine-
# written "active slot" the ISO's .zlogin looks for — before S1, and removed on
# exit (it would turn any later manual ISO boot into a disk wipe). --encrypted
# also attaches a swtpm TPM (start.sh --tpm) to every stage: the installer
# auto-enrolls TPM2 unlock in S1 (limine_enroll_tpm), and S2/S3 boots rely on
# it — without a TPM the headless LUKS unlock would hang at the passphrase
# prompt. Logs and the firstboot status marker land in vm/logs/ as usual.
#
# --dualboot keeps every assertion of its stack (plain or --encrypted) and replaces
# the blank disk with fake-windows.sh's layout before S1: Windows ESP + MSR + NTFS +
# ~42 GiB free, the installer runs with disk_mode=free. S0 then boots the UEFI shell
# once to give that Windows its firmware boot entry ("Windows Boot Manager", the way
# a real Windows install leaves it) — the entry W's boot menus are built from. S3
# adds what the mode promises: the foreign partitions hash exactly as they did before
# S1, none of them is mounted, W runs off its own ESP with its own NVRAM entry, and
# the boot menu offers Windows and is shown. Every other run asserts the opposite —
# no Windows entry, the menu stays hidden.
# Local-only by design (not in the CI canary) — run it when lib/disk.sh, the
# disk_mode step or the bootloader modules change (scripts/test.sh --dualboot).
#
# --secureboot own|shim (with --encrypted) keeps the whole run and then turns Secure
# Boot on in the installed system the way a user does — `w-secureboot enable`, both
# phases — on a Secure Boot firmware: `own` on the Setup-Mode varstore (start.sh
# --secureboot), `shim` on a factory-like one with Microsoft's keys (--secureboot=ms,
# virt-fw-vars from virt-firmware). Three more boots:
#   S4  SB not enforcing yet → `enable` phase 1 (own: keys into the firmware; shim:
#       shim chain + MOK request). MokManager cannot be driven headless, so for shim
#       the harness takes W's public cert off the ESP, drops the queued request, and
#       pre-seeds MokList itself (virt-fw-vars --add-mok) while switching enforcing on.
#   S5  Secure Boot enforcing → the boot chain is the mode's; `enable` phase 2 seals
#       TPM2 to PCR7; the loaders follow a limine-update; W's NVRAM entry is deleted.
#   S6  headless boot through the removable fallback path under Secure Boot — the
#       disk unlocking with no passphrase proves both the signed fallback and the
#       PCR7 seal at once (a broken one hangs at the prompt → SSH timeout).
# Before S4 the S1 TPM2 seal is replaced by one bound to no PCR at all (test seam:
# the passphrase prompt cannot be answered headless while PCR7 is in flux); phase 2
# replaces it with the real PCR7 seal, which S6 then depends on. Local-only, like
# --dualboot (scripts/test.sh --secureboot).
#
# --iso-sb (with --encrypted) boots the install medium itself under Secure Boot, on
# Microsoft's keys (start.sh --secureboot=ms), the way a user meets it: shim, then
# Limine trusted only by its hash in MokList (scripts/iso-secureboot.sh). The hash
# is recomputed from the ISO here, not taken from the build's word for it. Before S1,
# three short boots that must FAIL, each read off the serial console:
#   SB0  no hash in MokList → shim refuses Limine ("Verification failed") → MokManager;
#   SB1  Secured-core db (Windows CA 2023 only) → the firmware refuses shim itself;
#   SB2  hash enrolled, airootfs.sfs tampered in a copy of the ISO → cms_verify stops
#        the initramfs in its rescue shell (a probe typed there through the QEMU
#        monitor answers on ttyS0 — only where /init exists and the medium is found).
# Then S1 installs encrypted from that firmware with the hash enrolled; the install
# log must say secure_boot=on, and the installer has run `w-secureboot enable` phase 1
# (shim) itself. MokManager cannot be driven headless, so the harness puts W's public
# cert (mirrored to the share by the installer) into MokList. S2 (firstboot: phase 2,
# the TPM2 seal on PCR7) and S3 run under Secure Boot, then S5/S6 as for --secureboot
# shim, minus the enable calls — the installer and firstboot made them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
E2E_DIR="$SCRIPT_DIR/e2e"
LOGS_DIR="$SCRIPT_DIR/logs"
PRESET="$E2E_DIR/preset.conf"
KEY="$E2E_DIR/id_ed25519"
STATUS_FILE="$LOGS_DIR/e2e-firstboot-status"

# Per-stage timeouts (seconds). S1 pacstraps over the network; S2 runs the full
# apply --all including on-target AUR builds — both legitimately take a while.
T_S1=2700
T_S2=5400
T_S3=600

die()  { echo -e "\033[1;31mE2E FAIL:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;35m==>\033[0m $*"; }

# ── Arguments / preconditions ─────────────────────────────────────────────────
ISO=""
ENCRYPTED=0
DUALBOOT=0
FAULT=0
SB_MODE=""
ISO_SB=0
while (($#)); do
  case "$1" in
    --iso) ISO="${2:-}"; [[ -n "$ISO" ]] || die "--iso needs a path"; shift ;;
    --encrypted) ENCRYPTED=1 ;;
    --dualboot) DUALBOOT=1 ;;
    --fault-mirror) FAULT=1 ;;
    --secureboot) SB_MODE="${2:-}"; shift ;;
    --iso-sb) ISO_SB=1 ;;
    *) die "unknown option: $1 (usage: e2e.sh [--iso PATH] [--encrypted] [--dualboot] [--fault-mirror] [--secureboot own|shim] [--iso-sb])" ;;
  esac
  shift
done
if [[ -n "$SB_MODE" ]]; then
  [[ "$SB_MODE" == own || "$SB_MODE" == shim ]] || die "--secureboot takes own or shim"
  (( ENCRYPTED )) || die "--secureboot needs --encrypted (Secure Boot exists on the Limine stack only)"
fi
if (( ISO_SB )); then
  (( ENCRYPTED )) || die "--iso-sb needs --encrypted (Secure Boot exists on the Limine stack only)"
  [[ -z "$SB_MODE" ]] && (( ! DUALBOOT )) || die "--iso-sb runs on its own, not with --secureboot or --dualboot"
fi

# ── Mirror fault scenario (installer.md §5 Ф.4) ───────────────────────────────
# Opt-in, and opt-in twice over: the scenario file below is what makes the
# installer's mod_fault_inject do anything at all, and it is deleted on every run
# that did not ask for it — so a normal gate run is byte-for-byte what it was.
FAULT_CONF="$E2E_DIR/fault.conf"
FAULT_PORT_BASE=18080
# One port per mirrorlist entry (see vm/fault-mirror.py): reflector saves at most
# --number 20, so 24 leaves headroom without the arming side having to wrap.
FAULT_PORTS=24
FAULT_PID=""
rm -f "$FAULT_CONF"

[[ "$(uname -s)" == Linux ]] || die "Arch/KVM host required (Linux only)."
[[ -e /dev/kvm ]]            || die "/dev/kvm not available."
command -v qemu-system-x86_64 &>/dev/null || die "qemu not installed."
command -v timeout &>/dev/null            || die "coreutils timeout not found."
if (( ENCRYPTED )); then
  # start.sh --tpm would catch this too, but only after the disk reset — die early.
  command -v swtpm &>/dev/null || die "--encrypted needs swtpm on the host (sudo pacman -S swtpm)."
fi
if [[ "$SB_MODE" == shim ]]; then
  command -v virt-fw-vars &>/dev/null || die "--secureboot shim needs virt-fw-vars (w-pack install w-dev → virt-firmware)."
fi
if (( ISO_SB )); then
  for c in virt-fw-vars xorriso mcopy python3; do
    command -v "$c" &>/dev/null || die "--iso-sb needs $c on the host (w-pack install w-dev)."
  done
  python3 -I -c 'import pefile' 2>/dev/null || die "--iso-sb needs python-pefile on the host."
fi

if [[ -z "$ISO" ]]; then
  ISO="$(ls -t "$PROJECT_DIR"/archiso/out/*.iso 2>/dev/null | head -1 || true)"
  [[ -n "$ISO" ]] || die "no ISO in archiso/out/ — build one (scripts/build-iso.sh) or pass --iso."
fi
[[ -f "$ISO" ]] || die "ISO not found: $ISO"
info "ISO: $ISO"

# ── Scenario → working preset → active slot + SSH key ─────────────────────────
S1_EXTRA=()
if (( DUALBOOT )); then
  # The dual copies inherit edge_repo from their stack's regular copy.
  if (( ENCRYPTED )); then
    SAMPLE="$E2E_DIR/preset-dualboot.sample.conf"
    WORK="$E2E_DIR/preset-dualboot.conf"
    PARENT="$E2E_DIR/preset-encrypted.conf"
    START_EXTRA=(--tpm)
  else
    SAMPLE="$E2E_DIR/preset-dualboot-plain.sample.conf"
    WORK="$E2E_DIR/preset-dualboot-plain.conf"
    PARENT="$E2E_DIR/preset-plain.conf"
    START_EXTRA=()
  fi
  # --force-iso: the disk is not blank any more, so make the ISO the first boot
  # device explicitly instead of relying on OVMF finding nothing bootable on it.
  S1_EXTRA=(--force-iso)
elif (( ENCRYPTED )); then
  SAMPLE="$E2E_DIR/preset-encrypted.sample.conf"
  WORK="$E2E_DIR/preset-encrypted.conf"
  START_EXTRA=(--tpm)
else
  SAMPLE="$E2E_DIR/preset-plain.sample.conf"
  WORK="$E2E_DIR/preset-plain.conf"
  START_EXTRA=()
fi

mkdir -p "$E2E_DIR" "$LOGS_DIR"
if [[ ! -f "$KEY" ]]; then
  info "Generating E2E SSH keypair..."
  ssh-keygen -q -t ed25519 -N '' -C w-e2e -f "$KEY"
fi
if [[ ! -f "$WORK" ]]; then
  info "Creating working preset $(basename "$WORK") from $(basename "$SAMPLE")..."
  cp "$SAMPLE" "$WORK"
  # A dual-boot copy inherits its stack's edge_repo (dev-edge + its credentials,
  # when set up) — otherwise a first --dualboot run would silently install the
  # public release instead of what the other phases test.
  if (( DUALBOOT )) && grep -q '^edge_repo=' "$PARENT" 2>/dev/null; then
    sed -i '/^edge_repo=/d' "$WORK"
    grep '^edge_repo=' "$PARENT" >> "$WORK"
  fi
fi
if ! grep -q '^ssh_authorized_key=' "$WORK"; then
  printf 'ssh_authorized_key=%q\n' "$(cat "$KEY.pub")" >> "$WORK"
fi
# Install the scenario as the active slot — the fixed path the ISO's .zlogin
# probes on the virtiofs share (/w-src/vm/e2e/preset.conf).
{ echo "# Written by e2e.sh from $(basename "$WORK") — edit that file, not this one."
  cat "$WORK"; } > "$PRESET"

# IdentitiesOnly=yes + IdentityAgent=none: use ONLY the -i key, never consult
# $SSH_AUTH_SOCK. Otherwise ssh offers agent identities first — on a dev machine
# running an SSH agent (e.g. Bitwarden) that pops an approval dialog (breaks the
# unattended run) and can trip "Too many authentication failures" before the -i key.
SSH=(ssh -p 2222 -i "$KEY" -o IdentitiesOnly=yes -o IdentityAgent=none
     -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=3 -o LogLevel=ERROR root@localhost)

# Kill a stage's leftover QEMU if we bail out mid-run. start.sh runs QEMU as a
# child (no exec — it keeps a trap of its own), so take out the children too.
QPID=""
TAMPERED="$E2E_DIR/iso-sb-tampered.iso"
cleanup() {
  rm -f "$TAMPERED" "$E2E_DIR"/iso-sb-*.mon "$E2E_DIR"/iso-sb-*.vars "$E2E_DIR/.s1-start"
  if [[ -n "$QPID" ]]; then
    kill -- -"$QPID" 2>/dev/null || true   # start.sh runs in a session of its own
    pkill -P "$QPID" 2>/dev/null || true
    kill "$QPID" 2>/dev/null || true
  fi
  # The scenario file must not outlive the run that asked for it: left behind, it
  # would silently arm the fault on the NEXT run, whose relay is not even running.
  rm -f "$FAULT_CONF"
  [[ -n "$FAULT_PID" ]] && kill "$FAULT_PID" 2>/dev/null || true
  # Same for the active preset, only worse: any later ISO boot on this host's QEMU
  # (start.sh --install) finds it on the share and wipes the VM disk unattended.
  rm -f "$PRESET"
}
trap cleanup EXIT

if (( FAULT )); then
  command -v python3 &>/dev/null || die "--fault-mirror needs python3 on the host."
  info "Fault scenario: starting the stalled-mirror relay on ports $FAULT_PORT_BASE-$((FAULT_PORT_BASE + FAULT_PORTS - 1))..."
  # Starts healthy. The sick window is armed by the guest at the moment of
  # injection (w-fault-arm calls /__ctl/sick), because it has to cover the first
  # transaction and expire before the retry — anchoring it to harness start-up
  # instead would make the window a race against how long the wizard takes.
  python3 "$SCRIPT_DIR/fault-mirror.py" --port "$FAULT_PORT_BASE" --ports "$FAULT_PORTS" \
    > "$LOGS_DIR/fault-mirror.log" 2>&1 &
  FAULT_PID=$!
  sleep 2
  kill -0 "$FAULT_PID" 2>/dev/null || die "fault relay died on start — see $LOGS_DIR/fault-mirror.log"
  # 10.0.2.2 is the host as seen from QEMU user-mode networking.
  { echo "# Written by e2e.sh --fault-mirror; deleted when the run ends."
    echo "FAULT_HOST=10.0.2.2"
    echo "FAULT_PORT_BASE=$FAULT_PORT_BASE"
    echo "FAULT_PORTS=$FAULT_PORTS"
    echo "FAULT_SICK_SECONDS=auto"
  } > "$FAULT_CONF"
fi

# ── S0 (--dualboot): the fake Windows' firmware boot entry ────────────────────
# A real Windows leaves "Windows Boot Manager" in NVRAM, pointing at bootmgfw.efi on
# its ESP; W's menus are built from that entry (w-boot-otheros). The image alone
# cannot carry it — NVRAM lives in OVMF_VARS — so one short boot of the UEFI shell
# (edk2-shell) writes it with bcfg, exactly as an OS installer would, and powers off.
# The shell and its startup.nsh sit on a throwaway read-only vvfat disk, not on the
# Windows ESP, which stays byte for byte what fake-windows.sh hashed. The disk is
# attached first, as in start.sh, so the entry's device path matches later boots.
seed_windows_nvram() {
  local shell=/usr/share/edk2-shell/x64/Shell.efi dir
  [[ -f "$shell" ]] || die "S0: no UEFI shell at $shell (w-pack install w-dev → edk2-shell)."
  # shellcheck source=vm/arch-iso.conf
  source "$SCRIPT_DIR/arch-iso.conf"
  dir="$(mktemp -d)"
  mkdir -p "$dir/EFI/BOOT"
  cp "$shell" "$dir/EFI/BOOT/BOOTX64.EFI"
  printf '%s\r\n' '@echo -off' 'for %a in fs0 fs1 fs2 fs3' \
    '  if exist %a:\EFI\Microsoft\Boot\bootmgfw.efi then' \
    '    bcfg boot add 0 %a:\EFI\Microsoft\Boot\bootmgfw.efi "Windows Boot Manager"' \
    '  endif' 'endfor' 'reset -s' > "$dir/startup.nsh"
  info "S0: writing the Windows NVRAM entry (UEFI shell, bcfg)..."
  timeout --foreground 180 qemu-system-x86_64 -enable-kvm -cpu host -m 1G \
    -global isa-fdc.fdtypeA=none \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$SCRIPT_DIR/OVMF_VARS.fd" \
    -drive file="$SCRIPT_DIR/w-base.qcow2",format=qcow2,if=none,id=hd0 \
    -device virtio-blk-pci,drive=hd0,bootindex=1 \
    -drive file="fat:$dir",format=raw,if=none,id=sh0,readonly=on \
    -device virtio-blk-pci,drive=sh0,bootindex=0 \
    -display none -no-reboot -net none > "$LOGS_DIR/e2e-s0.log" 2>&1 \
    || { rm -rf "$dir"; die "S0: the UEFI shell did not power off (see $LOGS_DIR/e2e-s0.log)."; }
  rm -rf "$dir"
}

# ── SB0–SB2 (--iso-sb): the install medium under Secure Boot must refuse ──────
# The firmware for these boots is built here, from the pristine template, each time:
# Microsoft's keys and enforcing, plus virt-fw-vars arguments of the caller's.
sb_vars() {  # <out> [virt-fw-vars args...]
  local out="$1"; shift
  # shellcheck source=vm/arch-iso.conf
  source "$SCRIPT_DIR/arch-iso.conf"
  virt-fw-vars --input "$OVMF_VARS" --output "$out" --enroll-redhat --secure-boot "$@" &>/dev/null \
    || die "virt-fw-vars could not build the Secure Boot varstore $(basename "$out")."
}
# A bare medium-only boot with the serial console and the QEMU monitor on files —
# no disk, no share, no TPM: nothing here gets far enough to want them. No
# -no-reboot either: OVMF may reset once on the first start of a fresh varstore
# (memory-type buckets), and the harness ends these boots itself.
sb_iso_boot() {  # <name> <vars> <iso>
  # shellcheck source=vm/arch-iso.conf
  source "$SCRIPT_DIR/arch-iso.conf"
  SB_SERIAL="$LOGS_DIR/e2e-iso-sb-$1.serial" SB_MON="$E2E_DIR/iso-sb-$1.mon"
  rm -f "$SB_SERIAL" "$SB_MON"
  qemu-system-x86_64 -enable-kvm -cpu host -m 3G -machine q35,smm=on \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE_SECBOOT" \
    -drive if=pflash,format=raw,file="$2" -cdrom "$3" -display none -vga std -net none \
    -serial file:"$SB_SERIAL" -monitor unix:"$SB_MON",server,nowait &>/dev/null &
  QPID=$!
}
sb_iso_down() { kill "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true; QPID=""; }
# Through the QEMU monitor: $1 typed on the guest's keyboard, one sendkey per
# character — or, with --cmd, $2 sent as a monitor command as is.
sb_type() {
  python3 -I - "$SB_MON" "$@" 2>/dev/null <<'EOF'
import socket, sys, time
keys = {' ': 'spc', '-': 'minus', '_': 'shift-minus', '/': 'slash', '.': 'dot',
        '>': 'shift-dot', '&': 'shift-7', '\n': 'ret'}
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.3); s.recv(65536)
if sys.argv[2] == '--cmd':
    s.sendall((sys.argv[3] + '\n').encode()); time.sleep(1)
    sys.exit()
for c in sys.argv[2]:
    k = keys.get(c) or ('shift-' + c.lower() if c.isupper() else c)
    s.sendall(('sendkey %s\n' % k).encode()); time.sleep(0.05)
EOF
}
# Waits up to $2 s for the fixed string $1 on the serial console; $3, when given, is
# typed again every 10 s meanwhile (a probe whose answer is what $1 looks for) — only
# from the 45th second on: earlier, its letters would land in Limine's menu (`s` opens
# the firmware setup). On a miss, says why and leaves the guest's screen next to the
# serial log.
sb_expect() {
  local start=$SECONDS deadline=$((SECONDS + $2))
  until grep -aqF -- "$1" "$SB_SERIAL" 2>/dev/null; do
    if ! kill -0 "$QPID" 2>/dev/null; then
      echo "QEMU exited after $((SECONDS - start)) s" >&2; return 1
    fi
    if (( SECONDS >= deadline )); then
      sb_type --cmd "screendump ${SB_SERIAL%.serial}.ppm" || true
      # Seen twice in three runs: the guest's serial output reaches the file only
      # when a monitor client connects (here, the screendump) — the screen already
      # showed the expected refusal, the serial was byte-identical to a passing run.
      # The assertion is about what the firmware says, not how fast QEMU flushes it.
      if grep -aqF -- "$1" "$SB_SERIAL" 2>/dev/null; then
        echo "  (serial arrived only after the monitor poke at $2 s)" >&2; return 0
      fi
      echo "nothing after $2 s; screen: ${SB_SERIAL%.serial}.ppm" >&2; return 1
    fi
    [[ -z "${3:-}" ]] || (( SECONDS - start < 45 )) || sb_type "$3" || true
    sleep 10
  done
}

if (( ISO_SB )); then
  # The hash a user's MokManager records from the medium's own grubx64.efi, read off
  # the ISO's EFI partition (appended partition 2) — and held against the build's.
  read -r esp_start _ < <(xorriso -no_rc -indev "$ISO" -report_system_area plain 2>/dev/null \
    | awk '$1=="MBR" && $2=="partition" && $6=="0xef" {print $7, $8; exit}')
  [[ -n "${esp_start:-}" ]] || die "SB: no EFI partition in $ISO."
  sbdir="$(mktemp -d)"
  mcopy -i "$ISO@@$((esp_start * 512))" ::/EFI/BOOT/grubx64.efi "$sbdir/" 2>/dev/null \
    || { rm -rf "$sbdir"; die "SB: no EFI/BOOT/grubx64.efi on the ISO's EFI partition — not a Secure Boot medium."; }
  MOK_HASH="$(python3 -I "$PROJECT_DIR/scripts/pe-authenticode.py" "$sbdir/grubx64.efi")"
  rm -rf "$sbdir"
  if [[ -f "$ISO.mok-sha256" ]]; then
    [[ "$(awk '{print $1}' "$ISO.mok-sha256")" == "$MOK_HASH" ]] \
      || die "SB: $(basename "$ISO").mok-sha256 does not match the ISO's grubx64.efi ($MOK_HASH)."
  fi
  info "SB: MokList hash of the medium: $MOK_HASH"
  SB_GUID=605dab50-e046-4300-abb6-3dd810dd8b23  # shim's vendor GUID, MokList's owner

  info "SB0: no hash in MokList — shim must refuse Limine..."
  sb_vars "$E2E_DIR/iso-sb-nohash.vars"
  sb_iso_boot nohash "$E2E_DIR/iso-sb-nohash.vars" "$ISO"
  sb_expect "Verification failed: (0x1A) Security Violation" 120 \
    || die "SB0: shim did not refuse the unenrolled second stage — see $SB_SERIAL"
  sb_iso_down

  info "SB1: Secured-core firmware (no 3rd-party CA) — the firmware must refuse shim..."
  sb_vars "$E2E_DIR/iso-sb-win23.vars" --microsoft-db win23
  sb_iso_boot win23 "$E2E_DIR/iso-sb-win23.vars" "$ISO"
  sb_expect "Access Denied" 120 || die "SB1: the firmware did not refuse shim — see $SB_SERIAL"
  sb_iso_down

  # The tamper sits mid-file in airootfs.sfs: kernel, initramfs and the EFI partition
  # stay byte for byte, so everything up to cms_verify passes as in the real boot.
  info "SB2: hash enrolled, airootfs.sfs tampered — cms_verify must stop the boot..."
  sb_vars "$E2E_DIR/iso-sb-hash.vars" --add-mok-hash "$SB_GUID" "$MOK_HASH"
  cp --reflink=auto "$ISO" "$TAMPERED"
  read -r sfs_lba sfs_blocks < <(xorriso -no_rc -indev "$TAMPERED" -find /w/x86_64/airootfs.sfs \
    -exec report_lba 2>/dev/null | awk -F, '/airootfs.sfs/ {print $2 + 0, $3 + 0}')
  [[ -n "${sfs_blocks:-}" ]] || die "SB2: airootfs.sfs not found on the ISO."
  dd if=/dev/urandom of="$TAMPERED" bs=2048 seek=$((sfs_lba + sfs_blocks / 2)) count=32 \
    conv=notrunc status=none
  sb_iso_boot cms "$E2E_DIR/iso-sb-hash.vars" "$TAMPERED"
  # /init exists only in the initramfs, the signature file only where the medium was
  # found and mounted: the answer means "stopped at verification", nothing else.
  # The leading Enter: a boot slow enough to still sit in Limine's menu at 45 s takes
  # it as "boot the default entry" — without it the probe's `s` opens Firmware Setup.
  sb_expect "w-cms-rejected" 240 \
    $'\ntest -e /init -a -e /run/archiso/bootmnt/w/x86_64/airootfs.sfs.cms.sig && echo w-cms-rejected >/dev/ttyS0\n' \
    || die "SB2: no rescue shell after a tampered airootfs.sfs — cms_verify did not stop the boot (see $SB_SERIAL)."
  sb_iso_down
  rm -f "$TAMPERED"

  S1_EXTRA+=(--secureboot=ms)
  info "SB: refusals OK — S1 installs from the medium under Secure Boot."
fi

# ── A stage's VM under a deadline ─────────────────────────────────────────────
# start.sh in a session of its own: on a timeout the whole process group goes —
# QEMU, and the swtpm/virtiofsd it started — not just the wrapper (a QEMU left
# alive holds swtpm and fails every later stage). First a screendump through the
# monitor: a silent hang leaves nothing else to look at.
run_vm() {  # <stage> <seconds> <start.sh args...>
  local stage="$1" deadline=$((SECONDS + $2)) rc=0; shift 2
  local mon="$E2E_DIR/$stage.mon"
  rm -f "$mon"
  setsid bash "$SCRIPT_DIR/start.sh" --monitor="$mon" "$@" &
  QPID=$!
  while kill -0 "$QPID" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      SB_MON="$mon" sb_type --cmd "screendump $LOGS_DIR/e2e-$stage-timeout.ppm" || true
      echo "$stage: out of time; screen: $LOGS_DIR/e2e-$stage-timeout.ppm" >&2
      kill -- -"$QPID" 2>/dev/null || true
      wait "$QPID" 2>/dev/null || true
      QPID=""; rm -f "$mon"
      return 124
    fi
    sleep 5
  done
  wait "$QPID" || rc=$?
  QPID=""; rm -f "$mon"
  return "$rc"
}

# ── S1: ISO boot → unattended install ─────────────────────────────────────────
rm -f "$STATUS_FILE" "$LOGS_DIR/w-install-mok.cer"
info "S1: resetting disk..."
bash "$SCRIPT_DIR/reset-disk.sh"
if (( DUALBOOT )); then
  info "S1: laying the fake Windows onto the disk..."
  bash "$SCRIPT_DIR/fake-windows.sh"
  seed_windows_nvram
fi
# S1's firmware under --iso-sb: start.sh --secureboot=ms reads this varstore. Written
# only now — reset-disk.sh above deletes the Secure Boot varstores.
(( ISO_SB )) && sb_vars "$SCRIPT_DIR/OVMF_VARS.secboot-ms.fd" --add-mok-hash "$SB_GUID" "$MOK_HASH"
S1_START="$E2E_DIR/.s1-start"; touch "$S1_START"
info "S1: booting ISO (headless, unattended install — up to $((T_S1 / 60)) min)..."
run_vm S1 "$T_S1" --install --headless --no-reboot --iso="$ISO" "${START_EXTRA[@]}" "${S1_EXTRA[@]}" \
  || die "S1: QEMU did not exit cleanly (timeout = install never rebooted; see $LOGS_DIR)."

# The installer mirrors its log through the share; its last line confirms S1
# actually finished (a wedged installer would have hit the timeout instead, but
# an early exit back to the live shell would not). Only a log this S1 wrote counts:
# an older run's log would answer for an install that never happened.
S1_LOG="$(find "$LOGS_DIR" -maxdepth 1 -name 'w-install-*.log' -newer "$S1_START" -printf '%T@ %p\n' \
  | sort -rn | head -1 | cut -d' ' -f2-)"
rm -f "$S1_START"
[[ -n "$S1_LOG" ]] || die "S1: no install log mirrored by this run in $LOGS_DIR."
grep -q "Unattended install complete" "$S1_LOG" \
  || die "S1: install did not reach its finish line — see $S1_LOG"
info "S1 OK ($(basename "$S1_LOG"))."

if (( ISO_SB )); then
  grep -q "^firmware: secure_boot=on$" "$S1_LOG" \
    || die "S1: the install log does not record an enforcing Secure Boot — see $S1_LOG"
  [[ -s "$LOGS_DIR/w-install-mok.cer" ]] \
    || die "S1: the installer left no W-MOK.cer — Secure Boot phase 1 did not run (see $S1_LOG)."
  # What a user does in MokManager on the next boot ("Enroll key from disk").
  MS_VARS="$SCRIPT_DIR/OVMF_VARS.secboot-ms.fd"
  { virt-fw-vars --input "$MS_VARS" --output "$MS_VARS.new" \
      --add-mok "$SB_GUID" "$LOGS_DIR/w-install-mok.cer" &>/dev/null \
    && mv -f "$MS_VARS.new" "$MS_VARS"; } || die "S1: could not put W's key into MokList."
  START_EXTRA+=(--secureboot=ms)
  info "S1: W's key in MokList — the installed system boots under Secure Boot from here."
fi

# ── S1 fault assertions (installer.md §5 Ф.4) ─────────────────────────────────
# POSITIVE assertions, and that is the whole point. A survived flake deliberately
# writes no CRITICAL: (the seam reserves that tag for terminal failure, so that
# "no CRITICAL apply warnings" below stays green on exactly the case this exists
# to fix) — so "the log has no errors" would pass on a build where the fault never
# fired at all. What has to be proved is that it DID fire and was survived.
#
# Not asserted, deliberately: "the dead host moved to the head of the list". When
# the whole pool is sick every entry is blamed, so demoting all of them preserves
# their relative order and the head does not change — correct behaviour (there is
# nowhere better to go), but it makes the check vacuous here. That the retry
# genuinely reorders is pinned by pac.bats instead, on a fake pacman where only
# some mirrors fail.
if (( FAULT )); then
  info "S1: fault-scenario assertions:"
  fault_assert() {
    local desc="$1" pattern="$2"
    if grep -qE "$pattern" "$S1_LOG"; then
      echo "  PASS  $desc"
    else
      die "S1 fault assertion failed: $desc (no /$pattern/ in $S1_LOG)"
    fi
  }
  fault_assert "the fault was actually injected after mirror selection" \
    'MIRRORS: fault injected — [0-9]+ mirror\(s\) routed through'
  fault_assert "layer 1 still ran first and left its evidence" \
    'MIRRORS: reflector ranked'
  fault_assert "pacstrap hit the stalled pool and the seam classified it as transport" \
    'PAC: pacstrap attempt 1/[0-9]+ failed on .* \(class=network\)'
  fault_assert "the blamed mirrors were demoted rather than dropped" \
    'PAC: pacstrap attempt 1/[0-9]+ .*demoted to the bottom'
  fault_assert "the half-built target keyring was reset before the retry" \
    'PAC: dropping the target.s half-built keyring'
  fault_assert "pacstrap survived on a later attempt" \
    'PAC: pacstrap succeeded on attempt [0-9]+ after a network failure'
  # The one thing a stalled pool must never be mistaken for. If the classifier ever
  # read this as a package/keyring truth it would refuse to retry and the install
  # would die — which is precisely the three release-gate failures.
  grep -q 'CRITICAL' "$S1_LOG" \
    && die "S1 fault assertion failed: the install log carries a CRITICAL — the flake was not survived"
  echo "  PASS  a survived flake left no CRITICAL in the install log"
fi

# ── S2: first boot → w-firstboot (apply --all) ────────────────────────────────
info "S2: booting installed disk (firstboot apply --all — up to $((T_S2 / 60)) min)..."
run_vm S2 "$T_S2" --headless --no-reboot "${START_EXTRA[@]}" \
  || die "S2: QEMU did not exit cleanly (timeout = firstboot hung; see $LOGS_DIR)."

[[ -f "$STATUS_FILE" ]] || die "S2: no firstboot status marker — w-firstboot never finished."
STATUS="$(cat "$STATUS_FILE")"
[[ "$STATUS" == ok ]] || die "S2: firstboot reported '$STATUS' — see $LOGS_DIR (firstboot log + diag bundle)."
info "S2 OK (firstboot status: $STATUS)."

# ── S3: clean boot → assertions over SSH ──────────────────────────────────────
info "S3: booting final system..."
setsid bash "$SCRIPT_DIR/start.sh" --headless "${START_EXTRA[@]}" &
QPID=$!

# SSH up, then the boot barrier below. $1 = stage label. A function because the
# Secure Boot stages (S4–S6) boot the same system three more times.
wait_booted() {
  local stage="$1" deadline=$((SECONDS + T_S3))
  info "$stage: waiting for SSH..."
  until "${SSH[@]}" true 2>/dev/null; do
    (( SECONDS < deadline )) || die "$stage: SSH never came up within $((T_S3 / 60)) min."
    kill -0 "$QPID" 2>/dev/null || die "$stage: QEMU exited before SSH came up."
    sleep 5
  done
  info "$stage: waiting for the boot to finish..."
  until [[ "$(boot_state)" =~ ^(running|degraded)$ ]]; do
    (( SECONDS < deadline )) || die "$stage: the system never left 'starting' within $((T_S3 / 60)) min.
$("${SSH[@]}" 'systemctl is-system-running; systemctl list-jobs' 2>&1 || true)"
    kill -0 "$QPID" 2>/dev/null || die "$stage: QEMU exited while the boot was still coming up."
    sleep 3
  done
}

# ── The boot barrier ──────────────────────────────────────────────────────────
# "SSH answers" is not "the system booted", and asserting through that gap makes
# the whole S3 battery measure a half-booted machine. sshd is up before
# multi-user.target; greetd starts after it AND after plymouth-quit-wait, so there
# is a one-to-two second window in which `systemctl is-active greetd` honestly
# answers "inactive".
#
# Measured on the 2026-09-07 nightly: the SSH probe landed in the same second sshd
# started listening, the first three assertions ran inside that window, and
# `greetd is active` failed a fraction of a second before `Started Greeter daemon.`
# — a red run about nothing. The night before was green because the probe happened
# to land four seconds later on the same five-second grid; nothing else differed.
#
# The flake is the smaller half. In that same window `0 failed system units` and
# `0 coredumps` are falsely GREEN: a unit that dies on the last second of boot is
# not there yet when they look. Same rule as an assertion that cannot read its own
# input — it must fail, never report on a system it did not measure.
#
# Gate on "left the starting state", not on "reached running": `degraded` is a
# legitimate outcome, and it belongs to the `0 failed system units` assertion
# below. A barrier that waited for `running` would swallow the very signal it
# exists to make honest.
#
# Only an explicit terminal state ends the wait. An unreadable answer — a dropped
# connection, an empty string, `unknown` — keeps waiting until the deadline rather
# than falling through to the assertions, for the same reason: not knowing is not
# permission to proceed. `is-system-running --wait` blocks with no ceiling of its
# own, hence both the per-call `timeout` and the shared T_S3 deadline.
boot_state() {
  "${SSH[@]}" 'timeout 20 systemctl is-system-running --wait >/dev/null 2>&1
               systemctl is-system-running' 2>/dev/null | tail -1
}

wait_booted S3

FAILED=0
assert() {
  local desc="$1"; shift
  local out
  if out="$("${SSH[@]}" "$@" 2>&1)"; then
    echo "  PASS  $desc"
  else
    echo "  FAIL  $desc"
    [[ -n "$out" ]] && sed 's/^/        /' <<< "$out"
    FAILED=1
  fi
}

info "S3: assertions:"
assert "0 failed system units" \
  '[[ -z "$(systemctl --failed --no-legend)" ]] || { systemctl --failed --no-legend; exit 1; }'
assert "0 coredumps" \
  'if coredumpctl -q list --no-legend &>/dev/null; then coredumpctl -q list --no-legend; exit 1; fi'
assert "greetd is active" 'systemctl is-active greetd'
assert "firstboot flag cleared" 'test ! -e /var/lib/w/.firstboot-pending'
# apply.sh's `crit()` tags install steps that are mandatory but can legitimately
# fail on real hardware without network at firstboot-time (non-fatal there, so
# apply.sh itself doesn't die on it). e2e guarantees network, so any CRITICAL
# here is a real regression, not an expected offline branch — gate on it.
assert "no CRITICAL apply warnings" '! grep -q "CRITICAL:" /var/log/w/apply.log'
# Hardening asserted on the OUTCOME (/proc/cmdline), not on the config file that was
# supposed to produce it — because the config file was green for the whole time the
# feature was broken. mod_harden wrote GRUB_CMDLINE_LINUX_DEFAULT and ran grub-mkconfig
# unconditionally; on the encrypted path Limine boots /etc/kernel/cmdline and reads
# neither, and since grub is installed on both paths (base.txt) nothing ever failed —
# the tokens simply never reached a kernel. Only the booted cmdline can tell those apart,
# and it does so identically on both bootloaders.
assert "kernel hardening reached the running kernel" \
  'for t in init_on_alloc=1 init_on_free=1 slab_nomerge randomize_kstack_offset=1 page_alloc.shuffle=1 vsyscall=none debugfs=off; do grep -qw -- "$t" /proc/cmdline || { echo "missing from /proc/cmdline: $t"; exit 1; }; done'
assert "hardening sysctl drop-ins active" \
  'test -f /etc/sysctl.d/90-w-kernel.conf && test -f /etc/sysctl.d/90-w-fs.conf && test -f /etc/sysctl.d/90-w-net.conf'
assert "goose (AI host) installed" 'command -v goose'
# The .snapshots mount points must be plain directories, not the subvolumes snapper's
# create-config leaves behind (fix_snapper flattens them). A nested subvolume there is
# invisible under the mount but is a child of @/@home, and a rollback that moves the
# outgoing root's children renames an active mount point → EBUSY, which is exactly how
# the first real Limine rollback failed. Asserted on both boot paths: the same
# create-config runs on each; only the Limine rollback trips over the result.
# Tested through a subvolid=5 mount rather than `btrfs subvolume list`: the mount
# points are covered by @snapshots/@home_snapshots in the live tree (so `show` there
# reports the WRONG subvolume), and list -a prints `<FS_TREE>/` on some rows and not
# others depending on where it is run from — a grep over it silently stops matching.
assert "no nested .snapshots subvolume under @ / @home" \
  'set -e
   t=$(mktemp -d); rc=0
   mount -o subvolid=5 "$(findmnt -no SOURCE / | sed "s/\[.*//")" "$t"
   for d in @/.snapshots @home/.snapshots; do
     if btrfs subvolume show "$t/$d" &>/dev/null; then echo "nested subvolume: $d"; rc=1; fi
   done
   umount "$t"; rmdir "$t"; exit $rc'

if (( FAULT )); then
  # pacstrap copies the host mirrorlist into the target once the packages land, so
  # whatever the fault run left behind is what this machine would live with for
  # good. The installer un-arms that copy right after pacstrap (mod_fault_restore);
  # these two assertions are what proves it, and they are the reason a failed fault
  # run cannot hand the next person a machine that silently cannot update.
  assert "the installed mirrorlist carries no relay URLs" \
    '! grep -q "10\.0\.2\.2:180" /etc/pacman.d/mirrorlist'
  # Depth is the invariant the whole seam is built around: pacman's own "too many
  # errors from X, skipping" fallback only works while somewhere is left to go, so
  # a run that survived by TRIMMING the list would be a regression, not a pass.
  # 10 is MIRRORS_MIN from scripts/install/modules/base.sh — kept as a literal here
  # because this runs on the host, where that file is not sourced.
  assert "the inherited list kept its depth (>= 10 servers)" \
    '[[ "$(grep -c "^Server" /etc/pacman.d/mirrorlist)" -ge 10 ]] ||
       { grep -c "^Server" /etc/pacman.d/mirrorlist; exit 1; }'
  assert "the inherited list still resolves to real mirrors" \
    'grep -qE "^Server *= *https?://[a-z]" /etc/pacman.d/mirrorlist'
fi

# ── Multi-user matrix ─────────────────────────────────────────────────────────
# Updating W is a multi-user contract, and a single-account VM proves none of it:
# only members of `wheel` may escalate, git over the checkout always runs as the
# checkout's owner, and the sync state is one file for the whole machine. So the
# two missing roles are created right here — a second ADMIN who does not own the
# checkout, and a NON-ADMIN. (The dev VM keeps the same pair as a permanent
# fixture, devtools/usr/local/bin/w-test-users; an e2e system is throwaway, so it
# grows its own inline and drops them again below.)
#
# Every command starts with `cd /`: runuser keeps root's cwd, and an unprivileged
# child cannot chdir into /root (0700). HOME is passed explicitly for the same
# class of reason — runuser hands root's environment to the target user.
#
# What is deliberately NOT asserted: the polkit/sudo prompt itself. It asks for a
# password on a terminal headless does not have, so that half of the matrix is
# walked by a human (see update-system.md); everything up to the prompt is here.
info "S3: creating the multi-user fixture (second admin + non-admin)..."
"${SSH[@]}" 'useradd -m -G wheel admin2 && useradd -m plain' \
  || die "S3: could not create the multi-user test accounts."

assert "a non-admin is refused before any escalation (w-sync update)" \
  'cd /; out=$(runuser -u plain -- env HOME=/home/plain w-sync update 2>&1) && exit 1; grep -q "requires administrator rights" <<< "$out"'
# Not a duplicate of the above: it proves the refusal comes from the shared
# w-priv-lib gate rather than from something w-sync does on its own.
assert "the same gate answers in another escalating tool (w-update upgrade)" \
  'cd /; out=$(runuser -u plain -- env HOME=/home/plain w-update upgrade 2>&1) && exit 1; grep -q "requires administrator rights" <<< "$out"'
# core._is_admin() is the Python twin that guards every Tier-2 AI tool in one
# place (core._actuate). If the two definitions of "admin" ever drift, the AI path
# raises a prompt nobody in that session can answer — assert they still agree.
assert "the AI-side twin of the admin gate agrees with the CLI" \
  'cd /; runuser -u plain  -- env PYTHONPATH=/usr/lib/w/w-mcp python3 -c "import core; raise SystemExit(0 if not core._is_admin() else 1)" &&
        runuser -u admin2 -- env PYTHONPATH=/usr/lib/w/w-mcp python3 -c "import core; raise SystemExit(0 if core._is_admin() else 1)"'

# Delivering the config is the other half of the same contract. /etc/skel only
# ever reaches an account at useradd time, so before this a second administrator
# kept the shell their account was born with, forever — a successful update and a
# stale Hub at the same time. Stale all three homes deliberately, re-apply the
# module, and check BOTH ownership classes in one pass: managed must be refreshed
# everywhere, user-owned must survive everywhere, and a user file that is missing
# from a home must be seeded there (that is how a NEW user-class file added by an
# update reaches an account that already exists). /var/lib/w/src holds the source
# on both channels — a git checkout on edge, a plain copy otherwise — so this
# block belongs here, not in the edge-only half.
#
# The user-owned marker is INJECTED into bar.json, not written over it: this disk
# outlives the run as the dev VM (see the header), and a bar.json replaced by a
# stub is a shell with an empty bar for whoever boots it next. `shell.qml` and
# `volume.json` need no such care — the re-apply below restores both.
info "S3: staling every account's shell config, then re-applying..."
"${SSH[@]}" 'set -e; for u in w admin2 plain; do
    q=/home/$u/.config/quickshell/w
    echo STALE > "$q/shell.qml"
    jq "._e2e = \"user-edit\"" "$q/config/bar.json" > "$q/config/bar.json.e2e"
    mv "$q/config/bar.json.e2e" "$q/config/bar.json"
    rm -f "$q/config/volume.json"
    chown -R $u:$u "$q"
  done' || die "S3: could not stale the fixture accounts' shell config."
"${SSH[@]}" 'bash /var/lib/w/src/scripts/apply.sh --quickshell' &>/dev/null \
  || die "S3: apply.sh --quickshell failed."

assert "a managed shell file is refreshed for EVERY account, not just the first" \
  'for u in w admin2 plain; do grep -q STALE /home/$u/.config/quickshell/w/shell.qml && exit 1; done; exit 0'
assert "a user-owned config file survives the same re-apply, for every account" \
  'for u in w admin2 plain; do grep -q _e2e /home/$u/.config/quickshell/w/config/bar.json || exit 1; done'
assert "a user-owned file absent from a home is seeded there, for every account" \
  'for u in w admin2 plain; do test -s /home/$u/.config/quickshell/w/config/volume.json || exit 1; done'

# Which kernel boots next is a Hub row, and the Hub asks for it as the desktop user —
# but BOTH bootloaders keep that answer in a root-only file (the ESP is mounted
# dmask=0077, and grub-mkconfig writes grub.cfg under `umask 077` unconditionally), so
# a fresh install of either kind rendered "—" while `w-kernel list` as root looked
# perfect. That is why this runs as the NON-ADMIN account: asserting it as root is
# exactly the check that stayed green through the whole bug. The mirror that fixes it
# is written where the default is pinned (refresh_boot / 50-w-default-entry).
assert "the desktop user can see which kernel boots (the Hub's kernel row)" \
  'cd /; runuser -u plain -- w-kernel list --porcelain |
     awk -F"\t" "NR>1 && \$5==\"yes\" {n++} END {exit !(n==1)}"'

if (( DUALBOOT )); then
  # What disk_mode=free promises, measured on the result. The reference hashes were
  # taken from the image before S1 (fake-windows.sh): the Windows ESP, MSR and NTFS
  # must read back identical — no format, no fsck, no mount-time write, no resize.
  SUMS="$LOGS_DIR/e2e-dualboot.sha256"
  [[ -s "$SUMS" ]] || die "S3: no dual-boot reference hashes ($SUMS)."
  sum_cmd=""
  while read -r n h; do
    sum_cmd+="[[ \"\$(sha256sum /dev/vda$n | cut -d\" \" -f1)\" == $h ]] || { echo \"vda$n changed\"; rc=1; }; "
  done < "$SUMS"
  assert "the foreign partitions are byte for byte what they were before S1" "rc=0; $sum_cmd exit \$rc"
  assert "no foreign partition is mounted" \
    '! findmnt -rno SOURCE | grep -E "^/dev/vda[123]$"'
  assert "W runs off its own ESP (not the Windows one)" \
    'esp=$(findmnt -no SOURCE /boot/efi); [[ "$esp" != /dev/vda1 && "$(lsblk -no PARTLABEL "$esp")" == "W EFI" ]] || { echo "ESP: $esp"; exit 1; }'
  # Limine registers "W (Limine)"; GRUB's non-removable grub-install, "W".
  if (( ENCRYPTED )); then label='W \(Limine\)'; else label='W'; fi
  assert "NVRAM carries the W entry for that ESP" \
    'n=$(cat /sys/class/block/$(basename "$(findmnt -no SOURCE /boot/efi)")/partition)
     efibootmgr | grep -qE "^Boot[0-9A-F]{4}\*? '"$label"'[[:space:]]+HD\($n,GPT" || { efibootmgr; exit 1; }'
  assert "the firmware has the Windows entry S0 wrote, and W detects it" \
    '/usr/lib/w/w-boot-otheros | grep -qP "^[0-9A-F]{4}\tWindows Boot Manager$" || { efibootmgr; exit 1; }'
fi

# Windows keeps the RTC in local time: RTC=auto follows it (firstboot's mod_time),
# and every other run keeps UTC.
if (( DUALBOOT )); then rtc=yes rtc_desc=local; else rtc=no rtc_desc=UTC; fi
assert "hardware clock in $rtc_desc time (RTC=auto)" \
  '[[ "$(timedatectl show -p LocalRTC --value)" == '"$rtc"' ]] || { w-time status; exit 1; }'

# The boot menu next to Windows: an entry that reboots into the firmware's Windows
# entry (never a chainload — BitLocker), and the menu shown. Without Windows the
# opposite, and that half runs on every e2e: the menu stays hidden, no foreign entry.
if (( ENCRYPTED )); then
  if (( DUALBOOT )); then
    assert "Limine menu offers Windows via its firmware entry, and is shown" \
      'c=/boot/efi/limine.conf
       grep -qx "/Windows Boot Manager" $c && grep -qx "    protocol: efi_boot_entry" $c &&
       grep -qx "    entry: Windows Boot Manager" $c && grep -qx "quiet: no" $c &&
       grep -qx "timeout: 5" $c || { cat $c; exit 1; }'
  else
    assert "Limine menu stays quiet, no foreign entry" \
      'c=/boot/efi/limine.conf
       grep -qx "quiet: yes" $c && ! grep -q efi_boot_entry $c || { cat $c; exit 1; }'
  fi
else
  if (( DUALBOOT )); then
    assert "GRUB menu offers Windows via BootNext, and is shown" \
      'c=/boot/grub/grub.cfg
       grep -q "^menuentry .Windows Boot Manager. .*w-bootnext-" $c &&
       grep -qx "set timeout_style=menu" $c && ! grep -q chainloader $c || { cat $c; exit 1; }'
  else
    assert "GRUB menu stays hidden, no foreign entry" \
      'c=/boot/grub/grub.cfg
       ! grep -q -e w-bootnext -e efi-bootnext -e "^set timeout_style=menu" $c &&
       grep -q "set timeout_style=hidden" $c || { cat $c; exit 1; }'
  fi
fi

if (( ENCRYPTED )); then
  # The very fact S2/S3 booted headless already proves the TPM2 unlock worked —
  # these pin the stack's identity: root on the LUKS mapping, the tpm2 token in
  # the LUKS header, Limine (not GRUB) on the ESP.
  assert "root LUKS mapping active" 'cryptsetup status cryptroot | grep -q "is active"'
  assert "TPM2 unlock token enrolled" \
    'cryptsetup luksDump "$(cryptsetup status cryptroot | awk "/device:/ {print \$2}")" | grep -q systemd-tpm2'
  # The install seals to no PCR (its live PCR 7 is the medium's); firstboot rebinds
  # the seal to PCR 7 of this boot chain — S3 unlocking headless proves it matches.
  assert "firstboot resealed TPM2 to PCR 7, nothing left pending" \
    '! test -e /var/lib/w/tpm-reseal-pending &&
     cryptsetup luksDump --dump-json-metadata "$(cryptsetup status cryptroot | awk "/device:/ {print \$2}")" |
       jq -e "[.tokens[] | select(.type == \"systemd-tpm2\") | .\"tpm2-pcrs\"] == [[7]]"'
  assert "Limine deployed" 'test -f /etc/default/limine && test -f /boot/efi/EFI/limine/limine_x64.efi'
  # w-boot-otheros reads Windows out of efibootmgr's text — this pins that text on the
  # one entry every encrypted install has, so a format change upstream fails the
  # nightly canary rather than silently emptying the menus of dual-boot machines.
  # Installed under Secure Boot, W's entry is shim's "W" (Limine's own was dropped).
  nv_label='W \(Limine\)'
  if (( ISO_SB )); then nv_label='W'; fi
  assert "efibootmgr still prints what w-boot-otheros parses" \
    'efibootmgr | grep -qP "^Boot[0-9A-F]{4}\*? '"$nv_label"'\t(\S*/)?HD\([0-9]+,GPT,[0-9a-fA-F-]{36}," || { efibootmgr; exit 1; }'
  # ── The ESP staging path (the encrypted stack's single point of failure) ──────
  # Limine cannot read the LUKS root, so /boot is not what it boots — the ESP copy
  # is, and only limine-mkinitcpio-hook keeps that copy current. When its AUR build
  # broke upstream (gradle 9.7.0, 2026-08) the install still reported success and
  # the machine quietly stopped receiving kernel updates at the loader. "Limine
  # deployed" above stayed green throughout, because the seed ESP is deployed by
  # the installer itself — hence these three, which test the live path instead.
  assert "limine kernel-install tooling installed" \
    'command -v limine-mkinitcpio && command -v limine-update'
  assert "limine-snapper-sync enabled" 'systemctl is-enabled limine-snapper-sync.service'
  # A real rebuild, not a file listing: w-mkinitcpio is what every W caller uses, so
  # this walks the same fork the kernel's alpm hooks walk. The paths come out of
  # limine.conf rather than being guessed, because THAT is what the loader will read
  # — the managed entry names both halves as `boot():/<path>#<BLAKE2B>`. Four things
  # have to hold at once, and each one failed for real at some point: the files exist,
  # the kernel is the installed one, the initramfs was built for that same kernel (a
  # mismatched pair boots to a rescue shell), and the hash in the config still matches
  # the file (a restage that skips the config regen panics Limine under Secure Boot).
  assert "a rebuild lands a matching, correctly-hashed kernel+initramfs pair on the ESP" \
    'set -e
     conf=/boot/efi/limine.conf
     w-mkinitcpio >/dev/null
     k=$(sed -n "s|^ *path: boot():||p" "$conf" | grep -v "^/EFI/" | head -1)
     i=$(sed -n "s|^ *module_path: boot():||p" "$conf" | head -1)
     [[ -n "$k" && -n "$i" ]] || { echo "limine.conf names no managed kernel entry"; exit 1; }
     ih=${i#*#}; k=${k%%#*}; i=${i%%#*}
     test -s "/boot/efi$k" && test -s "/boot/efi$i"
     kver=$(lsinitcpio --nocolor -a "/boot/efi$i" | sed -n "s/.*Kernel: *//p" | head -1)
     test -n "$kver" && test -d "/usr/lib/modules/$kver" \
       || { echo "ESP initramfs was built for ${kver:-?}, not for the installed kernel"; exit 1; }
     # Against the package image limine-mkinitcpio copies, not /boot/vmlinuz-*: once
     # sbctl holds keys, its mkinitcpio post hook signs the /boot copy (nothing boots it).
     cmp -s "/boot/efi$k" "/usr/lib/modules/$kver/vmlinuz" \
       || { echo "ESP kernel differs from the installed /usr/lib/modules/$kver/vmlinuz"; exit 1; }
     [[ "$(b2sum "/boot/efi$i" | cut -d" " -f1)" == "$ih" ]] \
       || { echo "limine.conf carries a stale BLAKE2B for the staged initramfs"; exit 1; }'
  # The encrypted preset is also the EDGE preset, so this is the only scenario where
  # w-sync has a real git checkout to work on. These run over SSH *as root*, which is
  # precisely the path that used to fail: /var/lib/w/src belongs to the user, and git
  # refused to touch it for a root shell (no SUDO_UID) while quietly reporting
  # "behind: 0". w-sync now runs git as the checkout's owner instead.
  assert "w-sync log works from a root shell" 'w-sync log'
  # The state is machine-wide (/var/lib/w/state/sync.json), written by root here and
  # read by every user's Hub — so it must exist, parse, and carry a real count.
  assert "w-sync check records an honest behind-count" \
    'w-sync check && python3 -m json.tool /var/lib/w/state/sync.json >/dev/null && ! grep -q "\"behind\": *-1" /var/lib/w/state/sync.json'
  assert "the sync state is world-readable and owned by the checkout owner" \
    '[[ "$(stat -c %a /var/lib/w/state/sync.json)" == 644 && "$(stat -c %U /var/lib/w/state)" == "$(stat -c %U /var/lib/w/src)" ]]'
  assert "the checkout owner reads the same machine-wide state" \
    'cd /; o=$(stat -c %U /var/lib/w/src); runuser -u "$o" -- env HOME="$(getent passwd "$o" | cut -d: -f6)" w-sync status | grep -q "^Source : /var/lib/w/state/sync.json"'
  assert "no root-owned objects in the user checkout" \
    '[[ -z "$(find /var/lib/w/src/.git -user root -print -quit)" ]] || { find /var/lib/w/src/.git -user root | head -20; exit 1; }'
  # The edge-only half of the multi-user matrix — these need a real checkout and a
  # real state file, which only this scenario has.
  #
  # A second admin owns no checkout, so before the machine-wide state existed the
  # honest answer available to them was "no idea". Now `log` answers from the file
  # every user's Hub reads, read-only and without touching git.
  assert "a second admin reads the machine-wide state without owning the checkout" \
    'cd /; runuser -u admin2 -- env HOME=/home/admin2 w-sync log | grep -q "reading the last recorded check"'
  # …and when they do want to update, they are pointed at sudo (where w-sync runs
  # as root and drives git as the owner) rather than being turned away as if they
  # were not an admin. Two different refusals; conflating them would hide the bug.
  assert "a second admin is sent to sudo, not turned away as a non-admin" \
    'cd /; out=$(runuser -u admin2 -- env HOME=/home/admin2 w-sync update 2>&1) && exit 1; grep -q "run w-sync as that user, or via sudo" <<< "$out"'
  # The old per-user state let every user's check timer write its own file, so a
  # non-owner recorded a fresh-looking lie. Now their check is a no-op that leaves
  # the shared file untouched — and, because this runs without a tty exactly like
  # the 6-hourly timer does, it must also stay quiet: the explanatory line w-sync
  # prints to a human is isatty-gated, and losing that gate would put it in every
  # non-owner's journal four times a day.
  assert "a non-owner check is a no-op that touches neither the state nor the journal" \
    'cd /; S=/var/lib/w/state/sync.json; b=$(stat -c %y "$S"); out=$(runuser -u plain -- env HOME=/home/plain w-sync check 2>&1) || exit 1; [[ -z "$out" && "$b" == "$(stat -c %y "$S")" ]]'

  # ── Release signatures ───────────────────────────────────────────────────────
  # The edge channel runs apply.sh as root on whatever it pulls, so the signature
  # check is its entire security boundary. The unit suite proves the logic; these
  # prove it is actually armed on an installed machine — the anchor arrived, the
  # strictness derived at install time matches what the checkout tracks, and a tip
  # this machine cannot verify is refused before anything is touched.
  assert "the release trust anchor is deployed and holds a usable key" \
    'k=$(awk "!/^[[:space:]]*#/ && NF >= 3 { print \$2\" \"\$3; exit }" /usr/share/w/update/w-release.allowed_signers) &&
     test -n "$k" && printf "%s\n" "$k" | ssh-keygen -lf - >/dev/null'
  # Derived once by mod_updatesys from the remote the checkout actually tracks:
  # strict on the official repository, open on anything else (a fork, or the dev
  # repo, where there are no release tags to find). Asserted as that relationship
  # rather than as a fixed value, because both kinds of preset exist.
  #
  # git runs as the checkout OWNER, never as the root this assertion is executed by.
  # /var/lib/w/src is user-owned by design, so git's ownership guard (CVE-2022-24765)
  # refuses it for everyone else — root's only exemption is a repo owned by $SUDO_UID,
  # which a root ssh session does not have. `w-sync` itself is built on exactly this
  # rule (git_c), and the neighbouring assertions already follow it; this one did not,
  # and read an empty URL. Which was invisible, because an unreadable remote fell into
  # the `*)` branch and was answered as "some other remote" — green on a dev preset,
  # where that branch is also the correct one. So the read is now a hard failure of
  # its own: an origin this assertion cannot determine proves nothing either way.
  assert "signature checking is armed to match the tracked remote" \
    'u=$(stat -c %U /var/lib/w/src) && h=$(getent passwd "$u" | cut -d: -f6) || exit 1
     o=$(cd / && runuser -u "$u" -- env -u XDG_CONFIG_HOME HOME="$h" git -C /var/lib/w/src remote get-url origin) || exit 1
     [[ -n "$o" ]] || { echo "the tracked remote could not be read — nothing to match against"; exit 1; }
     s=$(w-sync status | sed -n "s/^Signed : //p")
     case "${o%.git}" in
       https://github.com/tarkh/w) [[ "$s" == required* ]] ;;
       *)                          [[ "$s" == "NOT required"* ]] ;;
     esac || { echo "origin=$o signed=$s"; exit 1; }'
  # The refusal itself, driven end to end. The checkout is rewound one commit so an
  # update is genuinely attempted, the anchor is swapped for a key nothing was signed
  # with, and the run must stop with the machine untouched — same HEAD, nothing
  # pulled. Both the anchor and the original HEAD are restored either way, so this
  # leaves the system exactly as it found it whether it passes or fails.
  assert "an update whose tag it cannot verify is refused, changing nothing" \
    'set -u; A=/usr/share/w/update/w-release.allowed_signers; o=$(stat -c %U /var/lib/w/src)
     [[ "$(w-sync status | sed -n "s/^Signed : //p")" == required* ]] || { echo "not armed here — nothing to prove"; exit 0; }
     h=$(getent passwd "$o" | cut -d: -f6)
     g() { cd /; runuser -u "$o" -- env HOME="$h" git -C /var/lib/w/src "$@"; }
     H=$(g rev-parse HEAD); g rev-parse --verify -q HEAD~1 >/dev/null || { echo "history too short to test"; exit 0; }
     cp -a "$A" "$A.e2e-bak"
     restore() { mv -f "$A.e2e-bak" "$A"; g reset --hard "$H" >/dev/null 2>&1; rm -f /tmp/e2e-notrust /tmp/e2e-notrust.pub; }
     trap restore EXIT
     rm -f /tmp/e2e-notrust /tmp/e2e-notrust.pub
     ssh-keygen -q -t ed25519 -N "" -C e2e -f /tmp/e2e-notrust
     printf "w-release@w.tarkh.com %s\n" "$(awk "{print \$1\" \"\$2}" /tmp/e2e-notrust.pub)" > "$A"
     g reset --hard HEAD~1 >/dev/null
     R=$(g rev-parse HEAD)
     out=$(w-sync update --yes 2>&1) && { echo "$out"; echo "the update was NOT refused"; exit 1; }
     grep -qE "REFUSING TO UPDATE|no release tag" <<< "$out" || { echo "$out"; exit 1; }
     [[ "$(g rev-parse HEAD)" == "$R" ]] || { echo "the checkout moved despite the refusal"; exit 1; }'
  # Recovery must not cost more than it repairs. Both halves were broken at once and
  # both were reachable from the refusal message above: restoring any managed system
  # file put it back mode 644, so `w-reset updatesys` left /usr/bin/w-sync unexecutable
  # (exit 126 — no way left to update at all), and the module's vendor default said
  # CHANNEL=stable, so the same command took the machine off the edge channel. Found
  # live 2026-09-03, fixed the day after; asserted here because nothing static sees it.
  # The narrow form is what w-sync now prints, so it is the one proven to work.
  assert "the per-file form restores just the anchor" \
    'set -u; A=/usr/share/w/update/w-release.allowed_signers; C=$(cat /etc/w/update.conf)
     cp -a "$A" "$A.e2e-bak"
     trap "[[ -s $A ]] || mv -f $A.e2e-bak $A; rm -f $A.e2e-bak" EXIT
     rm -f "$A"
     w-reset updatesys w-release.allowed_signers >/dev/null
     test -s "$A" || { echo "the anchor was not restored"; exit 1; }
     [[ "$(cat /etc/w/update.conf)" == "$C" ]] || { echo "update.conf changed under a per-file reset"; exit 1; }'
  assert "a full module reset keeps the client runnable and the channel intact" \
    'set -u; C=$(grep ^CHANNEL /etc/w/update.conf)
     w-reset updatesys >/dev/null
     test -x /usr/bin/w-sync || { echo "w-sync came back without its executable bit"; exit 1; }
     w-sync status >/dev/null || { echo "w-sync no longer runs after its own module reset"; exit 1; }
     [[ "$(grep ^CHANNEL /etc/w/update.conf)" == "$C" ]] || { echo "the update channel changed: $C -> $(grep ^CHANNEL /etc/w/update.conf)"; exit 1; }'
fi

# Drop the fixture before the diagnostics bundle, so the archived system state is
# the one the installer actually produces.
info "S3: removing the multi-user fixture..."
"${SSH[@]}" 'userdel -rf admin2; userdel -rf plain' &>/dev/null || true

# Final-boot diagnostics for the record (mirrors into vm/logs via the share).
info "S3: collecting final diag bundle (best-effort)..."
"${SSH[@]}" 'bash /var/lib/w/src/scripts/collect-logs.sh' &>/dev/null || true

if [[ -n "$SB_MODE" ]]; then
  # The test seam (see the header): TPM2 bound to no PCR, so S4/S5 unlock headless
  # while the Secure Boot state moves under PCR7. The passphrase comes from the preset.
  eval "$(grep '^luks_pass=' "$WORK" | tail -1)"
  LUKS_PW="$(printf %q "${luks_pass:-}")"
  "${SSH[@]}" "PASSWORD=$LUKS_PW"' systemd-cryptenroll "$(cryptsetup status cryptroot | awk "/device:/ {print \$2}")" --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=' >/dev/null \
    || die "S3: could not re-bind TPM2 to no PCR for the Secure Boot stages."
fi

"${SSH[@]}" 'systemctl poweroff' 2>/dev/null || true
wait "$QPID" 2>/dev/null || true
QPID=""

# ── S4–S6 (--secureboot): Secure Boot turned on in the installed system ───────
# --iso-sb comes in at S5: the installer ran phase 1, firstboot phase 2, and the
# firmware (S1's varstore, W's key added) has been enforcing since S1.
SB_ISO_PHASES=0
if (( ISO_SB )); then SB_MODE=shim; SB_ISO_PHASES=1; fi
if [[ -n "$SB_MODE" ]] && (( FAILED == 0 )); then
  # Firmware: own → start.sh's Setup-Mode varstore (seeded from the plain one, so the
  # boot entries come along); shim → Microsoft's keys, NOT enforcing yet: a user turns
  # Secure Boot on after the shim chain is in place, never before. The enroll
  # shortcut itself turns SecureBootEnable on, hence the explicit --set-false.
  MS_VARS="$SCRIPT_DIR/OVMF_VARS.secboot-ms.fd"
  if (( SB_ISO_PHASES )); then
    SB_START=(--secureboot=ms --tpm)
  elif [[ "$SB_MODE" == shim ]]; then
    SB_START=(--secureboot=ms --tpm)
    virt-fw-vars --input "$SCRIPT_DIR/OVMF_VARS.fd" --output "$MS_VARS" --enroll-redhat \
      --set-false SecureBootEnable &>/dev/null \
      || die "S4: virt-fw-vars could not build the Microsoft-keyed varstore."
  else
    SB_START=(--secureboot --tpm)
  fi
  sb_boot() { setsid bash "$SCRIPT_DIR/start.sh" --headless "${SB_START[@]}" & QPID=$!; wait_booted "$1"; }
  sb_down() { "${SSH[@]}" 'systemctl poweroff' 2>/dev/null || true; wait "$QPID" 2>/dev/null || true; QPID=""; }
  # Remote prelude: `cur` prints the firmware entry BootCurrent points at.
  CURRENT='cur() { local c; c=$(efibootmgr | sed -n "s/^BootCurrent: *//p"); efibootmgr | grep "^Boot$c"; }; '
  # shim: W's entry first, Limine's own (the firmware rejects it) — if any — last of the
  # boot entries; the firmware's built-in apps (FvVol) are left out, OVMF moves them.
  SHIM_ORDER='fv=",$(efibootmgr | grep FvVol | sed -n "s/^Boot\([0-9A-F]*\).*/\1/p" | paste -sd,),"
    o=$(efibootmgr | sed -n "s/^BootOrder: *//p" | tr , "\n" | while read -r b; do [[ $fv == *,$b,* ]] || echo $b; done | paste -sd,)
    num() { efibootmgr | grep -i "$1" | sed -n "s/^Boot\([0-9A-F]*\).*/\1/p"; }
    w=$(num "EFI.W.shimx64.efi"); l=$(num "EFI.limine.limine_x64.efi")
    [[ -n $w && $o == $w,* ]] && { [[ -z $l ]] || [[ $o == *,$l ]]; } || { efibootmgr; exit 1; }'
  # The 6th column of `status --porcelain`: does the config hash in the loaders match?
  hash_is() { echo 'w-secureboot status --porcelain | awk -F"\t" "NR==2 && \$6==\"'"$1"'\" {ok=1} END {exit !ok}"'; }

  if (( ! SB_ISO_PHASES )); then
    info "S4: Secure Boot firmware ($SB_MODE), not enforcing yet — enable, phase 1..."
    sb_boot S4
    "${SSH[@]}" 'w-secureboot enable' > "$LOGS_DIR/e2e-sb-phase1.log" 2>&1 \
      || die "S4: w-secureboot enable (phase 1) failed — see $LOGS_DIR/e2e-sb-phase1.log"
    assert "enable picked the $SB_MODE mode from the firmware, and asks for a reboot" \
      'w-secureboot status --porcelain | awk -F"\t" "NR==2 && \$4==\"reboot_needed\" && \$5==\"'"$SB_MODE"'\" {ok=1} END {exit !ok}"'
    if [[ "$SB_MODE" == shim ]]; then
      assert "the firmware boots W's shim entry first, Limine's own entry last" "$SHIM_ORDER"
      "${SSH[@]}" 'cat /boot/efi/EFI/W/W-MOK.cer' > "$LOGS_DIR/e2e-sb-mok.cer" \
        || die "S4: no W-MOK.cer on the ESP."
      "${SSH[@]}" 'mokutil --revoke-import' &>/dev/null || true
    fi
    sb_down
    (( FAILED == 0 )) || die "Secure Boot phase 1 assertions failed."
    if [[ "$SB_MODE" == shim ]]; then
      # 605dab50-… is shim's vendor GUID — the owner mokutil records for its imports.
      { virt-fw-vars --input "$MS_VARS" --output "$MS_VARS.new" --secure-boot \
          --add-mok 605dab50-e046-4300-abb6-3dd810dd8b23 "$LOGS_DIR/e2e-sb-mok.cer" &>/dev/null \
        && mv -f "$MS_VARS.new" "$MS_VARS"; } || die "S4: could not pre-seed MokList / turn Secure Boot on."
    fi
  fi

  info "S5: Secure Boot enforcing — the mode's boot chain, enable phase 2..."
  sb_boot S5
  assert "Secure Boot is enforcing" 'mokutil --sb-state | grep -qx "SecureBoot enabled"'
  if [[ "$SB_MODE" == shim ]]; then
    assert "booted through W's shim entry, with W's key in MokList" \
      "$CURRENT"'cur | grep -qi "EFI.W.shimx64.efi" &&
       test -e /sys/firmware/efi/efivars/MokListRT-605dab50-e046-4300-abb6-3dd810dd8b23 &&
       mokutil --test-key /boot/efi/EFI/W/W-MOK.cer | grep -q "already enrolled" || { efibootmgr; exit 1; }'
    assert "the boot order survived the reboot: shim entry first, Limine's own last" "$SHIM_ORDER"
  else
    assert "the firmware runs W's own keys, booting W's Limine entry" \
       "$CURRENT"'sbctl status | grep -q "Setup Mode:.*Disabled" && cur | grep -qi "EFI.limine.limine_x64.efi" || { efibootmgr; exit 1; }'
  fi
  if (( SB_ISO_PHASES )); then
    assert "the medium's hash stays in MokList (unattended queues no MokManager step)" \
      '! test -e /sys/firmware/efi/efivars/MokNew-605dab50-e046-4300-abb6-3dd810dd8b23 &&
       ! test -e /sys/firmware/efi/efivars/MokDel-605dab50-e046-4300-abb6-3dd810dd8b23'
  else
    "${SSH[@]}" "PASSWORD=$LUKS_PW w-secureboot enable" > "$LOGS_DIR/e2e-sb-phase2.log" 2>&1 \
      || die "S5: w-secureboot enable (phase 2) failed — see $LOGS_DIR/e2e-sb-phase2.log"
  fi
  assert "phase 2 finished: on, no reseal pending, mode reported" \
    'w-secureboot status --porcelain | awk -F"\t" "NR==2 && \$1==\"on\" && \$4==\"no\" && \$5==\"'"$SB_MODE"'\" {ok=1} END {exit !ok}"'
  assert "TPM2 is sealed to PCR7" \
    'cryptsetup luksDump --dump-json-metadata "$(cryptsetup status cryptroot | awk "/device:/ {print \$2}")" |
       jq -e "[.tokens[] | select(.type == \"systemd-tpm2\") | .\"tpm2-pcrs\"] == [[7]]"'
  # A regeneration (what every kernel update or snapshot does) must leave the mode's
  # loaders consistent with the config Limine will read.
  if [[ "$SB_MODE" == shim ]]; then
    assert "after limine-update, both grubx64.efi carry .sbat, the current config hash, a signature" \
      'limine-update &>/dev/null; e=/boot/efi; h=$(b2sum $e/limine.conf | cut -c1-128)
       for d in W BOOT; do g=$e/EFI/$d/grubx64.efi
         strings -n 128 $g | grep -q "$h" || { echo "$g: stale config hash"; exit 1; }
         sbctl verify $g | grep -q "✓" || { echo "$g: not signed"; exit 1; }
         objdump -h $g | grep -q " \.sbat " || { echo "$g: no .sbat"; exit 1; }
       done
       cmp -s $e/EFI/BOOT/BOOTX64.EFI /usr/share/shim-signed/shimx64.efi || { echo "the fallback is not shim"; exit 1; }'
    entry='EFI.W.shimx64.efi'
  else
    assert "after limine-update, the fallback is the signed, hash-enrolled Limine" \
      'limine-update &>/dev/null; e=/boot/efi
       cmp -s $e/EFI/BOOT/BOOTX64.EFI $e/EFI/limine/limine_x64.efi || { echo "the fallback differs from limine_x64.efi"; exit 1; }
       sbctl verify $e/EFI/BOOT/BOOTX64.EFI | grep -q "✓" || { echo "the fallback is not signed"; exit 1; }'
    entry='EFI.limine.limine_x64.efi'
  fi
  assert "status reports the config hash current" "$(hash_is ok)"
  # The guard: an edit past limine-entry-tool leaves the enrolled hash behind, and
  # Limine would halt S6 on CHECKSUM MISMATCH unless w-secureboot-guard re-enrolls at
  # this poweroff. S6 booting at all is the rest of this assertion.
  assert "an edit past limine-entry-tool is reported stale, the shutdown guard is armed" \
    'echo "# e2e: edited past limine-entry-tool" >> /boot/efi/limine.conf; '"$(hash_is stale)"' &&
     systemctl is-active -q w-secureboot-guard.service'
  # S6 has to reach the system through the removable path: drop W's own entry.
  "${SSH[@]}" 'for n in $(efibootmgr | grep -i "'"$entry"'" | sed -n "s/^Boot\([0-9A-F]*\).*/\1/p"); do efibootmgr -b $n -B >/dev/null; done'
  sb_down
  (( FAILED == 0 )) || die "Secure Boot phase 2 assertions failed."

  # Reaching SSH at all is the main assertion here: nobody types a passphrase in a
  # headless boot, so the disk was unlocked by the PCR7 seal of phase 2, and the
  # loader that started was the removable fallback under an enforcing firmware.
  info "S6: Secure Boot, fallback path only — must unlock and boot headless..."
  sb_boot S6
  assert "booted from the removable fallback path, Secure Boot enforcing" \
     "$CURRENT"'mokutil --sb-state | grep -qx "SecureBoot enabled" && ! cur | grep -qiE "EFI.(W|limine)." || { efibootmgr; exit 1; }'
  assert "the shutdown guard re-enrolled the edited limine.conf, the hash is current" \
    'journalctl -b -1 -u w-secureboot-guard.service | grep -q "re-enrolling" && '"$(hash_is ok)"
  sb_down
fi

if [[ $FAILED -eq 0 ]]; then
  info "E2E PASS — full pipeline: ISO → install → firstboot → clean boot."
else
  die "assertions failed on the final boot (diag bundle mirrored to $LOGS_DIR)."
fi
