# modules/limine.sh — Limine bootloader + encrypted-boot prep (UEFI)
#
# ENCRYPTED install path only (CONF_ENCRYPT=true). Parallels grub.sh: the functions
# work in both the install context (MNT/chroot set by the installer) and the live
# system (apply.sh --limine, MNT=""). Layout on the encrypted stack:
#   - /boot        : directory inside @ on the LUKS-encrypted btrfs (kernel/initramfs
#                    live here and ARE snapshotted with @).
#   - /boot/efi    : the FAT ESP (large, ~2G). Limine can't read the LUKS root, so the
#                    Limine EFI binary, limine.conf, and STAGED copies of the current +
#                    per-snapshot kernel/initramfs live here.
# The AUR helpers (limine-mkinitcpio-hook + limine-snapper-sync) auto-manage entries and
# staging once installed; mod_limine pulls them in the LIVE context (they are NOT in the
# shared aur.txt — their pacman hooks would touch the ESP on plain GRUB systems too).
# The first boot runs off a hand-written limine.conf seeded here (before AUR tooling and
# before Secure Boot enforcement exists), then limine-update takes over post-boot.

# Compatibility shim: apply.sh uses info(), install context uses ui_info()
command -v ui_info &>/dev/null || ui_info() { info "$@"; }
# crit() is apply.sh's "mandatory step failed, and e2e gates on it" tag. The
# install context has no such notion (it dies instead), and never reaches the
# live-only branch that raises one — keep the file sourceable there anyway.
command -v crit &>/dev/null || crit() { echo -e "\033[1;31mCRITICAL:\033[0m $*"; }

# ── Encrypted initramfs prep (install context only) ──────────────────────────
# Switches mkinitcpio to a systemd-based initramfs with sd-encrypt and writes the
# shared kernel cmdline. MUST run before mod_plymouth's single `mkinitcpio -P`
# (mod_plymouth then inserts `plymouth` after `kms`, giving the correct hook order:
# `kms plymouth ... block sd-encrypt filesystems` — splash themes the unlock prompt).
limine_prep_initramfs() {
  local mkconf="$MNT/etc/mkinitcpio.conf"
  ui_info "Configuring encrypted initramfs (sd-encrypt)..."
  sed -i 's|^HOOKS=.*|HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)|' "$mkconf"

  local part2 uuid
  part2="$(part "$CONF_DISK" 2)"
  uuid="$(blkid -s UUID -o value "$part2")"
  mkdir -p "$MNT/etc/kernel"
  # One shared cmdline for all kernels/snapshots. rootflags subvol=@ is overridden
  # per-snapshot by limine-snapper-sync. `quiet splash` → Plymouth. TPM2 unlock (once
  # enrolled by `w-crypt enroll-tpm`) is auto-tried by systemd-cryptsetup — no cmdline
  # flag needed; the passphrase stays as the mandatory fallback.
  echo "rd.luks.name=${uuid}=${LUKS_NAME} root=/dev/mapper/${LUKS_NAME} rootflags=subvol=@ rw quiet splash" \
    > "$MNT/etc/kernel/cmdline"
}

# ── Unattended TPM2 auto-unlock enrollment (install context only) ─────────────
# Interactive installs deliberately leave TPM2 enrollment to the operator post-boot
# (`w-crypt enroll-tpm`). A headless preset install has nobody at the console to type
# the LUKS passphrase, so every boot of the pipeline (the firstboot reboot included)
# would hang at the unlock prompt — enroll auto-unlock right here in S1 instead.
# Same policy as w-crypt's default: PCR 7 (Secure Boot state; identical between this
# ISO boot and the installed system — SB is off/unchanged in both, verify on the
# first live run). No TPM → warn and continue: the install itself still succeeds,
# each boot then needs a human for the passphrase (TPM-less fleet hardware). A TPM
# that is present but fails to enroll is fatal — better a loud die now than a silent
# hour-long timeout on an invisible unlock prompt later.
limine_enroll_tpm() {
  if [[ ! -e /dev/tpmrm0 ]]; then
    echo "WARN: no TPM 2.0 device — skipping auto-unlock enrollment; every boot will ask for the LUKS passphrase."
    return 0
  fi
  ui_info "Enrolling TPM2 auto-unlock (PCR 7)..."
  local part2; part2="$(part "$CONF_DISK" 2)"
  # systemd-cryptenroll authorizes the new slot with the existing passphrase — hand
  # it over as a root-only key file (never argv). Runs in the chroot: the target has
  # the tpm2 stack via mod_limine's tpm2-tools, and arch-chroot bind-mounts /dev.
  local keyfile="$MNT/root/.w-luks-enroll"
  (umask 077; printf '%s' "$CONF_LUKS_PASS" > "$keyfile")
  local rc=0
  chroot_run systemd-cryptenroll "$part2" --unlock-key-file=/root/.w-luks-enroll \
    --tpm2-device=auto --tpm2-pcrs=7 || rc=$?
  rm -f "$keyfile"
  (( rc == 0 )) || die "TPM2 enrollment failed (rc=$rc) — headless boots would hang at the passphrase prompt."
}

