#!/usr/bin/env bash
# W Linux Installer — main orchestrator
# Usage: bash install.sh [--preset FILE]
# Run from Arch Linux live ISO with internet access.
#
# --preset FILE: unattended install (audit P2). FILE is an install.conf-format
# answers file (see lib/tui.sh answers_load / vm/e2e/preset-plain.sample.conf). The
# whole interactive phase is skipped — the disk is wiped WITHOUT confirmation —
# and every blocking dialog downstream (offline retry loops, the final reboot
# screen, firstboot's dialogs) is replaced by a non-interactive branch. Drives
# both the headless E2E test (vm/e2e.sh) and fleet deployment.

set -euo pipefail

# Suppress snap-pac for every pacman/pacstrap/chroot transaction during install. The
# root Snapper config doesn't exist yet (created live by apply.sh), so snap-pac's hook
# would just invoke snapper with no config and crash the scriptlet ("fatal library
# error, lookup self"). Inherited by pacstrap and arch-chroot. Not persisted → normal
# snap-pac resumes on the installed system.
export SNAP_PAC_SKIP=y

INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_LIB="$INSTALL_ROOT/install/lib"
INSTALL_MODULES="$INSTALL_ROOT/install/modules"
# Repo root — shared modules reference $SRC (same convention as apply.sh).
SRC="$(cd "$INSTALL_ROOT/.." && pwd)"

source "$INSTALL_LIB/utils.sh"
source "$INSTALL_LIB/pac.sh"
source "$INSTALL_LIB/ui.sh"
source "$INSTALL_LIB/tui.sh"
source "$INSTALL_LIB/progress.sh"
source "$INSTALL_LIB/disk.sh"
source "$INSTALL_LIB/system.sh"
source "$INSTALL_LIB/modules.sh"

# Install-phase modules come from the registry (scripts/install/modules.conf, the
# same file apply.sh reads for the post-boot phases) — so "which modules run in the
# installer" is a declared fact rather than the shape of this list. main() below
# still calls them by name: the sequence there interleaves with the disk/system
# steps, and check/modules.sh proves it matches the registry's order.
w_modules_load "$INSTALL_ROOT/install/modules.conf" \
  || { echo "install.sh: module registry unusable" >&2; exit 1; }
mapfile -t _mod_files < <(w_modules_files install)
[[ ${#_mod_files[@]} -gt 0 ]] || { echo "install.sh: no install-phase modules" >&2; exit 1; }
for _f in "${_mod_files[@]}"; do source "$INSTALL_MODULES/$_f"; done
unset _f _mod_files

# ── Config consumed by the work phases (mapped from ANSWERS after the wizard) ──
CONF_DISK=""
CONF_HOSTNAME=""
CONF_TZ="Europe/Moscow"
CONF_ROOT_PASS=""
CONF_USER=""
CONF_USER_PASS=""
CONF_KEYMAP="us"
CONF_LOCALE="en_US.UTF-8"
CONF_ENCRYPT=false
CONF_LUKS_PASS=""
CONF_MODE="stable"        # update channel: stable (w-system pkg) | edge (git)
CONF_EDGE_REPO=""         # edge: clone URL entered in the wizard
EDGE_SRC_DIR=""           # validated edge clone, reused by mod_firstboot

# The public W repository, pre-filled into the edge step so a beta install is one
# Enter. Users may replace it with their own fork — the field stays editable. Kept
# as ONE constant here because the same URL also appears in rootfs/etc/os-release
# and README.md; `scripts/publish.sh check` prints every occurrence so the three
# never drift apart.
W_PUBLIC_EDGE_REPO="https://github.com/tarkh/w"

# ── Unattended mode (--preset) ────────────────────────────────────────────────
PRESET_FILE=""
W_UNATTENDED=""           # non-empty → no interactive phase, no blocking dialogs
for _arg in "$@"; do
  case "$_arg" in
    --preset)   PRESET_PENDING=1 ;;
    *) if [[ -n "${PRESET_PENDING:-}" ]]; then PRESET_FILE="$_arg"; unset PRESET_PENDING
       else die "Unknown option: $_arg (usage: install.sh [--preset FILE])"; fi ;;
  esac
done
[[ -n "${PRESET_PENDING:-}" ]] && die "--preset needs a file argument."
[[ -n "$PRESET_FILE" ]] && W_UNATTENDED=1

# ── Update channel (Stable / Edge) options + edge-repo validator ──────────────
# Menu descriptions are single tokens (the wizard splits items on whitespace); the
# explanation lives in the step prompt. Edge validation clones the repo NOW so a bad
# URL fails the step here, not at firstboot. The validated clone is reused as-is.
# `stable` is implemented end to end in the code (CONF_MODE, mod_updatesys, w-sync's
# is_edge gate, preset_validate) but has no SERVER side yet: update-system.md phase 6
# — the signed w-system package on update.w.tarkh.com — is deferred, so choosing it
# would leave a machine that never receives an update. It is HIDDEN from the menu,
# not removed. To restore: put `stable $(t s_mode_stable)` back at the front of the
# line below and flip the two ANSWERS[mode] seeds in main().
#
# Nothing exercises `stable` any more: both E2E presets run edge, because a channel
# no install can produce is not worth a gate phase. Its code is therefore expected
# to have rotted by the time phase 6 arrives — re-test it then rather than trusting
# it. What the gate covers instead is the axis that IS live: edge against two
# different remotes, which is what edge_repo below is for.
mode_list() { echo "edge $(t s_mode_edge)"; }

# Laptop vs desktop — drives the w-power preset (idle/lid/profile-auto/charge). The
# detected chassis is emitted first so dialog highlights it as the default; the user
# can still switch. Mirrors w-power's own detect_mode (chassis → DMI → battery).
computer_type_list() {
  local c t det=desktop
  c="$(hostnamectl chassis 2>/dev/null || true)"
  case "$c" in laptop|notebook|portable|convertible|tablet|handset) det=laptop ;; esac
  if [[ "$det" == desktop ]]; then
    t="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || true)"
    case "$t" in 8|9|10|11|14|30|31|32) det=laptop ;; esac
  fi
  [[ "$det" == desktop ]] && compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1 && det=laptop
  if [[ "$det" == laptop ]]; then
    echo "laptop $(t s_computer_laptop) desktop $(t s_computer_desktop)"
  else
    echo "desktop $(t s_computer_desktop) laptop $(t s_computer_laptop)"
  fi
}

