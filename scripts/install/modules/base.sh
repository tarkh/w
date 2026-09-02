# modules/base.sh — pacstrap base system

MIRRORLIST="/etc/pacman.d/mirrorlist"
# Depth is not cosmetic: pacman's own fallback ("too many errors from X, skipping
# for the remainder of this transaction") only works while there is somewhere
# left to go. One or two mirrors in the list = no fallback at all.
MIRRORS_MIN=10
# How many head entries the pre-flight probes before giving up.
MIRRORS_PROBE=5

# Mirror selection — layer 1 of the package-delivery plan (installer.md §5). Two
# failure classes are cut right here, and neither of them is curable by a retry
# later on:
#   * a host that answers the probe but does not serve data — it must drop out ON
#     THE RATING, not in the middle of pacstrap;
#   * a stale host — --age: its db is accepted while the packages it lists are
#     not on that mirror yet → 404 in the middle of a transaction.
# pacstrap copies this file into the target (copymirrorlist=1), so whatever comes
# out of here is what the installed machine lives with until w-mirrors (§5 Ф.3)
# exists — which is why depth is preserved instead of trimming aggressively.
#
# None of the numbers are arbitrary. reflector's rate probe is a full
# extra/os/x86_64/extra.db download (~8.8 MB) cut short by SIGALRM at
# --download-timeout, so:
#   --score 30            pre-filter by the central Arch score; the pool size IS
#                         the traffic budget (30 × 8.8 MB worst case), and score
#                         also filters by reliability, which --latest (freshness
#                         only, what this used to pass) does not.
#   --download-timeout 12 the default 5 s rates everything below ~1.8 MB/s as 0,
#                         so on an ordinary link the whole pool ties at zero and
#                         the ranking degenerates into API order. 12 s covers a
#                         ~0.75 MB/s link; a stalled host still burns at most
#                         12 s and sorts last.
#   --threads 4           30 serial probes ≈ 2 min; measured 28 s at 5 threads.
#                         Shared bandwidth compresses the rates — acceptable: the
#                         job here is excluding the dead, not benchmarking the
#                         live.
#   timeout 200           the previous 60 s wrapper could not fit 20 serial
#                         probes, so reflector was killed BEFORE --save and no
#                         ranking happened at all — the list silently stayed the
#                         ISO's. The new worst case is ~30/4 × 15 ≈ 113 s.
# Fail-soft: reflector never writes the live mirrorlist directly (a run killed by
# the timeout wrapper must not be able to truncate it), and a list too short to
# be useful is merged with the ISO's instead of replacing it.
mod_reflector() {
  command -v reflector &>/dev/null || return 0
  ui_info "Ranking mirrors (reflector)..."

  local tmp="/tmp/w-mirrorlist.$$" t0=$SECONDS n
  timeout 200 reflector --protocol https --age 12 --score 30 \
    --sort rate --number 20 --threads 4 \
    --connection-timeout 3 --download-timeout 12 \
    --verbose --save "$tmp" || true

  n=$(grep -c '^Server' "$tmp" 2>/dev/null || true); n=${n:-0}
  echo "MIRRORS: reflector ranked $n mirror(s) in $((SECONDS - t0))s"

  if (( n >= MIRRORS_MIN )); then
    cat "$tmp" > "$MIRRORLIST"
  elif (( n > 0 )); then
    # Ranked, but too shallow to survive a transaction on its own: keep it as the
    # head and re-append the ISO's own entries below it, deduplicated.
    { cat "$tmp"
      echo "# W: ISO mirrors kept below — reflector returned only $n"
      grep '^Server' "$MIRRORLIST" | grep -vxF -f "$tmp" || true
    } > "$tmp.merged"
    cat "$tmp.merged" > "$MIRRORLIST"
    echo "MIRRORS: list too shallow ($n < $MIRRORS_MIN) — ISO mirrors appended below it"
  else
    echo "MIRRORS: reflector produced nothing — keeping the ISO mirrorlist as is"
  fi
  rm -f "$tmp" "$tmp.merged"
}