# ── /etc/default/limine — consumed by the AUR limine-update post-boot ─────────
# $1 = target file path, $2 = enroll-config (yes|no) for Secure Boot.
limine_write_default() {
  local file="$1" enroll="$2"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# Managed by W (mod_limine). Overrides /etc/limine-entry-tool.conf.
# Kernel cmdline is read from /etc/kernel/cmdline.
ESP_PATH="/boot/efi"

# Plain kernel+initramfs (NOT UKI): smaller ESP, and Limine-native per-snapshot cmdline
# for limine-snapper-sync. Toggle ENABLE_UKI=yes later if UKIs are ever preferred.
ENABLE_UKI=no

# Keep an unsigned Limine at the removable fallback path (EFI/BOOT/BOOTX64.EFI) so a
# blocked boot (e.g. a stale enrolled config hash under Secure Boot) is always recoverable.
ENABLE_LIMINE_FALLBACK=yes

# Secure Boot: enroll a BLAKE2B hash of limine.conf into the signed Limine binary. When
# on, every limine.conf change must be re-enrolled. The re-enroll runs automatically via
# limine-mkinitcpio-hook's shipped boot hooks (pre.d/10-limine-reset-enroll +
# post.d/90-limine-enroll-config), fired after every limine.conf write. Our
# post.d/50-w-default-entry sorts before 90-, so the enrolled hash covers the corrected
# default_entry. (Legacy COMMANDS_BEFORE_SAVE/AFTER_SAVE would duplicate those hooks and
# are deprecated by limine-snapper-sync — omitted on purpose.)
ENABLE_ENROLL_LIMINE_CONFIG=$enroll
EOF
}

# ── post.d hook — pin default_entry at the bootable kernel LEAF ────────────────
# limine-entry-tool (limine-update) and limine-snapper-sync regenerate limine.conf
# with `default_entry` reset to its default `1`. Index 1 selects the `/+<OS>` BRANCH
# — a non-bootable directory — so Limine hangs before the menu ever renders (see the
# retire_seed note below). A one-shot sed can't survive the async snapper-sync re-runs;
# limine-entry-tool's own post.d hooks are the fix — they run after EVERY limine.conf
# write (snapper-sync included, same channel as 90-limine-enroll-config). This hook
# repoints default_entry to `<branch>/<first kernel leaf>` (Limine entry-path form,
# CONFIG.md). Prefix 50- sorts before 90-limine-enroll-config so the enrolled Secure
# Boot hash is computed over the already-corrected config. $1 = target hook path.
limine_write_default_entry_hook() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
#!/usr/bin/env bash
# Managed by W (mod_limine). Pin Limine's default_entry at the bootable kernel leaf,
# not the auto-generated /+<OS> branch (index 1 = branch = boot hang).
set -u
esp="/boot/efi"
[[ -f /etc/default/limine ]] && esp="$(awk -F'"' '/^ESP_PATH=/{print $2}' /etc/default/limine)"
esp="${esp:-/boot/efi}"
conf="$esp/limine.conf"
[[ -f "$conf" ]] || exit 0

