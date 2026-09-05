# check/pam.sh — the polkit-1 password chain is a PINNED COPY, not an include.
#
# /etc/pam.d/polkit-1 deliberately does not `include system-auth` for its auth
# phase: a cancelled W auth card must not count as a failed login attempt
# (polkit ≥126 keeps the socket-activated helper alive past the cancel, pam_unix
# answers the dead socket with PAM_AUTHTOK_ERR — the code pam_get_authtok()
# maps a dead prompt to — and upstream's `default=bad` hands that to
# pam_faillock authfail; three dismissed cards locked the password prompt for
# ten minutes; measured, see quickshell-auth.md). The price of the
# copy is drift: pambase can change system-auth under us and the copy would
# silently stop following it. This suite turns that silence into a red gate:
#
#   1. the copied block in rootfs/etc/pam.d/polkit-1 must equal the pinned
#      snapshot (tests/fixtures/system-auth.auth) modulo EXACTLY one inserted
#      pair of tokens — `authtok_err=die conv_err=die` on pam_unix — so nobody
#      can "improve" the chain without touching the snapshot too;
#   2. the rest of the stack (gate, pam_fprintd, account/session includes) must
#      still be there, and the very `auth include system-auth` line the copy
#      replaced must NOT come back;
#   3. on a machine with a live /etc/pam.d/system-auth (Arch dev host; the file
#      is absent on macOS/pambase-less CI), its sha256 must equal the pinned
#      one — a pambase update that touches system-auth fails the gate here
#      first, with the refresh procedure living in the fixture header.
#
# Whitespace inside the compared lines is squeezed before comparison: the delta
# that matters is tokens (module, arguments, control actions), not column
# alignment.

# One line, internal blanks squeezed to single spaces (newline-safe: only
# [:blank:] is squeezed, not [:space:] — the latter would eat the separator).
_pam_squeeze() { # <line>
  printf '%s\n' "$1" | tr -s '[:blank:]' ' ' | sed 's/^ //;s/ $//'
}

# Module lines of the copied block in our stack: the contiguous auth-phase run
# from the faillock preauth line through authsucc (the gate and pam_fprintd
# lines before it are W-specific and excluded on purpose).
_pam_our_block() {
  sed -n '/^auth[[:space:]].*pam_faillock\.so[[:space:]]*preauth/,/^auth[[:space:]].*pam_faillock\.so[[:space:]]*authsucc/p' \
    rootfs/etc/pam.d/polkit-1 | grep -E '^(auth|-auth)' | while IFS= read -r l; do _pam_squeeze "$l"; done
}

# Module lines of the pinned snapshot (its leading comments are provenance).
_pam_fixture_block() {
  grep -E '^(auth|-auth)' scripts/check/tests/fixtures/system-auth.auth | while IFS= read -r l; do _pam_squeeze "$l"; done
}

chk_pam() {
  local rc=0 i

  # 1. The copy matches the snapshot modulo exactly one inserted token.
  local -a ours theirs
  mapfile -t ours < <(_pam_our_block)
  mapfile -t theirs < <(_pam_fixture_block)
  if (( ${#ours[@]} != ${#theirs[@]} || ${#theirs[@]} == 0 )); then
    printf '  auth chain has %d module lines, pinned snapshot has %d\n' \
      "${#ours[@]}" "${#theirs[@]}"
    return 1
  fi
  for i in "${!theirs[@]}"; do
    local want=${theirs[i]}
    if [[ $want == *"pam_unix.so"* ]]; then
      # The one allowed delta: two "conversation is dead, fail without
      # tallying" tokens inserted into the control field. authtok_err is the
      # code pam_get_authtok() actually maps a dead prompt to (measured);
      # conv_err is the belt for raw propagations.
      want=${want/\[success=1 /\[success=1 authtok_err=die conv_err=die }
    fi
    if [[ ${ours[i]:-} != "$want" ]]; then
      printf '  auth chain line %d deviates from the pinned snapshot:\n    ours: %s\n    want: %s\n' \
        $((i + 1)) "${ours[i]:-<missing>}" "$want"
      rc=1
    fi
  done

  # 2. The rest of the stack is intact — the W-specific front, the untouched
  #    phases, and no return of the include this copy replaced.
  local -a must=(
    'auth [success=ignore default=1] pam_exec.so quiet /usr/lib/w/w-fp-gate'
    'auth sufficient pam_fprintd.so'
    'account include system-auth'
    'session include system-auth'
  )
  local -a squeezed
  mapfile -t squeezed < <(sed 's/#.*//' rootfs/etc/pam.d/polkit-1 \
    | grep -v '^[[:space:]]*$' | while IFS= read -r l; do _pam_squeeze "$l"; done)
  local want found
  for want in "${must[@]}"; do
    found=0
    for i in "${!squeezed[@]}"; do
      [[ ${squeezed[i]} == "$want" ]] && { found=1; break; }
    done
    if (( ! found )); then
      printf '  stack lost a required line: %s\n' "$want"
      rc=1
    fi
  done
  if grep -qE '^auth[[:space:]]+include[[:space:]]+system-auth' rootfs/etc/pam.d/polkit-1; then
    printf '  auth phase is an include again — the copy (and its conv_err=die fix) is gone\n'
    rc=1
  fi

  # 3. Live drift sensor: where a real system-auth exists, it must still be the
  #    pambase state we pinned. (macOS and pambase-less CI have no such file —
  #    the fixture invariant above is all they can run.)
  local live=/etc/pam.d/system-auth
  if [[ -r $live ]]; then
    local pinned livehash
    pinned=$(sed 's/^#[[:space:]]*//' scripts/check/tests/fixtures/system-auth.auth \
      | grep -oE '^[a-f0-9]{64}$' | tail -1)
    livehash=$({ sha256sum "$live" 2>/dev/null || shasum -a 256 "$live"; } | awk '{print $1}')
    if [[ $livehash != "$pinned" ]]; then
      printf '  live /etc/pam.d/system-auth drifted from the pinned snapshot (pambase updated?)\n    pinned: %s\n    live:   %s\n    refresh BOTH the fixture and the polkit-1 copy — procedure in the fixture header\n' \
        "$pinned" "$livehash"
      rc=1
    fi
  else
    printf '  note: no live /etc/pam.d/system-auth (non-Arch/pambase-less) — fixture invariant only\n'
  fi

  return $rc
}