# Pre-flight before pacstrap — installer.md §5. `pacstrap -K` is the one step with
# no room for error: it combines keyring init with the first transaction, so a
# network stall inside it surfaces as 23× "keyring is not writable" and reads as a
# cryptographic defect (that misreading is exactly what kept this filed as a
# "mysterious keyring flake" for years, see e2e-preset.md). So: probe the head of
# the list with a cheap core.db request, demote whoever does not answer, and put
# the reason in the log in plain words — the next post-mortem must not start from
# a keyring hypothesis again.
#
# The probe is throughput-checked, not merely time-limited: the observed failure
# was a host that connects instantly and then serves <1 byte/s. core.db is
# ~130 KB, so a live mirror is done well under a second; the 10 KB/s floor over a
# 5 s window catches the stalled host without punishing an honestly slow link.
# Fail-soft: a dead head is demoted to the bottom, never deleted (the list is
# inherited by the target — depth must not shrink), and if nothing in the head
# answers we proceed anyway, since by then the suspect is our own link.
mod_mirror_preflight() {
  command -v curl &>/dev/null || return 0
  ui_info "Verifying mirror availability..."

  local -a heads=() dead=()
  mapfile -t heads < <(grep '^Server' "$MIRRORLIST" 2>/dev/null | head -n "$MIRRORS_PROBE")
  (( ${#heads[@]} )) || return 0

  local line url probe host rc alive=0
  for line in "${heads[@]}"; do
    url="${line#*=}"; url="${url//[[:space:]]/}"
    probe="${url//\$repo/core}"; probe="${probe//\$arch/x86_64}"
    host="${url#*://}"; host="${host%%/*}"

    rc=0
    curl -sfL --connect-timeout 5 --max-time 20 --speed-limit 10240 --speed-time 5 \
      -o /dev/null "$probe/core.db" || rc=$?
    if (( rc == 0 )); then alive=1; break; fi

    dead+=("$line")
    echo "MIRRORS: mirror $host is not serving data (core.db probe, curl rc=$rc) — demoted to the bottom"
  done

  if (( ! alive )); then
    echo "MIRRORS: none of the first ${#heads[@]} mirrors served core.db — proceeding anyway (suspect the local link)"
  fi
  (( ${#dead[@]} )) || return 0

  local tmp="/tmp/w-mirrorlist-preflight.$$" pat="/tmp/w-mirrorlist-dead.$$"
  printf '%s\n' "${dead[@]}" > "$pat"
  { grep -vxF -f "$pat" "$MIRRORLIST" || true
    echo "# W: demoted by pre-flight — did not serve core.db"
    cat "$pat"
  } > "$tmp"
  cat "$tmp" > "$MIRRORLIST"
  rm -f "$tmp" "$pat"
}

# Pre-retry hook for the pacstrap seam. `pacstrap -K` only initialises the target
# keyring when the gnupg directory does NOT exist yet ([[ ! -d $newroot/$gpg_dir ]]
# in /usr/bin/pacstrap — read, not assumed). So an attempt that died after creating
# the directory but before the keyring was populated would make the RETRY skip the
# init entirely and fail again on "keyring is not writable" — the exact signature
# that had this class filed as a mysterious keyring flake for years. Dropping the
# directory costs a few seconds of key generation and makes the retry deterministic
# instead of dependent on which half of the first attempt survived.
_base_reset_target_keyring() {
  [[ -n "${MNT:-}" && -d "$MNT/etc/pacman.d/gnupg" ]] || return 0
  echo "PAC: dropping the target's half-built keyring so pacstrap -K re-initialises it"
  rm -rf "$MNT/etc/pacman.d/gnupg"
}

# Fault-injection point — dev/E2E only, a no-op everywhere else (installer.md §5 Ф.4).
#
# The position IS the design. Layer 1 has just finished: reflector ranked the real
# pool and the pre-flight probed its head, both leaving their MIRRORS: lines in the
# log as proof that selection saw healthy mirrors. Only after that does the
# transport go bad — which is the literal shape of the failure §5 exists for,
# "rated fine, stalled a minute later". Injecting anywhere earlier tests the wrong
# layer: before mod_reflector the entry is overwritten wholesale (the list is
# rebuilt from scratch), and between reflector and the pre-flight the pre-flight
# honestly demotes it, so the run would prove layer 1 works and say nothing about
# the layer it was written for.
#
# Two independent conditions, and the run is opt-in on both: the hook lives under
# devtools/ (never staged into the ISO by build-iso.sh) on the virtiofs share,
# which exists on a dev host's QEMU and physically nowhere else — the same guard
# .zlogin uses to decide this is an unattended dev run, and the same one
# w-firstboot's e2e_status runs on — AND the scenario file that only
# `vm/e2e.sh --fault-mirror` writes. A normal e2e run has the share but no
# scenario file, so it behaves byte-for-byte as before.
_W_FAULT_HOOK=/w-src/devtools/usr/local/bin/w-fault-arm
_W_FAULT_CONF=/w-src/vm/e2e/fault.conf

mod_fault_inject() {
  [[ -x "$_W_FAULT_HOOK" && -r "$_W_FAULT_CONF" ]] || return 0
  ui_info "E2E: arming the mirror fault..."
  "$_W_FAULT_HOOK" arm "$MIRRORLIST" "$_W_FAULT_CONF" \
    || echo "MIRRORS: fault injection hook failed — continuing with the real list"
}

# Undo the injection in the TARGET's copy of the list, right after pacstrap. The
# host side needs no undoing — during an install "the host" is the live ISO, whose
# /etc is tmpfs and evaporates on reboot — but the target's copy is the file the
# installed machine lives with forever (pacstrap copies it in once the packages
# land), and leaving twenty relay URLs in it would hand the next person a machine
# that cannot update. e2e-preset.md's rule: a test does not leave behind state it
# cannot restore. Restoring is a pure local transform — each entry still carries
# its own upstream — so it needs neither the relay nor the network, and the demoted
# ORDER the seam produced is preserved.
mod_fault_restore() {
  [[ -x "$_W_FAULT_HOOK" && -r "$_W_FAULT_CONF" ]] || return 0
  "$_W_FAULT_HOOK" restore "$MNT/etc/pacman.d/mirrorlist" \
    || echo "MIRRORS: could not un-arm the target mirrorlist"
}

mod_base() {
  mod_reflector
  mod_mirror_preflight
  mod_fault_inject

  local pkg_file; pkg_file="$(dirname "$INSTALL_ROOT")/packages/base.txt"
  [[ -f "$pkg_file" ]] || die "Package list not found: $pkg_file"

  local pkgs
  pkgs=$(grep -v '^\s*#' "$pkg_file" | grep -v '^\s*$' | tr '\n' ' ') || true

  # -K: initialise a fresh pacman keyring inside the target instead of copying the
  # live ISO's. A copied keyring is non-deterministic (depends on the ISO build's
  # keyring state) and can leave the target keyring unusable — later chroot installs
  # that download+verify packages (mod_limine: limine/sbctl/tpm2-tools on the
  # encrypted path) then fail with "keyring is not writable / required key missing".
  # The plain/GRUB path never hit this (grub is in the pacstrap set, no chroot -S).
  # Real progress bar driven by pacman's "( n/m )" counts (see progress.sh).
  #
  # Through the seam since Ф.4 (installer.md §5). Both roots are stated outright
  # rather than inherited: $MNT is set by now, but the transaction reads the HOST's
  # mirrorlist (pacstrap runs `pacman -r $newroot` under the host config and copies
  # the list into the target only AFTER the packages land), while the partial
  # downloads to clear between attempts live in the TARGET's cache, because pacstrap
  # points pacman's --cachedir there. Declared `local` so they unwind with the
  # function instead of leaking into the rest of the install.
  local W_PAC_SYSROOT="" W_PAC_CACHE_ROOT="$MNT" W_PAC_PRERETRY=_base_reset_target_keyring
  if declare -F progress_pacman >/dev/null; then
    w_run_retry pacstrap progress_pacman "$(t phase_base)" pacstrap -K "$MNT" $pkgs
  else
    clear
    echo -e "\033[1;35m  ── Installing base system ──\033[0m\n"
    w_run_retry pacstrap pacstrap -K "$MNT" $pkgs
    echo -e "\n\033[1;35m  ── Done ──\033[0m"
    sleep 1
  fi

  mod_fault_restore
}
