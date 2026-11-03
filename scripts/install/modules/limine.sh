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

  local uuid; uuid="$(blkid -s UUID -o value "$CONF_ROOT_PART")"
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
# Interactive installs under an enforcing Secure Boot enroll too (desktops only — a
# laptop keeps the passphrase: a stolen one would boot to its login screen, see
# package-limine.md): there the order "Secure Boot, then TPM2" already holds.
# Bound to NO PCR here, and resealed to PCR 7 (w-crypt's default policy) by
# w-firstboot on the installed system's own first boot: PCR 7 of this live session is
# not the installed system's — the medium boots through shim, which measures its own
# state (SBAT level, MOK) into PCR 7 even with Secure Boot off, while the installed
# Limine starts without it. Sealed to this boot, every later boot would ask for the
# passphrase. The marker tells w-firstboot the unbound seal is the installer's.
# No TPM → warn and continue: the install itself still succeeds,
# each boot then needs a human for the passphrase (TPM-less fleet hardware). A TPM
# that is present but fails to enroll is fatal — better a loud die now than a silent
# hour-long timeout on an invisible unlock prompt later.
limine_enroll_tpm() {
  if [[ ! -e /dev/tpmrm0 ]]; then
    echo "WARN: no TPM 2.0 device — skipping auto-unlock enrollment; every boot will ask for the LUKS passphrase."
    return 0
  fi
  ui_info "Enrolling TPM2 auto-unlock (sealed to PCR 7 on the first boot)..."
  # systemd-cryptenroll authorizes the new slot with the existing passphrase — hand
  # it over as a root-only key file (never argv). Runs in the chroot: the target has
  # the tpm2 stack via mod_limine's tpm2-tools, and arch-chroot bind-mounts /dev.
  local keyfile="$MNT/root/.w-luks-enroll"
  { set +x; } 2>/dev/null   # keep the passphrase out of the trace log
  (umask 077; printf '%s' "$CONF_LUKS_PASS" > "$keyfile")
  [[ -n "${W_TRACE_FD:-}" ]] && set -x || true
  local rc=0
  chroot_run systemd-cryptenroll "$CONF_ROOT_PART" --unlock-key-file=/root/.w-luks-enroll \
    --tpm2-device=auto --tpm2-pcrs= || rc=$?
  rm -f "$keyfile"
  (( rc == 0 )) || die "TPM2 enrollment failed (rc=$rc) — headless boots would hang at the passphrase prompt."
  mkdir -p "$MNT/var/lib/w" && : > "$MNT/var/lib/w/tpm-reseal-pending"
}

# ── Secure Boot at install (install context, firmware enforcing) ───────────────
# The medium came up through shim, so the firmware trusts Microsoft's 3rd-party CA:
# `w-secureboot enable --mode shim` phase 1, run in the chroot — machine-local sbctl
# keys, Limine-for-shim (grubx64.efi) with the seed limine.conf's hash, NVRAM "W",
# EFI/W/W-MOK.cer. Interactive: the MOK enrollment is queued with a one-time code
# chosen here (MOK_CODE, shown by show_done — kept out of the trace log), and the
# medium's own hash is queued for deletion in the same MokManager visit. Unattended:
# nothing is queued — shim, refusing the unknown Limine, opens MokManager by itself,
# and "Enroll key from disk" needs no code. Firmware that refuses the request (no
# MokNew after phase 1 — see w-secureboot mok_queue) ends the same way: MOK_FROM_DISK,
# and show_done gives those steps instead of the code. w-firstboot runs phase 2.
MOK_CODE=""
MOK_FROM_DISK=""
limine_secureboot() {
  ui_info "Secure Boot is enforcing — setting up shim and this machine's key..."
  # shim-signed is AUR: prebuilt in the medium's w-repo (build-iso.sh).
  local pkg; pkg="$(ls /root/w-repo/shim-signed-*.pkg.tar.* 2>/dev/null | head -1 || true)"
  [[ -n "$pkg" ]] || die "shim-signed is missing from the medium's w-repo — cannot boot under Secure Boot."
  cp "$pkg" "$MNT/var/tmp/"
  chroot_run pacman -U --noconfirm --needed "/var/tmp/${pkg##*/}"
  rm -f "$MNT/var/tmp/${pkg##*/}"

  local -a env=(W_SB_NONINTERACTIVE=1)
  local codefile="$MNT/root/.w-mok-code" hashfile=/tmp/.w-mok-hash
  if [[ -z "$W_UNATTENDED" ]]; then
    { set +x; } 2>/dev/null   # keep the code out of the trace log
    MOK_CODE="$(od -An -N8 -tu1 /dev/urandom | awk '{for (i = 1; i <= NF; i++) printf "%d", $i % 10}')"
    (umask 077; printf '%s' "$MOK_CODE" > "$codefile"; mokutil --generate-hash="$MOK_CODE" > "$hashfile")
    [[ -n "${W_TRACE_FD:-}" ]] && set -x || true
    env=(W_MOK_CODE_FILE=/root/.w-mok-code)
  fi
  local rc=0
  chroot_run env "${env[@]}" w-secureboot enable --mode shim || rc=$?
  rm -f "$codefile"
  (( rc == 0 )) || die "Secure Boot setup (w-secureboot enable, phase 1) failed (rc=$rc)."
  if [[ -z "$W_UNATTENDED" ]]; then
    if [[ -e "${W_EFIVARS:-/sys/firmware/efi/efivars}/MokNew-605dab50-e046-4300-abb6-3dd810dd8b23" ]]; then
      limine_mok_drop_medium "$hashfile"
    else
      # Nothing queued — the same refusal would meet --delete-hash; the medium's
      # hash stays in MokList (harmless).
      MOK_CODE=""; MOK_FROM_DISK=1
    fi
  fi
  rm -f "$hashfile"
}