# First top-level branch name (/+Name) and its first depth-2 kernel leaf (//name).
# Excludes the //Snapshots sub-branch and deeper snapshot entries (///, ////).
branch="$(sed -n 's#^/+##p' "$conf" | head -1)"
kernel="$(sed -n 's#^[[:space:]]*//\([^/].*\)#\1#p' "$conf" | grep -vx 'Snapshots' | head -1)"
[[ -n "$branch" && -n "$kernel" ]] || exit 0
target="${branch}/${kernel}"

if grep -q '^default_entry:' "$conf"; then
  current="$(sed -n 's#^default_entry:[[:space:]]*##p' "$conf" | head -1)"
  [[ "$current" == "$target" ]] && exit 0
  sed -i "s#^default_entry:.*#default_entry: ${target}#" "$conf"
else
  # Insert after the leading comment header, before the first non-comment line.
  sed -i "0,/^[^#]/s#^\([^#]\)#default_entry: ${target}\n\1#" "$conf"
fi
EOF
  chmod 755 "$file"
}

# ── First-boot limine.conf (theme header + one entry) ────────────────────────
# $1 = target limine.conf, $2 = kernel cmdline, $3 = mnt prefix (for logo staging).
# Post-boot limine-update regenerates the entries; w-style renders the theme header.
limine_write_conf() {
  local file="$1" cmdline="$2" mnt="$3"

  # Seed the BRANDED look already at install time — the very first Limine menu (shown before
  # the OS and the firstboot `apply --all` ever run) must carry the theme palette, not bare
  # black. Source the baseline theme.conf and emit the SAME top-level keys the w-style
  # 'limine' axis writes (900-limine/module.sh), so nothing shifts after the first render.
  # No logo (the logo lives in GRUB/Plymouth; Limine's menu sits center-screen so a centered
  # logo clashed with it). term_background is the whole-screen fill without a wallpaper;
  # backdrop matches as a fallback. w-style re-renders this per active theme later.
  local theme_conf=""
  local c
  for c in "${SRC:-}/rootfs/etc/w/themes/w/theme.conf" \
           "${mnt}/etc/w/themes/w/theme.conf" \
           "/etc/w/themes/w/theme.conf"; do
    [[ -n "$c" && -f "$c" ]] && { theme_conf="$c"; break; }
  done

  # Resolve palette tokens in a SUBSHELL so the installer env is not polluted with W_* vars.
  # Hex values are '#rrggbb'; Limine wants bare 'rrggbb', palettes are ';'-joined.
  local bg fg brand help_col pal palb
  if [[ -n "$theme_conf" ]]; then
    eval "$(
      # shellcheck disable=SC1090
      . "$theme_conf"
      _cat() { local o="" x; for x in "$@"; do o="${o:+$o;}${x#\#}"; done; printf %s "$o"; }
      # Single-quote the RHS: palettes contain ';' which eval would treat as separators.
      echo "bg='${W_BG#\#}'"
      echo "fg='${W_TERM_FG#\#}'"
      echo "brand='${W_PRIMARY#\#}'"
      echo "help_col='${W_ON_SURFACE_VARIANT#\#}'"
      echo "pal='$(_cat "$W_TERM_ANSI_BLACK" "$W_TERM_ANSI_RED" "$W_TERM_ANSI_GREEN" \
                        "$W_TERM_ANSI_YELLOW" "$W_TERM_ANSI_BLUE" "$W_TERM_ANSI_MAGENTA" \
                        "$W_TERM_ANSI_CYAN" "$W_TERM_ANSI_WHITE")'"
      echo "palb='$(_cat "$W_TERM_ANSI_BRIGHT_BLACK" "$W_TERM_ANSI_BRIGHT_RED" \
                         "$W_TERM_ANSI_BRIGHT_GREEN" "$W_TERM_ANSI_BRIGHT_YELLOW" \
                         "$W_TERM_ANSI_BRIGHT_BLUE" "$W_TERM_ANSI_BRIGHT_MAGENTA" \
                         "$W_TERM_ANSI_BRIGHT_CYAN" "$W_TERM_ANSI_BRIGHT_WHITE")'"
    )"
  fi
  # Fallback to plain black if theme.conf was unreadable — first boot must stay bootable.
  : "${bg:=000000}" "${fg:=ffffff}" "${brand:=c46bd6}" "${help_col:=8a7a90}"

  cat > "$file" <<EOF
