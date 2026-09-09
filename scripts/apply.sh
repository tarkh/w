#!/usr/bin/env bash
# apply.sh — apply W Linux configuration to the running system
# Run inside the installed VM as root: bash /mnt/w-src/scripts/apply.sh
set -euo pipefail

# apply is a managed bulk operation — no per-transaction snap-pac snapshots during it.
# This both silences snap-pac's "fatal library error, lookup self" crash while the root
# Snapper config doesn't exist yet (created last, by fix_snapper) and reinforces the
# single-`initial`-snapshot policy. The `initial` anchor is a manual `snapper create`,
# unaffected. Not persisted → normal snap-pac resumes for ordinary post-install pacman.
export SNAP_PAC_SKIP=y

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES="$SRC/scripts/install/modules"

source "$SRC/scripts/install/lib/deploy.sh"
source "$SRC/scripts/install/lib/pac.sh"
source "$SRC/scripts/install/lib/aurbuild.sh"
source "$SRC/scripts/install/lib/modules.sh"

die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;35m==>\033[0m $*"; }
# crit(): for install steps that are mandatory (not an optional add-on) but can
# legitimately fail on real hardware without network yet at firstboot-time —
# same non-fatal/retryable contract as a plain WARN, but tagged distinctly so
# an environment that guarantees network (the e2e VM) can grep apply.log and
# gate on it: a CRITICAL there is a real regression, not an expected offline
# branch. See vm/e2e.sh S3 assertions.
crit() { echo -e "\033[1;31mCRITICAL:\033[0m $*"; }

# ── Logging ───────────────────────────────────────────────────────────────────
# Capture the full run (no dialog here → safe global tee). Appended per session.
if [[ $EUID -eq 0 && -z "${W_APPLY_LOGGED:-}" ]]; then
  export W_APPLY_LOGGED=1
  W_APPLY_LOG="/var/log/w/apply.log"
  mkdir -p /var/log/w
  { echo; echo "=== apply.sh $(date '+%Y-%m-%d %H:%M:%S') — args: $* ==="; } >> "$W_APPLY_LOG"
  exec > >(tee -a "$W_APPLY_LOG") 2>&1
  # set -e aborts silently (the failing command's status, no message). Surface the
  # exact line + command so a mid-run abort is never invisible in the log again —
  # this is precisely what masked the quickshell pipefail abort before.
  trap 'rc=$?; echo -e "\033[1;31mERROR:\033[0m apply.sh aborted (exit $rc) at ${BASH_SOURCE##*/}:${LINENO}: ${BASH_COMMAND}"' ERR
  # Drop a copy onto the virtiofs share on any exit (incl. failure) — host-readable.
  # sync first so tee has flushed the final (error) line before we copy.
  _w_apply_save() {
    sync; sleep 0.3; sync
    local share="$SRC/vm/logs"
    mkdir -p "$share" 2>/dev/null \
      && cp "$W_APPLY_LOG" "$share/w-apply-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null || true
  }
  trap _w_apply_save EXIT
fi

# ── Module registry ───────────────────────────────────────────────────────────
# Which modules exist, in what order they run, and what each one is called — all of
# it lives in scripts/install/modules.conf now (read through lib/modules.sh). The
# source list, the --all sequence, the flag dispatch and usage() below are derived
# from it, so they cannot drift apart the way the hand-kept copies did.
w_modules_load "$SRC/scripts/install/modules.conf" || die "module registry unusable"
mapfile -t _mod_files < <(w_modules_files apply manual dev)
[[ ${#_mod_files[@]} -gt 0 ]] || die "module registry lists no post-boot module files"
for _f in "${_mod_files[@]}"; do source "$MODULES/$_f"; done
unset _f _mod_files

[[ $EUID -eq 0 ]] || die "Must be run as root."
[[ -d "$SRC" ]]   || die "Project source not found: $SRC"

# ── Snapper ───────────────────────────────────────────────────────────────────
# `snapper create-config` always carves its .snapshots as a btrfs SUBVOLUME. W does
# not use it: the snapshots live in the top-level @snapshots/@home_snapshots, which
# fstab mounts over that path — so the one snapper made stays empty and invisible
# underneath, and the mount point must be a plain directory instead.
#
# Invisible is not harmless. A nested subvolume is what `btrfs subvolume list -o @`
# reports, and limine-snapper-restore moves every child of the outgoing root into the
# restored one. That move is a rename() of an active mount point → EBUSY, and the
# whole "Moving child subvolumes" step fails ("Device or resource busy"), leaving
# /var/lib/machines and /var/lib/portables behind and the kept root un-deletable by
# `snapper delete` (a subvolume with a child). Found on the first real Limine rollback
# taken from a normal @ — the earlier runs were taken from inside a snapshot, where
# .snapshots is already a plain dir because snapshots are non-recursive.
#
# Only .snapshots is affected: the nested subvolumes W creates on purpose (uv/pip
# caches, the rootless container store — snapshot exclusion by non-recursion) live
# under @home and are not mount points, so nothing renames them.
#
# $1 = the .snapshots path, which must NOT be mounted over when this is called.
flatten_snapshots_dir() {
  local dir="$1"
  btrfs subvolume show "$dir" &>/dev/null || return 0
  # Refuse a populated one: that would mean snapshots really were written there
  # (mount missing at the time), and deleting it would delete them.
  if [[ -n "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    echo "  WARN: $dir is a non-empty nested subvolume — left as-is (rollback will not move it)."
    return 0
  fi
  info "Flattening nested subvolume $dir into a plain mount point..."
  btrfs subvolume delete "$dir" >/dev/null || { echo "  WARN: could not delete $dir."; return 0; }
  mkdir -m 750 "$dir"
}

# Same, for a path that is currently mounted over: repair pass for machines installed
# before the above existed (they reach it through w-update → apply.sh). Best-effort in
# every branch — a busy /.snapshots must leave the machine exactly as it was, never
# unmounted. `if`, not `[[ … ]] && …`: a false test as the last statement would return
# 1 and take apply.sh down with set -e.
remount_flatten_snapshots_dir() {
  local dir="$1"
  mountpoint -q "$dir" || return 0
  umount "$dir" 2>/dev/null || return 0
  flatten_snapshots_dir "$dir"
  if ! mount "$dir"; then die "could not re-mount $dir — snapshots are not visible."; fi
}

fix_snapper() {
  info "Configuring snapper..."

  if ! snapper -c root list &>/dev/null; then
    # Config doesn't exist yet — create it (D-Bus is available in live system)
    if mountpoint -q /.snapshots; then
      umount /.snapshots
    fi
    [[ -d /.snapshots ]] && rmdir /.snapshots
    snapper -c root create-config /
    flatten_snapshots_dir /.snapshots
    # Re-mount @snapshots subvolume (fstab entry already correct)
    mount /.snapshots
  else
    info "Snapper config already exists, skipping create."
    # Repair pass for machines installed before the flatten existed — see the
    # function's comment. Runs on every apply; a no-op once the dir is flat.
    remount_flatten_snapshots_dir /.snapshots
  fi

  # Root retention (enforced every run, idempotent): keep the last N snap-pac
  # snapshots, rotate the rest. NUMBER_CLEANUP=yes is the key — snapper's default is
  # "no", so pacman snapshots would otherwise grow unbounded. TIMELINE off for root:
  # meaningful rollback points come from snap-pac (pre/post pacman), not hourly
  # timeline noise (which also clutters the snapshot boot menu). The `initial`
  # anchor is created with NO cleanup algorithm → never counted or pruned here.
  snapper -c root set-config \
    TIMELINE_CREATE=no TIMELINE_CLEANUP=yes \
    NUMBER_CLEANUP=yes NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10 NUMBER_MIN_AGE=1800

  configure_home_snapper

  info "Enabling snapper timers..."
  systemctl enable --now snapper-timeline.timer
  systemctl enable --now snapper-cleanup.timer

  # Snapshot→boot bridge: grub-btrfsd rebuilds the GRUB submenu on plain installs.
  # On encrypted/Limine installs the equivalent is limine-snapper-sync (enabled by
  # mod_limine) — grub-btrfsd there watches a GRUB config nothing boots, so skip it.
  if [[ ! -f /etc/default/limine ]]; then
    info "Enabling grub-btrfs daemon..."
    systemctl enable --now grub-btrfsd.service
  fi

  # Tell the user, at login, when the session is running from a snapshot. Booting one
  # is the recovery path and its root is read-only, but the desktop looks completely
  # normal — without a word, work done outside /home is silently lost. Global enable
  # for the same reason hypridle and the night-light tick use it: every login user's
  # uwsm session needs its own instance. The helper self-gates (silent on a normal
  # boot, and it stands aside where limine-snapper-sync ships its own notification
  # with a Restore button), so this is enabled unconditionally on both boot paths.
  info "Enabling snapshot-boot notice..."
  systemctl --global enable w-snapshot-notify.service 2>/dev/null || true
}

# Separate `home` snapper config (update-system Phase 4): soft, timeline-only
# retention protecting user config edits. Relies on the @home_snapshots subvolume +
# its fstab entry from disk.sh; on a pre-Phase-4 install it isn't there, so we skip
# rather than let snapper create a nested (inconsistent) .snapshots subvolume. Not
# pacman-coupled (snap-pac only hooks the root config by default), no grub-btrfs.
configure_home_snapper() {
  if snapper -c home list &>/dev/null; then
    info "Home snapper config already exists, skipping."
    remount_flatten_snapshots_dir /home/.snapshots
    return 0
  fi
  if ! mountpoint -q /home/.snapshots; then
    info "@home_snapshots subvolume absent — skipping home snapper (reinstall to enable)."
    return 0
  fi
  info "Configuring home snapper..."
  umount /home/.snapshots
  rmdir  /home/.snapshots 2>/dev/null || true
  snapper -c home create-config /home
  flatten_snapshots_dir /home/.snapshots
  mount /home/.snapshots   # re-mount top-level @home_snapshots (fstab entry present)
  snapper -c home set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=6 TIMELINE_LIMIT_DAILY=7 \
    TIMELINE_LIMIT_WEEKLY=2 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
}

# ── Rootfs overlay ────────────────────────────────────────────────────────────
# Admin-state that an update must PRESERVE is declared once, in the ownership
# manifests (class `override`). apply_rootfs is the only thing that copies rootfs/
# over /, so it is the only place that can honour that contract — a guard inside
# an individual module cannot: mod_hyprland's seed-if-absent for terminal.conf ran
# AFTER this rsync had already put the vendor file back, so it never fired. Same
# defect reset the machine mode, the active theme and the NTP selection in the
# field. Semantics here are seed-if-absent: the vendor file still ships when the
# destination is missing (fresh install), and is skipped once it exists.
override_excludes() {
  local mdir="$SRC/rootfs/usr/share/w/update" m path class
  [[ -d "$mdir" ]] || return 0
  for m in "$mdir"/*.manifest; do
    [[ -f "$m" ]] || continue
    # `|| [[ -n $path ]]` so a final line without a trailing newline is still read.
    while IFS=$'\t' read -r path class || [[ -n "$path" ]]; do
      [[ "$path" == /* && "$class" == override && -e "$path" ]] || continue
      printf -- '--exclude=%s\n' "$path"
    done < "$m"
  done
  return 0
}

apply_rootfs() {
  info "Syncing rootfs..."
  if compgen -G "$SRC/rootfs/*" &>/dev/null; then
    local excl=()
    mapfile -t excl < <(override_excludes)
    if (( ${#excl[@]} )); then
      info "  preserving ${#excl[@]} admin-state path(s) (manifest class 'override')"
    fi
    rsync -av --chown=root:root --exclude='.gitkeep' \
      --exclude='__pycache__/' --exclude='*.pyc' "${excl[@]}" "$SRC/rootfs/" /
  else
    echo "  rootfs/ is empty, skipping."
  fi

  # Record the /etc paths W ships, so the .pacnew reconciler (alpm hook
  # 96-w-pacnew-reconcile) knows which .pacnew are W-owned noise and can drop them.
  # Regenerated from the source tree on every apply → never drifts.
  if [[ -d "$SRC/rootfs/etc" ]]; then
    mkdir -p /usr/share/w
    ( cd "$SRC/rootfs/etc" && find . -type f ! -name '.gitkeep' -printf '/etc/%P\n' ) \
      | sort -u > /usr/share/w/managed-etc.list
  fi

  migrate_split_configs
}

# One-shot migration of every subsystem that has been split into vendor/admin
# layers (update-system.md phase 2+). A machine installed before the split carries
# a full copy of the vendor file in /etc/w/<subsys>.conf; since the update
# preserves that file by ownership class, every key in it would stay pinned and
# improved defaults would never arrive — the exact bug the split removes. The
# migration drops the keys that merely repeat the vendor default and keeps the
# rest (see wconf_migrate).
#
# It lives HERE, right after the only place that copies rootfs → /, for the same
# reason the override contract does: one point of enforcement beats a guard in
# every module. Marker files make it a no-op on every later apply.
migrate_split_configs() {
  local lib=/usr/lib/w/w-conf-lib.sh f s
  [[ -r "$lib" ]] || return 0
  # shellcheck source=../rootfs/usr/lib/w/w-conf-lib.sh
  source "$lib"
  for f in /usr/share/w/defaults/*.conf; do
    [[ -f "$f" ]] || continue
    s="$(basename "$f" .conf)"
    # power brings its own migration: its vendor layer is GENERATED from the preset
    # tables, so the honest baseline is the preset for the machine's recorded MODE,
    # not the file on disk. w-power runs it before writing anything.
    [[ "$s" == power ]] && continue
    wconf_migrate "$s"
  done
  return 0
}

# ── Yay (AUR helper) ─────────────────────────────────────────────────────────
# w-repo: unsigned local repo baked onto our own ISO (build-iso.sh), staged onto
# the target by mod_firstboot with a [w-repo] entry prepended to pacman.conf. When
# present it lets firstboot install yay as a binary instead of compiling it —
# breaking the chicken-and-egg (nothing can build AUR packages before yay exists).
# Absent in the dev-VM workflow (stock Arch ISO) or on re-runs after the one-shot
# bootstrap below has already removed the entry — the makepkg fallback covers both.
install_yay() {
  if command -v yay &>/dev/null; then
    info "yay already installed, skipping."
    return
  fi

  if grep -q '^\[w-repo\]$' /etc/pacman.conf 2>/dev/null; then
    info "Installing yay from w-repo (prebuilt, no compile)..."
    w_pac -Sy --needed --noconfirm yay
    remove_w_repo
    return
  fi

  info "Installing yay (building from AUR)..."
  w_pac -S --needed --noconfirm git base-devel go

  # yay must be built as non-root
  local build_user
  build_user=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
  [[ -n "$build_user" ]] || die "No non-root user found to build yay."

  local tmp; tmp=$(mktemp -d)
  # Give full ownership of tmp dir so build_user can cd into it
  chown "$build_user:$build_user" "$tmp"

  # AUR occasionally returns a transient 5xx; a single failure here would abort the
  # whole first-boot apply at module 2/34. Retry a few times with backoff.
  local attempt
  for attempt in 1 2 3; do
    if git clone https://aur.archlinux.org/yay.git "$tmp/yay"; then
      break
    fi
    info "yay clone failed (attempt $attempt/3) — retrying in $((attempt * 5))s..."
    rm -rf "$tmp/yay"
    sleep $((attempt * 5))
  done
  [[ -d "$tmp/yay/.git" ]] || die "Failed to clone yay from AUR after 3 attempts."
  chown -R "$build_user:$build_user" "$tmp/yay"
  # Build only (no -i), then install as root
  su - "$build_user" -c "cd $tmp/yay && makepkg -s --noconfirm"
  pacman -U --noconfirm "$tmp"/yay/yay-*.pkg.tar.zst

  rm -rf "$tmp"
}

# One-shot bootstrap only — w-repo's `yay` build is pinned to ISO-build time and
# goes stale immediately. Drop it from pacman.conf right after use so a later
# `pacman -Syu` never tries to sync against it (files under /var/lib/w/w-repo are
# left in place, harmless, in case they're useful for debugging).
remove_w_repo() {
  grep -q '^\[w-repo\]$' /etc/pacman.conf || return 0
  sed -i '/^\[w-repo\]$/,/^$/d' /etc/pacman.conf
}

# ── Packages ──────────────────────────────────────────────────────────────────
install_packages() {
  info "Installing packages..."

  local pacman_list="$SRC/packages/pacman.txt"

  if [[ -f "$pacman_list" ]]; then
    local pkgs
    pkgs=$(sed 's/#.*//' "$pacman_list" | grep -v '^\s*$' | tr '\n' ' ') || true
    # rootfs/ is a curated overlay that intentionally shadows some package files
    # (e.g. our hyprland.desktop); apply_rootfs lays them down before packages, so
    # let pacman overwrite within those overlay zones instead of erroring out.
    [[ -n "${pkgs// }" ]] && w_pac -S --needed --noconfirm \
      --overwrite '/usr/share/wayland-sessions/*' $pkgs
  fi

  install_aur
}

# ── AUR packages ───────────────────────────────────────────────────────────────
# First unprivileged login user (uid 1000–65533) — makepkg refuses to run as root.
aur_build_user() {
  awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd
}

# Run `yay` as an unprivileged build user with a *temporary* passwordless-sudo grant.
# yay shells out to `sudo pacman` internally to install make-deps and the finished
# package; the permanent wheel policy stays password-gated, so without this grant yay
# blocks forever on a sudo password prompt (this is exactly what hung the encrypted
# install when mod_limine pulled its AUR hooks). The grant is created before and
# ALWAYS revoked after. Args after the user are passed straight to yay. Headless in
# both contexts: post-boot (dev VM) and installer chroot (root + a wheel user).
run_yay() {
  local bu="$1"; shift
  [[ -n "$bu" ]] || die "run_yay: no build user."

  # Name sorts AFTER the wheel drop-in: sudoers.d is read in lexical order and the
  # last matching rule wins, so this must come after "%wheel ... ALL" (which needs
  # a password) for the NOPASSWD grant to take effect for $bu.
  local sudoers="/etc/sudoers.d/zzzz-w-aur-build"
  echo "$bu ALL=(ALL) NOPASSWD: ALL" > "$sudoers"
  chmod 440 "$sudoers"
  visudo -cf "$sudoers" >/dev/null || { rm -f "$sudoers"; die "Generated AUR sudoers invalid."; }

  local rc=0
  sudo -u "$bu" -H yay "$@" || rc=$?
  rm -f "$sudoers"   # always revoke the temporary grant
  return $rc
}

# Build + install every package in aur.txt, non-interactively.
install_aur() {
  local aur_list="$SRC/packages/aur.txt"
  [[ -f "$aur_list" ]] || return 0

  local pkgs
  pkgs=$(sed 's/#.*//' "$aur_list" | grep -v '^\s*$' | tr '\n' ' ') || true
  [[ -n "${pkgs// }" ]] || return 0

  install_yay   # idempotent — ensures the helper exists before we need it

  local bu; bu=$(aur_build_user)
  [[ -n "$bu" ]] || die "No unprivileged user found to build AUR packages."

  info "Building AUR packages as '$bu': $pkgs"
  run_yay "$bu" -S --needed --noconfirm --removemake \
          --answerdiff None --answerclean None $pkgs \
    || die "AUR build failed."
}

# ── Plymouth ──────────────────────────────────────────────────────────────────
apply_plymouth() {
  info "Installing Plymouth..."
  w_pac -S --needed --noconfirm plymouth rsync

  info "Syncing Plymouth theme..."
  rsync -a --chown=root:root "$SRC/rootfs/usr/share/plymouth/" /usr/share/plymouth/

  # Seed the logo from the baseline theme (w-style later swaps it per active theme).
  # The logo lives in the theme system, not in the committed Plymouth dir. Rendered,
  # not copied: its pixel size has to match what the wallpapers show on THIS panel,
  # or the mark changes size the moment the splash hands over to the greeter.
  # Sourced from the repo copy — /usr/lib/w is populated by apply_rootfs, which
  # --plymouth alone does not run.
  W_WALLPAPER_BIN="$SRC/rootfs/usr/bin/w-wallpaper"
  # shellcheck source=/dev/null
  source "$SRC/rootfs/usr/lib/w/plymouth-logo.sh"
  plymouth_logo_install "$SRC/rootfs/etc/w/themes/w" /usr/share/plymouth/themes/w/logo.png
  chmod 644 /usr/share/plymouth/themes/w/logo.png

  # plymouthd's own config (theme + DeviceScale=1 — see the file's header). Copied
  # explicitly rather than left to apply_rootfs: the copy that matters is the one
  # inside the initramfs rebuilt below, and --plymouth must work on its own.
  info "Deploying plymouthd config..."
  mkdir -p /etc/plymouth
  cp "$SRC/rootfs/etc/plymouth/plymouthd.conf" /etc/plymouth/plymouthd.conf

  info "Configuring mkinitcpio..."
  if ! grep -q 'plymouth' /etc/mkinitcpio.conf; then
    sed -i 's/\bkms\b/kms plymouth/' /etc/mkinitcpio.conf
  fi

  info "Configuring GRUB..."
  if ! grep -q '\bsplash\b' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' \
      /etc/default/grub
  fi
  if ! grep -q '\bquiet\b' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet"/' \
      /etc/default/grub
  fi

  info "Deploying plymouth-quit seamless transition override..."
  mkdir -p /etc/systemd/system/plymouth-quit.service.d
  cp "$SRC/rootfs/etc/systemd/system/plymouth-quit.service.d/override.conf" \
    /etc/systemd/system/plymouth-quit.service.d/override.conf

  # Freeze the boot-progress estimate while the LUKS prompt waits for a human — it is
  # wall-clock based, so without this the wait eats the scale and the bar comes back
  # part-filled. Rides into the initramfs with the rest of the unit's drop-ins.
  info "Deploying ask-password progress-pause drop-in..."
  mkdir -p /etc/systemd/system/systemd-ask-password-plymouth.service.d
  cp "$SRC/rootfs/etc/systemd/system/systemd-ask-password-plymouth.service.d/10-w-pause-progress.conf" \
    /etc/systemd/system/systemd-ask-password-plymouth.service.d/10-w-pause-progress.conf
  systemctl daemon-reload

  info "Setting Plymouth theme and rebuilding initramfs..."
  # Set the default theme without -R (which would rebuild through the mkinitcpio shim);
  # w-mkinitcpio owns the bootloader-aware rebuild — `limine-mkinitcpio` on the Limine
  # kernel-install/BLS path (staging the ESP itself), classic `mkinitcpio -P` on GRUB.
  # Deployed by apply_rootfs (the first --all module), so it's present by the time we get
  # here. In --all this runs before the bootloader module installs limine-mkinitcpio-hook,
  # so it takes the GRUB fallback; mod_style's Plymouth axis rebuilds again post-Limine.
  plymouth-set-default-theme w
  w-mkinitcpio

  info "Regenerating GRUB config..."
  grub-mkconfig -o /boot/grub/grub.cfg
}

# Bootloader is picked per install type: encrypted systems run Limine, plain run GRUB.
# Detected by the presence of /etc/default/limine (only the Limine path deploys it).
apply_bootloader() {
  if [[ -f /etc/default/limine ]]; then mod_limine; else mod_grub; fi
}

# ── Full apply ────────────────────────────────────────────────────────────────
# The sequence and the labels come from the registry (phase `apply`, in file order);
# the "@@WFB i n label@@" markers below are what the firstboot progress TUI reads
# (scripts/install/lib/progress.sh:progress_modules) to drive its gauge. Label text
# stays plain English like the rest of apply.sh's info() output — no i18n plumbing.
run_all() {
  pre_apply_home_snapshot
  local i n=0 idx=() fn
  for ((i = 0; i < W_MOD_N; i++)); do
    if [[ "${W_MOD_PHASE[i]}" == apply ]]; then idx+=("$i"); n=$((n + 1)); fi
  done
  [[ $n -gt 0 ]] || die "module registry lists no --all modules"
  local step=0
  for i in "${idx[@]}"; do
    step=$((step + 1))
    fn="${W_MOD_FN[i]}"
    echo "@@WFB $step $n ${W_MOD_LABEL[i]}@@"
    declare -F "$fn" >/dev/null || die "module '${W_MOD_NAME[i]}': function $fn is not defined"
    "$fn"
  done
  initial_snapshot
}

# ── Pre-apply home snapshot ───────────────────────────────────────────────────
# Capture user home config before a full apply seeds/overwrites managed files, so a
# bad apply can be undone with `snapper -c home undochange`. Cleanup-algorithm
# number → auto-pruned by the soft home retention (not kept forever). Runs before
# any module; on the first install the home config doesn't exist yet (home is empty
# anyway) so it skips gracefully. The fuller w-sync/w-system pre-snapshot hook lands
# in update-system Phase 5; this is the standalone minimum.
pre_apply_home_snapshot() {
  command -v snapper &>/dev/null || return 0
  if ! snapper -c home list &>/dev/null; then
    info "Home snapper config absent, skipping pre-apply snapshot."
    return 0
  fi
  info "Creating pre-apply home snapshot..."
  snapper -c home create --description "pre-apply" --cleanup-algorithm number \
    || info "Pre-apply home snapshot failed (non-fatal)."
}

# ── Initial rollback anchor ───────────────────────────────────────────────────
# After a full apply, before the user's first reboot, drop a permanent Snapper
# snapshot capturing the freshly-installed state, so there is always a clean base
# to roll back to. No cleanup algorithm + important=yes → never auto-pruned.
# Idempotent: created once (runs at the tail of --all/--dev, after snapper is set up).
initial_snapshot() {
  command -v snapper &>/dev/null || return 0
  snapper -c root list &>/dev/null || { info "Snapper not configured, skipping initial snapshot."; return 0; }
  if snapper -c root list | grep -q 'W initial state'; then
    info "Initial snapshot already exists, skipping."
    return 0
  fi
  info "Creating initial rollback snapshot..."
  snapper -c root create --description "W initial state" --userdata "important=yes" \
    || info "Initial snapshot creation failed (non-fatal)."
}

# ── Main ──────────────────────────────────────────────────────────────────────
# usage/dispatch are generated from the registry: a flag exists exactly when a row
# declares one, and it calls exactly that row's function. --all/--dev stay explicit
# (they are compositions, not modules).
usage() {
  local flags=() f line="Usage: apply.sh"
  mapfile -t flags < <(w_modules_flags apply manual)
  for f in "${flags[@]}"; do line+=" [$f]"; done
  echo "$line [--all] [--devtools] [--dev]"
  echo "  No args: runs --snapper + --rootfs"
  echo "  --devtools: deploy dev-only test helpers (VM only, never in --all/build)"
  echo "  --dev:      --all + --devtools (manual dev-VM use)"
}

# flag → function, for every phase that owns one (install-only modules have none).
declare -A FLAG_FN=()
for ((_i = 0; _i < W_MOD_N; _i++)); do
  if [[ -n "${W_MOD_FLAG[_i]}" && "${W_MOD_PHASE[_i]}" != install ]]; then
    FLAG_FN["${W_MOD_FLAG[_i]}"]="${W_MOD_FN[_i]}"
  fi
done
unset _i

ARGS=("$@")
[[ ${#ARGS[@]} -eq 0 ]] && ARGS=(--snapper --rootfs)

for arg in "${ARGS[@]}"; do
  case "$arg" in
    --all)      run_all          ;;
    # Dev-VM convenience: full apply + dev helpers. Never used by the installer.
    --dev)      run_all; mod_devtools ;;
    *)
      fn="${FLAG_FN[$arg]:-}"
      [[ -n "$fn" ]] || { usage; exit 1; }
      declare -F "$fn" >/dev/null || die "flag $arg maps to $fn, which is not defined"
      "$fn" ;;
  esac
done

# ── Theme render finalizer ────────────────────────────────────────────────────
# Last, unconditionally: every module that lays config into a home has just done
# so, and the per-user theme artifacts are a FUNCTION of each account's active
# theme — nothing shipped can be right for a user who is not on the baseline
# theme `w` (see lib/deploy.sh, w_render_user_theme). This is also the only place
# an existing account gets re-rendered at all: mod_style runs `w-style apply all`
# as root, whose user scope writes /etc/skel, not homes.
#
# Unconditional rather than "only after the modules that touch home": that list
# is a registry to forget, and a forgotten entry fails silently — exactly the
# class of invisible breakage check/routing.sh exists to catch. Rendering after
# an unrelated module (--dns) is a few file writes plus a hyprctl reload, which
# is idempotent and cheap.
w_render_user_themes

echo ""
info "Done."