# The medium's own hash (/w/mok-sha256, written by iso-secureboot.sh) came into
# MokList to boot it; it goes out in the visit that adds W's key, so MokList does not
# grow by an entry per image. Best-effort: a medium that cannot be read any more
# (copytoram and gone, Ventoy) or a hash that is not enrolled is simply left alone.
limine_mok_drop_medium() {
  local hashfile="$1" tag dev dir h=""
  if [[ -r /run/archiso/bootmnt/w/mok-sha256 ]]; then
    h="$(awk '{print $1; exit}' /run/archiso/bootmnt/w/mok-sha256)"
  else
    tag="$(sed -n -E 's/.*archisosearchuuid=([^ ]+).*/UUID=\1/p' /proc/cmdline)"
    dev="$(blkid -o device -t "$tag" 2>/dev/null | head -1 || true)"
    dir="$(mktemp -d)"
    if [[ -n "$tag" && -n "$dev" ]] && mount -o ro "$dev" "$dir" 2>/dev/null; then
      h="$(awk '{print $1; exit}' "$dir/w/mok-sha256" 2>/dev/null || true)"
      umount "$dir"
    fi
    rmdir "$dir"
  fi
  [[ "$h" =~ ^[0-9a-f]{64}$ ]] || { echo "MOK: the medium's hash is not readable — left in MokList."; return 0; }
  mokutil --list-enrolled 2>/dev/null | tr -d ' :' | grep -qix "$h" \
    || { echo "MOK: the medium's hash $h is not in MokList."; return 0; }
  mokutil --delete-hash "$h" --hash-file "$hashfile" \
    || echo "WARN: could not queue the medium's hash for deletion — it stays in MokList."
}

