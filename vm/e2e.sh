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
#   bash vm/e2e.sh [--iso PATH] [--encrypted] [--fault-mirror]
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
# The selected working copy is installed as vm/e2e/preset.conf — the machine-
# written "active slot" the ISO's .zlogin looks for — before S1. --encrypted
# also attaches a swtpm TPM (start.sh --tpm) to every stage: the installer
# auto-enrolls TPM2 unlock in S1 (limine_enroll_tpm), and S2/S3 boots rely on
# it — without a TPM the headless LUKS unlock would hang at the passphrase
# prompt. Logs and the firstboot status marker land in vm/logs/ as usual.
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
FAULT=0
while (($#)); do
  case "$1" in
    --iso) ISO="${2:-}"; [[ -n "$ISO" ]] || die "--iso needs a path"; shift ;;
    --encrypted) ENCRYPTED=1 ;;
    --fault-mirror) FAULT=1 ;;
    *) die "unknown option: $1 (usage: e2e.sh [--iso PATH] [--encrypted] [--fault-mirror])" ;;
  esac
  shift
done

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

if [[ -z "$ISO" ]]; then
  ISO="$(ls -t "$PROJECT_DIR"/archiso/out/*.iso 2>/dev/null | head -1 || true)"
  [[ -n "$ISO" ]] || die "no ISO in archiso/out/ — build one (scripts/build-iso.sh) or pass --iso."
fi
[[ -f "$ISO" ]] || die "ISO not found: $ISO"
info "ISO: $ISO"

# ── Scenario → working preset → active slot + SSH key ─────────────────────────
if (( ENCRYPTED )); then
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
cleanup() {
  if [[ -n "$QPID" ]]; then
    pkill -P "$QPID" 2>/dev/null || true
    kill "$QPID" 2>/dev/null || true
  fi
  # The scenario file must not outlive the run that asked for it: left behind, it
  # would silently arm the fault on the NEXT run, whose relay is not even running.
  rm -f "$FAULT_CONF"
  [[ -n "$FAULT_PID" ]] && kill "$FAULT_PID" 2>/dev/null || true
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

# ── S1: ISO boot → unattended install ─────────────────────────────────────────
rm -f "$STATUS_FILE"
info "S1: resetting disk..."
bash "$SCRIPT_DIR/reset-disk.sh"
info "S1: booting ISO (headless, unattended install — up to $((T_S1 / 60)) min)..."
timeout --foreground "$T_S1" \
  bash "$SCRIPT_DIR/start.sh" --install --headless --no-reboot --iso="$ISO" "${START_EXTRA[@]}" \
  || die "S1: QEMU did not exit cleanly (timeout = install never rebooted; see $LOGS_DIR)."

# The installer mirrors its log through the share; its last line confirms S1
# actually finished (a wedged installer would have hit the timeout instead, but
# an early exit back to the live shell would not).
S1_LOG="$(ls -t "$LOGS_DIR"/w-install-*.log 2>/dev/null | head -1 || true)"
[[ -n "$S1_LOG" ]] || die "S1: no mirrored install log in $LOGS_DIR."
grep -q "Unattended install complete" "$S1_LOG" \
  || die "S1: install did not reach its finish line — see $S1_LOG"
info "S1 OK ($(basename "$S1_LOG"))."

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
timeout --foreground "$T_S2" \
  bash "$SCRIPT_DIR/start.sh" --headless --no-reboot "${START_EXTRA[@]}" \
  || die "S2: QEMU did not exit cleanly (timeout = firstboot hung; see $LOGS_DIR)."

[[ -f "$STATUS_FILE" ]] || die "S2: no firstboot status marker — w-firstboot never finished."
STATUS="$(cat "$STATUS_FILE")"
[[ "$STATUS" == ok ]] || die "S2: firstboot reported '$STATUS' — see $LOGS_DIR (firstboot log + diag bundle)."
info "S2 OK (firstboot status: $STATUS)."

# ── S3: clean boot → assertions over SSH ──────────────────────────────────────
info "S3: booting final system..."
bash "$SCRIPT_DIR/start.sh" --headless "${START_EXTRA[@]}" &
QPID=$!

info "S3: waiting for SSH..."
deadline=$((SECONDS + T_S3))
until "${SSH[@]}" true 2>/dev/null; do
  (( SECONDS < deadline )) || die "S3: SSH never came up within $((T_S3 / 60)) min."
  kill -0 "$QPID" 2>/dev/null || die "S3: QEMU exited before SSH came up."
  sleep 5
done

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
assert "goose (AI host) installed" 'command -v goose'

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

if (( ENCRYPTED )); then
  # The very fact S2/S3 booted headless already proves the TPM2 unlock worked —
  # these pin the stack's identity: root on the LUKS mapping, the tpm2 token in
  # the LUKS header, Limine (not GRUB) on the ESP.
  assert "root LUKS mapping active" 'cryptsetup status cryptroot | grep -q "is active"'
  assert "TPM2 unlock token enrolled" \
    'cryptsetup luksDump "$(cryptsetup status cryptroot | awk "/device:/ {print \$2}")" | grep -q systemd-tpm2'
  assert "Limine deployed" 'test -f /etc/default/limine && test -f /boot/efi/EFI/limine/limine_x64.efi'
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
     cmp -s "/boot/efi$k" /boot/vmlinuz-linux-zen \
       || { echo "ESP kernel differs from the installed /boot/vmlinuz-linux-zen"; exit 1; }
     kver=$(lsinitcpio --nocolor -a "/boot/efi$i" | sed -n "s/.*Kernel: *//p" | head -1)
     test -n "$kver" && test -d "/usr/lib/modules/$kver" \
       || { echo "ESP initramfs was built for ${kver:-?}, not for the installed kernel"; exit 1; }
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
  assert "signature checking is armed to match the tracked remote" \
    'o=$(git -C /var/lib/w/src remote get-url origin 2>/dev/null); s=$(w-sync status | sed -n "s/^Signed : //p");
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
fi

# Drop the fixture before the diagnostics bundle, so the archived system state is
# the one the installer actually produces.
info "S3: removing the multi-user fixture..."
"${SSH[@]}" 'userdel -rf admin2; userdel -rf plain' &>/dev/null || true

# Final-boot diagnostics for the record (mirrors into vm/logs via the share).
info "S3: collecting final diag bundle (best-effort)..."
"${SSH[@]}" 'bash /var/lib/w/src/scripts/collect-logs.sh' &>/dev/null || true

"${SSH[@]}" 'systemctl poweroff' 2>/dev/null || true
wait "$QPID" 2>/dev/null || true
QPID=""

if [[ $FAILED -eq 0 ]]; then
  info "E2E PASS — full pipeline: ISO → install → firstboot → clean boot."
else
  die "assertions failed on the final boot (diag bundle mirrored to $LOGS_DIR)."
fi