V_EDGE_MSG=""             # custom error surfaced by render_step for v_edge_repo
v_edge_repo() {
  local url="$1"
  [[ -n "$url" ]] || { V_EDGE_MSG="$(t err_edge_empty)"; return 1; }
  command -v git &>/dev/null || pacman -Sy --noconfirm git &>/dev/null || {
    V_EDGE_MSG="$(t err_edge_git)"; return 1; }
  local tmp="/tmp/w-edge-src" out
  rm -rf "$tmp"
  if [[ -z "$W_UNATTENDED" ]]; then
    dialog "${DIALOG_COMMON[@]}" --colors --title " $(t s_edge_title) " \
      --infobox "\n$(t edge_cloning)" 7 60 || true
  fi
  # GIT_TERMINAL_PROMPT=0 + timeout: unattended/headless installs have no TTY, so a
  # credential challenge (expired token, private repo without creds, transient 401)
  # would otherwise block git on an interactive username prompt forever — the whole
  # install hangs until the e2e S1 timeout. Fail fast + bounded instead, so
  # preset_validate dies loudly here (before the disk is touched) with git's error.
  if ! out=$(GIT_TERMINAL_PROMPT=0 timeout 300 git clone "$url" "$tmp" 2>&1); then
    V_EDGE_MSG="$(t err_edge_clone)"$'\n\n'"$(printf '%s' "$out" | tail -2)"
    rm -rf "$tmp"; return 1
  fi
  if [[ ! -f "$tmp/scripts/apply.sh" ]]; then
    V_EDGE_MSG="$(t err_edge_notw)"; rm -rf "$tmp"; return 1
  fi
  EDGE_SRC_DIR="$tmp"
  return 0
}

# ── W-Packs bundle selection (checklist) ──────────────────────────────────────
# Optional software bundles by direction (containers/graphics/…) sit on top of
# the base apply.sh. The wizard offers whatever is staged under scripts/packs/;
# the chosen set is installed at firstboot (w-pack install) after apply --all.
# Empty tree (after the INSTALLER=off filter) → packs_available is false → the
# step is hidden. Each row: tag = bundle dir, desc = localized key "p_<name>" when
# present, else the bundle's meta.conf DESC. A bundle with INSTALLER=off (e.g.
# ai-extra, userspace-only) is excluded from both — it stays a normal citizen
# everywhere else (w-pack list/install/status, Hub, AI tools).
packs_available() { [[ -n "$(packs_list)" ]]; }