# ── /etc/default/limine — consumed by the AUR limine-update post-boot ─────────
# $1 = target file path, $2 = enroll-config (yes|no) for Secure Boot, $3 = Secure Boot
# mode (own|shim|empty — /var/lib/w/secureboot-mode, written by w-secureboot).
limine_write_default() {
  local file="$1" enroll="$2" sbmode="${3:-}"
  # Without Secure Boot the entry-tool's own fallback (a plain copy of Limine at
  # EFI/BOOT/BOOTX64.EFI) is right. With it, that copy is unsigned and the firmware
  # rejects it — post.d/95-w-secureboot (w-secureboot-stage) owns the fallback path
  # instead, and the entry-tool must stop overwriting it.
  local fallback="yes" order=""
  [[ -n "$sbmode" ]] && fallback="no"
  # shim mode: limine-install (pacman hook on every limine upgrade) re-registers a
  # missing "Limine" NVRAM entry, first by default. Under the factory keys the
  # firmware rejects that binary — harmless, but keep it behind W's shim entry.
  [[ "$sbmode" == shim ]] && order=$'\n\n# Secure Boot via shim: a re-registered direct Limine entry is rejected by the\n# firmware (factory keys), so it goes last, behind W\'s shim entry.\nUEFI_BOOT_ORDER=last'
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# Managed by W (mod_limine). Overrides /etc/limine-entry-tool.conf.
# Kernel cmdline is read from /etc/kernel/cmdline.
ESP_PATH="/boot/efi"

# Plain kernel+initramfs (NOT UKI): smaller ESP, and Limine-native per-snapshot cmdline
# for limine-snapper-sync. Toggle ENABLE_UKI=yes later if UKIs are ever preferred.
ENABLE_UKI=no

# Removable fallback path (EFI/BOOT/BOOTX64.EFI): limine-update keeps a copy of Limine
# there while Secure Boot is off; under Secure Boot W's post.d/95-w-secureboot stages
# it instead (signed, config hash enrolled — see /usr/lib/w/w-secureboot-stage).
ENABLE_LIMINE_FALLBACK=$fallback${order}

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
# repoints default_entry to `<branch>/<kernel leaf>` (Limine entry-path form,
# CONFIG.md). Prefix 50- sorts before 90-limine-enroll-config so the enrolled Secure
# Boot hash is computed over the already-corrected config. WHICH leaf is the kernel
# selection: it reads /etc/w/kernel.conf (written by `w-kernel set`) and falls back to
# the first leaf — see the hook body. It also mirrors the leaf it pins into
# /var/lib/w/kernel.default, because limine.conf itself sits on a dmask=0077 ESP and
# the Hub reads the active kernel as the desktop user. $1 = target hook path.
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

# First top-level branch name (/+Name) and the depth-2 kernel leaf (//name) to boot.
# Excludes the //Snapshots sub-branch and deeper snapshot entries (///, ////).
# limine-entry-tool names each leaf after the kernel's pkgbase (//linux-zen), which is
# exactly what `w-kernel set` records in /etc/w/kernel.conf — so the choice survives
# every regeneration (limine-update, limine-snapper-sync) instead of being decided by
# whichever leaf happens to come first. The first leaf stays the fallback: it is the
# only answer on a machine that never made a choice, and with one kernel installed the
# two agree anyway.
branch="$(sed -n 's#^/+##p' "$conf" | head -1)"
leaves="$(sed -n 's#^[[:space:]]*//\([^/].*\)#\1#p' "$conf" | sed 's#[[:space:]]*$##' | grep -vx 'Snapshots')"
want=""
[[ -r /etc/w/kernel.conf ]] && want="$(sed -n 's/^DEFAULT_KERNEL="\?\([^"]*\)"\?.*/\1/p' /etc/w/kernel.conf | head -1)"
kernel=""
[[ -n "$want" ]] && kernel="$(grep -Fx -- "$want" <<<"$leaves" | head -1)"
[[ -n "$kernel" ]] || kernel="$(head -1 <<<"$leaves")"
[[ -n "$branch" && -n "$kernel" ]] || exit 0
target="${branch}/${kernel}"

# Mirror the leaf we are about to pin where an unprivileged reader can see it: the
# ESP is mounted dmask=0077, so the Hub (which asks `w-kernel list` as the desktop
# user) cannot read limine.conf and would render the active kernel as "—". Written
# from $kernel itself, so the mirror cannot disagree with the pin. Best-effort and
# deliberately before the sed: a failure here must never change this hook's exit
# code — an unpinned default_entry is a boot hang, a stale mirror is a wrong label.
# The `2>/dev/null` sits BEFORE the `>`, not after: bash applies redirections left to
# right, so with the usual order the failure to OPEN the file is still reported on the
# inherited stderr. That is not theoretical — a rollback registers the outgoing root
# as a snapshot and turns it read-only under the running system, so this hook (which
# the same rollback re-runs) printed a red "Read-only file system" at the user right
# after "Restore complete", for a mirror whose failure is by design harmless.
if [[ -d /var/lib/w ]]; then
  printf '%s\n' "$kernel" 2>/dev/null > /var/lib/w/kernel.default || true
  chmod 644 /var/lib/w/kernel.default 2>/dev/null || true
fi

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

# ── post.d hook — Windows next to W: its entry + a visible menu ─────────────────
# Same channel as 50-w-default-entry: runs after every limine.conf write (limine-
# update, limine-snapper-sync), and 60- still sorts before 90-limine-enroll-config, so
# the Secure Boot hash covers the result. limine-entry-tool's FIND_BOOTLOADERS only
# looks inside W's own ESP and its --scan is interactive, hence our own entry.
# Per Windows found by w-boot-otheros: a top-level entry at the end of the menu that
# reboots into the firmware's Windows entry (protocol efi_boot_entry — BootNext, not a
# chainload: BitLocker would ask for its recovery key), and quiet:no + timeout:5 so the
# menu is seen. The entries carry a marker comment; a Windows that went away takes its
# entry with it and puts back the install-time quiet:yes + timeout:1.5. No Windows and
# no marked entry → the file is not written at all. $1 = target hook path.
limine_write_other_os_hook() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
#!/usr/bin/env bash
# Managed by W (mod_limine). Windows entries (BootNext) + a visible menu when the
# firmware can boot a Windows; see /usr/lib/w/w-boot-otheros.
set -u
esp="/boot/efi"
[[ -f /etc/default/limine ]] && esp="$(awk -F'"' '/^ESP_PATH=/{print $2}' /etc/default/limine)"
conf="${esp:-/boot/efi}/limine.conf"
[[ -f "$conf" && -x /usr/lib/w/w-boot-otheros ]] || exit 0

mark="comment: Restarts into Windows through the firmware (W)"
found="$(/usr/lib/w/w-boot-otheros)"
[[ -n "$found" ]] || grep -qxF "    $mark" "$conf" || exit 0

# Everything but the marked top-level entries, trailing blank lines dropped.
new="$(awk -v m="    $mark" '
  function flush() { if (!(blk && marked)) printf "%s", buf; buf = ""; marked = 0 }
  /^\/[^\/]/ { flush(); blk = 1 }
  { buf = buf $0 "\n"; if ($0 == m) marked = 1 }
  END { flush() }' "$conf")"$'\n'

set_key() {  # $1 key, $2 value — replace, or insert before the first non-comment line
  if grep -q "^$1:" <<< "$new"; then
    new="$(sed "s#^$1:.*#$1: $2#" <<< "$new")"$'\n'
  else
    new="$(sed "0,/^[^#]/s#^\([^#]\)#$1: $2\n\1#" <<< "$new")"$'\n'
  fi
}
if [[ -n "$found" ]]; then
  set_key timeout 5
  set_key quiet no
  while IFS=$'\t' read -r _ label; do
    new+=$'\n'"/$label"$'\n'"    $mark"$'\n'"    protocol: efi_boot_entry"$'\n'"    entry: $label"$'\n'
  done <<< "$found"
else
  set_key timeout 1.5
  set_key quiet yes
fi
[[ "$new" == "$(cat "$conf")"$'\n' ]] || printf '%s' "$new" > "$conf"
EOF
  chmod 755 "$file"
}

# ── post.d hook — Secure Boot loaders (signed fallback / shim chain) ───────────
# Last in the chain on purpose: 95- runs after 90-limine-enroll-config has enrolled
# the final limine.conf hash and signed limine_x64.efi, so what it copies or rebuilds
# matches the config Limine reads. The work is in w-secureboot-stage (also run by the
# pacman hook and by w-secureboot); this only bridges the entry-tool's hook channel to
# it, and without a Secure Boot mode the helper exits at once. $1 = target hook path.
limine_write_secureboot_hook() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
#!/usr/bin/env bash
# Managed by W (mod_limine). Secure Boot loaders beside limine-entry-tool's own;
# see /usr/lib/w/w-secureboot-stage.
[[ -x /usr/lib/w/w-secureboot-stage ]] || exit 0
/usr/lib/w/w-secureboot-stage; rc=$?
# A failed enroll (the entry-tool's 90-, or the stage above) leaves a hash Limine
# halts on: retry, and say so loudly if that fails too.
command -v w-secureboot >/dev/null && { w-secureboot reenroll --if-stale || rc=1; }
exit $rc
EOF
  chmod 755 "$file"
}

# ── Secure Boot mode of a machine enabled before modes existed ─────────────────
# `w-secureboot enable` with own keys predates /var/lib/w/secureboot-mode: such a
# machine has sbctl keys and config-hash enrollment on, but no mode file — so its
# removable fallback is still the entry-tool's unsigned copy, which the firmware
# rejects (a lost NVRAM entry = no boot). Name the mode once; the limine-update that
# follows in mod_limine stages the signed fallback through 95-w-secureboot. shim mode
# never existed without the file, so own is the only possible answer here.
# Enrollment alone is no proof: the installer once turned it on with no keys at all,
# Secure Boot off. own without sbctl's keys cannot be (its PK IS those keys) — such a
# machine gets no mode, and a mode file this function wrote for it is dropped.
limine_sbctl_keys() { [[ "$(sbctl setup --print-state --json 2>/dev/null)" == *'"installed": true'* ]]; }
limine_migrate_secureboot_mode() {
  local f="/var/lib/w/secureboot-mode"
  if [[ -f "$f" ]]; then
    if [[ "$(cat "$f")" == own ]] && ! limine_sbctl_keys; then
      ui_info "Secure Boot mode 'own' without sbctl keys — not Secure Boot, dropping the mode..."
      rm -f "$f"
    fi
    return 0
  fi
  grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=yes' /etc/default/limine 2>/dev/null || return 0
  limine_sbctl_keys || return 0
  ui_info "Secure Boot (own keys) is on — staging a signed fallback loader..."
  mkdir -p "$(dirname "$f")"
  echo own > "$f"
}

# `#<BLAKE2B>` of a staged file for its Limine path (nothing when it is absent). Under
# Secure Boot the signed loader carries the config's hash and the config the files' —
# the chain limine-entry-tool writes later too (ENABLE_VERIFICATION).
limine_pin() { [[ -f "$1" ]] && printf '#%s' "$(b2sum "$1" | cut -d' ' -f1)"; return 0; }

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
  local d; d="$(dirname "$file")"

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
    path: boot():/vmlinuz-linux-zen$(limine_pin "$d/vmlinuz-linux-zen")
    cmdline: $cmdline
    module_path: boot():/intel-ucode.img$(limine_pin "$d/intel-ucode.img")
    module_path: boot():/amd-ucode.img$(limine_pin "$d/amd-ucode.img")
    module_path: boot():/initramfs-linux-zen.img$(limine_pin "$d/initramfs-linux-zen.img")
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
  # Disk + partition number come from the real ESP node, not a layout constant.
  local esp_disk esp_num
  if [[ -n "$mnt" ]] && read -r esp_disk esp_num < <(part_location "$CONF_ESP_PART"); then
    chroot_run efibootmgr --create --disk "$esp_disk" --part "$esp_num" \
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
  # mokutil + binutils (objcopy/objdump) serve Secure Boot through shim (w-secureboot,
  # w-secureboot-stage); shim-signed itself is AUR — live-only, with the hook pair below.
  w_pac -S --noconfirm --needed limine sbctl tpm2-tools mokutil binutils
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
    # Microsoft-signed shim (Fedora's, repackaged by AUR shim-signed) for Secure Boot
    # on the firmware's factory keys — `w-secureboot enable` without Setup Mode. Not
    # the boot path until that mode is on (w-secureboot refuses it without shim), so a
    # missing package is a WARN. Prebuilt in w-repo by build-iso.sh; otherwise built
    # here through the same seam (it only unpacks an RPM — seconds).
    if ! pacman -Q shim-signed &>/dev/null; then
      local shim_pkg
      shim_pkg="$(ls /var/lib/w/w-repo/shim-signed-*.pkg.tar.* 2>/dev/null | head -1 || true)"
      if [[ -z "$shim_pkg" ]]; then
        local shim_staged; shim_staged="$(mktemp -d -p /var/tmp)"
        w_aur_build "$shim_staged" shim-signed || true
        shim_pkg="$(ls "$shim_staged"/shim-signed-*.pkg.tar.* 2>/dev/null | head -1 || true)"
      fi
      [[ -n "$shim_pkg" ]] && { pacman -U --noconfirm --needed "$shim_pkg" || true; }
      [[ -n "${shim_staged:-}" ]] && rm -rf "$shim_staged"
      pacman -Q shim-signed &>/dev/null \
        || echo "WARN: shim-signed is not installed — Secure Boot on the firmware's factory keys (shim) is unavailable."
    fi
    limine_migrate_secureboot_mode
    # Config-hash guard at shutdown (rootfs ships the unit; a no-op without a mode).
    # Live only: Secure Boot is turned on after firstboot, which always runs this.
    systemctl enable --now w-secureboot-guard.service 2>/dev/null \
      || echo "WARN: w-secureboot-guard.service could not be enabled — an edit of limine.conf past limine-entry-tool would halt the next Secure Boot boot."
    # Snapshot→boot bridge (Limine analog of grub-btrfsd): watches Snapper and syncs
    # bootable snapshot entries into limine.conf. Enable but do NOT start now — this
    # module runs before fix_snapper (last), so the root Snapper config doesn't exist
    # yet; a running sync would spam "No Snapper config" and try to auto-create a
    # rogue config+snapshot. It starts cleanly on the post-install reboot, by which
    # point the config + initial snapshot are in place.
    if systemctl list-unit-files limine-snapper-sync.service &>/dev/null; then
      systemctl enable limine-snapper-sync.service 2>/dev/null || true
      # The ESP is self-limiting by design: MAX_SNAPSHOT_ENTRIES defaults to "auto",
      # which drops the OLDEST snapshot boot entries once usage passes
      # LIMIT_USAGE_PERCENT (85). That is the right behaviour — it degrades instead of
      # filling up, and it never touches the current kernels (a different hook stages
      # those) or the btrfs snapshots themselves. But it does it SILENTLY by default,
      # so a machine carrying several kernels would lose old snapshot menu entries with
      # no word about why. Turn the notification on: the eviction stays automatic, it
      # just stops being invisible. Idempotent, and only where the config exists.
      if [[ -f /etc/limine-snapper-sync.conf ]]; then
        if grep -q '^ENABLE_NOTIFICATION=' /etc/limine-snapper-sync.conf; then
          sed -i 's/^ENABLE_NOTIFICATION=.*/ENABLE_NOTIFICATION=yes/' /etc/limine-snapper-sync.conf
        else
          echo 'ENABLE_NOTIFICATION=yes' >> /etc/limine-snapper-sync.conf
        fi
      fi
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

  local sbmode=""
  [[ -z "$mnt" && -f /var/lib/w/secureboot-mode ]] && sbmode="$(cat /var/lib/w/secureboot-mode)"
  # Live enrollment without a Secure Boot mode is that keyless leftover: the hash then
  # guards nothing and halts the boot on any limine.conf edit past the entry-tool. Off,
  # as on a fresh install — pre.d/10-limine-reset-enroll strips it from the binary.
  [[ -z "$mnt" && -z "$sbmode" ]] && enroll="no"
  limine_write_default "${mnt}/etc/default/limine" "$enroll" "$sbmode"
  # Secure Boot loaders (95-w-secureboot → w-secureboot-stage): inert until
  # w-secureboot names a mode, installed everywhere so the hook chain is complete.
  install -Dm755 "$SRC/rootfs/usr/lib/w/w-secureboot-stage" "${mnt}/usr/lib/w/w-secureboot-stage"
  if [[ -n "$mnt" ]]; then
    # Ahead of firstboot's rootfs deploy: Secure Boot phase 1 runs in the chroot
    # (limine_secureboot), and w-firstboot reseals TPM2 / finishes phase 2 before
    # apply --all. apply's rootfs later lays the same files down again.
    local f
    for f in usr/bin/w-secureboot usr/bin/w-crypt; do install -Dm755 "$SRC/rootfs/$f" "$mnt/$f"; done
    for f in w-i18n-lib.sh w-conf-lib.sh w-sbat-lib.sh; do
      install -Dm644 "$SRC/rootfs/usr/lib/w/$f" "$mnt/usr/lib/w/$f"
    done
  fi
  limine_write_secureboot_hook "${mnt}/etc/boot/hooks/post.d/95-w-secureboot"
  # Windows next to W (60-w-other-os); the helper is in rootfs too, installed here so
  # the install-time seed — written before firstboot deploys rootfs — gets it as well.
  install -Dm755 "$SRC/rootfs/usr/lib/w/w-boot-otheros" "${mnt}/usr/lib/w/w-boot-otheros"
  limine_write_other_os_hook "${mnt}/etc/boot/hooks/post.d/60-w-other-os"

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
    # The seed is not written by limine-entry-tool, so its hooks do not run on it.
    # Best-effort: a missing Windows entry must not fail the install.
    if [[ -n "$mnt" ]]; then
      chroot_run /etc/boot/hooks/post.d/60-w-other-os || true
    else
      /etc/boot/hooks/post.d/60-w-other-os || true
    fi
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