# Managed by W. First-boot seed — limine-update regenerates entries post-boot,
# w-style ('limine' axis) re-renders the theme header per active theme.
timeout: 1.5
quiet: yes
default_entry: 1

backdrop: $bg
term_background: $bg
term_foreground: $fg${pal:+
term_palette: $pal}${palb:+
term_palette_bright: $palb}
interface_branding: W Linux
interface_branding_colour: $brand
interface_help_colour: $help_col
interface_help_hidden: yes

/W Linux
    protocol: linux
    path: boot():/vmlinuz-linux-zen
    cmdline: $cmdline
    module_path: boot():/intel-ucode.img
    module_path: boot():/amd-ucode.img
    module_path: boot():/initramfs-linux-zen.img
EOF
}

# ── Stage the ESP for the first boot (before AUR tooling / SB enforcement) ────
limine_bootstrap_esp() {
  local esp="$1" mnt="$2"
  ui_info "Bootstrapping ESP (Limine binary + staged kernel)..."
  mkdir -p "$esp/EFI/BOOT" "$esp/EFI/limine"

  # Limine EFI binary from the official package share dir → standard + removable paths.
  local share="${mnt}/usr/share/limine"
  cp "$share/BOOTX64.EFI" "$esp/EFI/limine/limine_x64.efi"
  cp "$share/BOOTX64.EFI" "$esp/EFI/BOOT/BOOTX64.EFI"

  # Stage kernel + initramfs + microcode from the (encrypted) /boot onto the ESP.
  local boot="${mnt}/boot"
  local f
  for f in vmlinuz-linux-zen initramfs-linux-zen.img intel-ucode.img amd-ucode.img; do
    [[ -f "$boot/$f" ]] && cp "$boot/$f" "$esp/$f"
  done

  local cmdline; cmdline="$(cat "${mnt}/etc/kernel/cmdline")"
  limine_write_conf "$esp/limine.conf" "$cmdline" "$mnt"

  # Register a firmware boot entry (best-effort; the removable fallback covers wiped NVRAM).
  if [[ -n "$mnt" ]]; then
    chroot_run efibootmgr --create --disk "$CONF_DISK" --part 1 \
      --loader '\EFI\limine\limine_x64.efi' --label 'W (Limine)' &>/dev/null || true
  fi
}