packs_list() {
  local conf name desc installer
  for conf in "$SRC"/scripts/packs/*/meta.conf; do
    [[ -f "$conf" ]] || continue
    name="$(basename "$(dirname "$conf")")"
    installer="$( set +u; source "$conf" 2>/dev/null; printf '%s' "${INSTALLER:-on}" )"
    [[ "$installer" == "off" ]] && continue
    desc="$( set +u; source "$conf" 2>/dev/null; printf '%s' "${DESC:-}" )"
    [[ -n "${MSG[p_$name]:-}" ]] && desc="$(t "p_$name")"
    printf '%s\t%s\n' "$name" "${desc:-$name}"
  done
}

# ── Language selection (first screen, before anything is localized) ───────────
# The list shows each language by its own _lang_name; the default follows $LANG.
select_language() {
  local items=() code name def="" cur="${LANG%%_*}"
  while IFS=$'\t' read -r code name; do
    items+=("$code" "$name")
    [[ "$code" == "$cur" ]] && def="$code"
  done < <(i18n_langs)
  [[ -n "$def" ]] || def="${items[0]}"

  local sel=""
  sel=$(dialog --backtitle "$DIALOG_BACKTITLE" --colors --no-cancel \
    --default-item "$def" --title " Language / Язык " \
    --menu "\n Select installer language:" 12 50 6 "${items[@]}" \
    3>&1 1>&2 2>&3) || sel="$def"
  [[ -n "$sel" ]] || sel="$def"

  i18n_load "$sel"
  nav_init

  # dialog needs a UTF-8 locale to render/measure multibyte text; the VT also
  # needs a font with the language's glyphs (else Cyrillic shows as look-alike
  # Latin). Both are best-effort — harmless over SSH/graphical terminals.
  export LANG=C.UTF-8
  local font="${MSG[_console_font]:-}"
  [[ -n "$font" ]] && setfont "$font" 2>/dev/null || true
}

# ── Map wizard answers onto the CONF_* the work phases read ───────────────────
map_answers() {
  CONF_DISK="${ANSWERS[disk]}"
  CONF_HOSTNAME="${ANSWERS[hostname]}"
  CONF_TZ="${ANSWERS[timezone]}"
  CONF_ROOT_PASS="${ANSWERS[root_pass]}"
  CONF_USER="${ANSWERS[user]}"
  CONF_USER_PASS="${ANSWERS[user_pass]}"
  CONF_KEYMAP="${ANSWERS[keymap]}"
  CONF_LOCALE="${ANSWERS[locale]}"
  [[ "${ANSWERS[encrypt]:-no}" == yes ]]    && CONF_ENCRYPT=true    || CONF_ENCRYPT=false
  CONF_LUKS_PASS="${ANSWERS[luks_pass]:-}"
  CONF_MODE="${ANSWERS[mode]:-stable}"
  CONF_EDGE_REPO="${ANSWERS[edge_repo]:-}"
}

# ── Summary + final confirm ───────────────────────────────────────────────────
confirm_install() {
  local p1; p1="$(part "$CONF_DISK" 1)"
  local p2; p2="$(part "$CONF_DISK" 2)"
  local esp_size root_line boot_line
  if [[ "$CONF_ENCRYPT" == true ]]; then
    esp_size="2G "
    root_line="$p2   rest   LUKS2   → btrfs (cryptroot)"
    boot_line="Limine + limine-snapper-sync"
  else
    esp_size="512M"
    root_line="$p2   rest   btrfs   /"
    boot_line="GRUB + grub-btrfs"
  fi
  dialog "${DIALOG_COMMON[@]}" --colors --title " $(t summary_title) " --msgbox \
"
  Disk       : $CONF_DISK
  Hostname   : $CONF_HOSTNAME
  Timezone   : $CONF_TZ
  Locale     : $CONF_LOCALE
  Keymap     : $CONF_KEYMAP
  User       : $CONF_USER
  Channel    : $CONF_MODE

  Partitions :
    $p1   ${esp_size}   FAT32   /boot/efi
    $root_line

  Subvolumes : @  @home  @home_snapshots  @snapshots  @var_log  @var_cache
  Swap       : zram
  Snapshots  : snapper (root + home) + snap-pac
  Bootloader : $boot_line
" 23 66

  ui_yesno "$(t confirm_title)" "$(t confirm_prompt)" || die "$(t quit)"
}

# ── Logging ──────────────────────────────────────────────────────────────────
W_LOG=""
# fd for dialog's on-screen display (dialog draws its SCREEN to stdout). Saved as
# a genuine dup of the real terminal NOW, before anything else runs — not just
# the literal "1" — because widgets that capture their result via
# `$(dialog ... 3>&1 1>&"$W_TTY" 2>&3)` (the wizard's SSID picker, password box)
# run inside a command substitution, where plain fd 1 is already the capture
# pipe, not the terminal; only a real, separate fd can still reach the terminal
# from in there. Reused unchanged once stdout/stderr are redirected to the log
# in init_logging (work phase) below.
exec {W_TTY}>&1
init_logging() {
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  W_LOG="/tmp/w-install-$ts.log"
  {
    echo "=== W Linux install log — $ts ==="
    echo "lang=$LANG_CODE disk=$CONF_DISK host=$CONF_HOSTNAME tz=$CONF_TZ user=$CONF_USER encrypt=$CONF_ENCRYPT"
    echo "==================================================================="
  } > "$W_LOG"
  exec {W_TRACE_FD}>>"$W_LOG"
  export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
  BASH_XTRACEFD=$W_TRACE_FD
  set -x
  # $W_TTY was already saved above, before the wizard ever ran. Now send
  # work-phase stdout/stderr to the log ONLY, so chroot command output no longer
  # scrolls over the TUI. Dialog widgets add `1>&$W_TTY` (dialog's screen is on
  # stdout); pacstrap output is tee'd to the log.
  exec >>"$W_LOG" 2>&1
  trap finalize_logging EXIT
}

finalize_logging() {
  set +x
  sleep 0.5; sync
  mkdir -p "$MNT/var/log/w" 2>/dev/null \
    && cp "$W_LOG" "$MNT/var/log/w/install.log" 2>/dev/null || true
  # Mirror to the host share(s). $SRC/vm/logs covers the dev-VM run from the
  # share itself; the explicit /w-src path covers an E2E run from the ISO's
  # baked copy (there $SRC=/root/w is tmpfs — the log would die with the live
  # session), where .zlogin mounted the virtiofs share separately.
  local share_logs
  for share_logs in "$SRC/vm/logs" /w-src/vm/logs; do
    if [[ -d "${share_logs%/logs}" ]] && mkdir -p "$share_logs" 2>/dev/null; then
      cp "$W_LOG" "$share_logs/$(basename "$W_LOG")" 2>/dev/null || true
    fi
  done
}

# Finalize the log, THEN reboot. `systemctl reboot` is asynchronous: it begins
# tearing down mounts (the target /mnt and, in a dev/E2E run, the /w-src share)
# the instant it is called, which races — and beats — the EXIT-trap log
# finalizer, leaving no install log on either the target OR the share (the
# mirrored share log carrying "Unattended install complete" is exactly the E2E
# S1 success signal). Mirror the log now, while everything is still mounted, then
# reboot; clearing the EXIT trap avoids a second, post-teardown finalize that
# would just race the unmount again and fail.
finish_and_reboot() {
  trap - EXIT
  finalize_logging
  systemctl reboot
}

# ── Welcome / done screens ────────────────────────────────────────────────────
show_welcome() {
  dialog "${DIALOG_COMMON[@]}" --colors --title " $(t welcome_title) " --msgbox \
"\n\Zb\Z5  ██╗    ██╗\n  ██║    ██║\n  ██║ █╗ ██║\n  ╚███╔███╔╝\n   ╚══╝╚══╝\Zn\n\n$(t welcome_body)\n" \
  20 60
}

show_done() {
  if [[ -n "$W_UNATTENDED" ]]; then
    # Headless: nobody is there to press Reboot (output goes to the log).
    echo "=== Unattended install complete — rebooting into firstboot. ==="
    finish_and_reboot
    return
  fi
  # Stay inside the TUI instead of dropping to the console: a single "Reboot"
  # button (dialog's screen goes to $W_TTY, like every other work-phase dialog).
  local extra="" box_h=20
  if [[ "$CONF_ENCRYPT" == true ]]; then
    # Two facts the encrypted path owes the user before the first boot: the
    # passphrase prompt is coming, and the two things that eventually remove it
    # (Secure Boot, then the TPM2 seal) live in the Hub — the installer cannot do
    # either, both need firmware steps outside the OS. See package-limine.md.
    extra="\n\n  $(t done_luks_notice)\n\n  $(t done_secureboot_notice)"
    box_h=27
  fi
  dialog "${DIALOG_COMMON[@]}" --ok-label "$(t reboot)" --title " $(t done_title) " --msgbox \
"\n\Zb\Z5  ██╗    ██╗\n  ██║    ██║\n  ██║ █╗ ██║\n  ╚███╔███╔╝\n   ╚══╝╚══╝\Zn\n\n  $(t done_reboot)$extra\n" \
  "$box_h" 64 1>&"${W_TTY:-1}"
  finish_and_reboot
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  require_root
  require_uefi
  command -v dialog &>/dev/null || pacman -Sy --noconfirm dialog

  load_steps
  if [[ -n "$W_UNATTENDED" ]]; then
    # Unattended: the preset replaces the whole interactive phase. Same defaults
    # the wizard seeds, then the preset overrides; validation replays the step
    # validators offline and aborts loudly before anything touches the disk.
    ANSWERS[keymap]="us"
    ANSWERS[locale]="en_US.UTF-8"
    ANSWERS[hostname]="w"
    ANSWERS[timezone]="Europe/Moscow"
    ANSWERS[mode]="edge"
    ANSWERS[edge_repo]="$W_PUBLIC_EDGE_REPO"
    answers_load "$PRESET_FILE"
    i18n_load "${lang:-en}"
    nav_init
    export LANG=C.UTF-8   # progress gauges still render on the console
    # Start logging + tracing NOW, before preset_validate. On the edge path that
    # validator runs a live `git clone` (v_edge_repo); any early failure there used
    # to die BEFORE init_logging armed the finalize/mirror EXIT trap, so the headless
    # harness got no mirrored log and burned its full ~45-min S1 timeout with zero
    # signal. Armed here, the validation is traced and finalize_logging mirrors the
    # partial log to the share on exit. Safe only in unattended mode — there is no
    # TUI whose stdout the log redirect would clobber (interactive keeps its
    # init_logging after the wizard, below). CONF_* are still empty in the header
    # here (map_answers runs after validation); the trace itself carries the detail.
    init_logging
    preset_validate
    map_answers
  else
    # Interactive phase — declarative wizard driven by steps.conf.
    select_language
    show_welcome
    # Seed defaults (widgets pre-fill from ANSWERS). Locale follows the TUI language.
    ANSWERS[keymap]="us"
    case "$LANG_CODE" in ru) ANSWERS[locale]="ru_RU.UTF-8" ;; *) ANSWERS[locale]="en_US.UTF-8" ;; esac
    ANSWERS[hostname]="w"
    ANSWERS[timezone]="Europe/Moscow"
    ANSWERS[mode]="edge"
    ANSWERS[edge_repo]="$W_PUBLIC_EDGE_REPO"
    wizard_run    || die "$(t quit)"
    wizard_review || die "$(t quit)"
    map_answers
    confirm_install
    init_logging   # after the wizard/TUI — the log redirect must not clobber dialog
  fi

  # Fail fast BEFORE erasing the disk if there is no internet — pacstrap and the
  # firstboot apply both need it (Wi-Fi should already be up from the wizard step).
  ensure_network

  # Phase 1: Disk
  disk_partition "$CONF_DISK"
  [[ "$CONF_ENCRYPT" == true ]] && disk_encrypt "$CONF_DISK"
  disk_format    "$CONF_DISK"
  disk_mount     "$CONF_DISK"

  # Phase 2: Base packages (real progress bar)
  mod_base

  # Phase 3: fstab
  disk_fstab

  # Phase 4: System configuration
  sys_timezone
  sys_locale
  sys_hostname
  sys_hosts
  sys_root_password
  sys_create_user
  sys_ssh_key
  sys_journal

  # Persist the answers as the single source for the firstboot phase (Session 2
  # will read this instead of re-asking). Harmless now; written after base so
  # /var/lib exists on the target.
  answers_serialize "$MNT/var/lib/w/install.conf"

  # Phase 5: Encryption initramfs prep (before plymouth's single mkinitcpio -P).
  [[ "$CONF_ENCRYPT" == true ]] && limine_prep_initramfs

  # Phase 6: Services and tooling
  mod_plymouth
  if [[ "$CONF_ENCRYPT" == true ]]; then
    mod_limine
    # Headless: nobody can type the LUKS passphrase on the coming boots — enroll
    # TPM2 auto-unlock now. Interactive installs keep this a post-boot w-crypt step.
    [[ -n "$W_UNATTENDED" ]] && limine_enroll_tpm
  else
    mod_bootloader
    mod_grub
  fi
  mod_network
  mod_wifi
  mod_zram
  mod_snapshots

  # Phase 7: Stage the firstboot handoff (Session 2) — must run last so it packages
  # the finished target as-is and enables the service that finishes the job on reboot.
  mod_firstboot

  show_done
}

main "$@"