# ── mod_limine — install/deploy Limine (install + live contexts) ─────────────
mod_limine() {
  local mnt="${MNT:-}"
  local esp="${mnt}/boot/efi"

  # Config-hash enrollment (ENABLE_ENROLL_LIMINE_CONFIG) is never turned on at install.
  # If it were, Limine would immediately enforce the BLAKE2B of limine.conf and HALT
  # before its UI on any change that isn't perfectly re-enrolled — while the firmware is
  # still in Setup Mode and Secure Boot enforces nothing. That premature enforcement
  # bricked the first encrypted boot test. Secure Boot is a post-install step by nature
  # (it needs firmware in Setup Mode and a manual UEFI toggle, neither reachable from an
  # installer), so `w-secureboot setup`/`enable` — Hub → Security — flips this to yes once
  # the user genuinely activates it. Re-applying on a live system that already ran setup
  # must preserve that yes instead of resetting the machine to unsigned.
  local enroll="no"
  if [[ -z "$mnt" && -f /etc/default/limine ]] \
     && grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=yes' /etc/default/limine; then
    enroll="yes"
  fi

  ui_info "Installing Limine bootloader..."
  # Official packages (limine + Secure Boot + TPM2 tooling). AUR hooks are live-only.
  w_pac -S --noconfirm --needed limine sbctl tpm2-tools
  if [[ -z "$mnt" ]]; then
    # Live: pull the AUR automation (kernel-entry hooks + snapper bridge). This is
    # NOT best-effort automation on top of a working system — without it the ESP is
    # never restaged again (see the CRITICAL below), so both the install path and
    # the fallback build path have to be loud when they come up empty.
    if ! command -v limine-update &>/dev/null; then
      # Fast path: install the prebuilt native-image packages baked into w-repo by
      # build-iso.sh. limine-{mkinitcpio-hook,snapper-sync} otherwise each trigger a
      # GraalVM native-image compile (the slowest build in the whole install) plus a
      # GraalVM JDK download. `pacman -U` resolves their official deps (limine/snapper/
      # btrfs-progs/libnotify/mkinitcpio/efibootmgr). Absent on the dev-VM apply path
      # (no ISO → no w-repo) → fall through to the live yay build below.
      local w_repo="/var/lib/w/w-repo"
      local hook_pkg snap_pkg
      hook_pkg="$(ls "$w_repo"/limine-mkinitcpio-hook-*.pkg.tar.* 2>/dev/null | head -1 || true)"
      snap_pkg="$(ls "$w_repo"/limine-snapper-sync-*.pkg.tar.* 2>/dev/null | head -1 || true)"
      if [[ -n "$hook_pkg" && -n "$snap_pkg" ]]; then
        ui_info "Installing Limine AUR automation (prebuilt from w-repo)..."
        pacman -U --noconfirm --needed "$hook_pkg" "$snap_pkg" || true
      fi
    fi
    if ! command -v limine-update &>/dev/null; then
      # Slow path: build the pair from the AUR ourselves (w_aur_build, lib/aurbuild.sh)
      # rather than through yay. Same seam the ISO prebuild uses, so an upstream build
      # break — like the gradle 9.7.0 one documented there — is fixed in one place and
      # its failure is visible here instead of being swallowed by yay's exit status.
      local staged; staged="$(mktemp -d -p /var/tmp)"
      w_aur_build "$staged" limine-mkinitcpio-hook limine-snapper-sync || true
      # Install whatever came out, even on a partial failure: the two packages are
      # independent, and the hook (the boot path) must not be held hostage to
      # snapper-sync (a feature) failing to build. The two checks further down
      # report on each of them separately for exactly that reason.
      local -a built=()
      mapfile -t built < <(ls "$staged"/*.pkg.tar.* 2>/dev/null)
      if (( ${#built[@]} )); then
        pacman -U --noconfirm --needed "${built[@]}" || true
      fi
      rm -rf "$staged"
    fi
    # Snapshot→boot bridge (Limine analog of grub-btrfsd): watches Snapper and syncs
    # bootable snapshot entries into limine.conf. Enable but do NOT start now — this
    # module runs before fix_snapper (last), so the root Snapper config doesn't exist
    # yet; a running sync would spam "No Snapper config" and try to auto-create a
    # rogue config+snapshot. It starts cleanly on the post-install reboot, by which
    # point the config + initial snapshot are in place.
    if systemctl list-unit-files limine-snapper-sync.service &>/dev/null; then
      systemctl enable limine-snapper-sync.service 2>/dev/null || true
    else
      # Snapshot entries are a feature, not the boot path — a WARN, not a CRITICAL.
      # e2e asserts on the unit directly so losing it still fails the gate.
      echo "WARN: limine-snapper-sync is not installed — bootable snapshot entries will not be generated."
    fi
    # The boot path itself. Without limine-mkinitcpio the ESP is never restaged:
    # mkinitcpio's own alpm hooks write /boot, which lives inside the LUKS root that
    # Limine cannot read, so a kernel update silently stops reaching the loader. This
    # exact failure shipped once as a successful install (upstream gradle break,
    # 2026-08), which is why it is tagged rather than warned: e2e greps apply.log.
    if ! command -v limine-mkinitcpio &>/dev/null; then
      crit "limine-mkinitcpio-hook is not installed — kernel updates will NOT reach the ESP and the machine will keep booting the install-time initramfs. Re-run 'apply.sh --limine' once the build works. This must not happen where network is available (e.g. e2e)."
    fi
  fi

  limine_write_default "${mnt}/etc/default/limine" "$enroll"

  # Live system with AUR tooling present → let limine-update own the config/staging.
  if [[ -z "$mnt" ]] && command -v limine-update &>/dev/null; then
    # Install the default_entry post.d hook BEFORE the first limine-update so every
    # regeneration (this one, retire's, and each async limine-snapper-sync run) leaves
    # default_entry pinned at the bootable leaf instead of the unbootable /+<OS> branch.
    limine_write_default_entry_hook "/etc/boot/hooks/post.d/50-w-default-entry"
    ui_info "Regenerating Limine entries (limine-update)..."
    limine-update || true
    limine_restage_esp "$esp"
    limine_retire_seed "$esp"
  else
    limine_bootstrap_esp "$esp" "$mnt"
  fi
}

# ── First-run ESP staging under the kernel-install/BLS model ─────────────────────
# limine-mkinitcpio-hook builds the initramfs straight into the ESP, but only on a
# KERNEL transaction. A machine that gets the hook late — a repair run, or the
# dev-VM path where the first apply could not build it — therefore has no managed
# <machine-id>/ tree at all, and its ESP still holds whatever limine_bootstrap_esp
# staged at install time: a stale, unthemed initramfs that no later kernel update
# would replace. limine-update alone does not fix that (it writes entries, it does
# not rebuild). Force exactly one kernel-install rebuild, through w-mkinitcpio so
# the bootloader fork stays in one place. Idempotent: a no-op once the tree exists.
limine_restage_esp() {
  local esp="$1"
  local mid=""
  # `if`, not `[[ … ]] && …`: the && list returns 1 when the file is unreadable and
  # `set -e` would take apply.sh down with it.
  if [[ -r /etc/machine-id ]]; then mid="$(cat /etc/machine-id)"; fi
  [[ -n "$mid" && ! -d "$esp/$mid" ]] || return 0
  command -v w-mkinitcpio &>/dev/null || return 0

  ui_info "Staging kernel+initramfs into the ESP (first run under limine-mkinitcpio)..."
  w-mkinitcpio || crit "ESP staging failed — the loader still has the install-time kernel/initramfs."
}

# ── Retire the hand-written first-boot seed once limine-update owns the config ────
# The install seed (limine_write_conf) writes a manual `/W Linux` entry pinned by
# `default_entry: 1` that boots STALE, staged-once ESP-root files (…/initramfs-linux-
# zen.img) — never re-staged, so every boot runs an unthemed install-time initramfs
# while limine-update's real, themed entry (…/<machine-id>/…) sits unused as entry 2.
# Once limine-update has generated its managed entry, remove the seed entry + its
# orphan ESP-root files. Idempotent: a no-op after the first run (seed already gone).
# Runs only in the live context. default_entry is owned by the 50-w-default-entry
# post.d hook (installed in mod_limine) — the trailing limine-update below fires it.
limine_retire_seed() {
  local esp="$1"
  local conf="$esp/limine.conf"
  [[ -f "$conf" ]] || return 0
  grep -q '^/W Linux$' "$conf" || return 0   # already retired

  # Never trade a working seed for nothing: the seed is the ONLY bootable entry
  # until limine-update's managed tree actually exists on the ESP. It normally does
  # by now (limine_restage_esp ran first), but if that rebuild failed, dropping the
  # seed here would leave a machine with no bootable entry at all.
  local mid=""
  # `if`, not `[[ … ]] && …`: the && list returns 1 when the file is unreadable and
  # `set -e` would take apply.sh down with it.
  if [[ -r /etc/machine-id ]]; then mid="$(cat /etc/machine-id)"; fi
  if [[ -z "$mid" || ! -d "$esp/$mid" ]]; then
    crit "Limine has no managed kernel tree on the ESP — keeping the first-boot seed entry as the only bootable path."
    return 0
  fi

  ui_info "Retiring first-boot Limine seed entry (limine-update owns the config now)..."

  # Drop the seed entry block: from the `/W Linux` line up to (not including) the next
  # top-level entry (`/…`) — indented child lines belong to managed tree entries.
  sed -i '\#^/W Linux$#,\#^/[^/ ]#{\#^/W Linux$#d; \#^/[^/ ]#!d}' "$conf"

  # Remove the orphaned, never-updated ESP-root staged files (managed staging lives
  # under $esp/<machine-id>/; microcode is baked into the initramfs by mkinitcpio).
  local f
  for f in vmlinuz-linux-zen initramfs-linux-zen.img intel-ucode.img amd-ucode.img; do
    rm -f "$esp/$f"
  done

  # We edited limine.conf → its BLAKE2B changes. Re-run limine-update so the config
  # hash is re-enrolled (harmless without Secure Boot; required under it).
  limine-update || true
}
