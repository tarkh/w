# w-priv-lib.sh — W Linux administrator check (shared, sourced).
#
# One definition of "administrator" for every W front-end that escalates:
# membership in the `wheel` group. That is not a new W concept — it is what
# %wheel in sudoers grants and what polkit's Arch default (unix-group:wheel)
# already treats as an admin, so the answer here matches what sudo/polkit will
# decide a moment later.
#
# WHY it exists: on a multi-user machine a non-admin who runs `w-sync update` or
# `w-update` used to hit a raw `sudo: user is not in the sudoers file` (or, via
# the AI path, a polkit prompt they cannot answer). Both are true refusals but
# neither explains anything. W checks first and says so in one sentence.
#
# NOT a security boundary. The real gate stays sudo/polkit — this only decides
# whether it is worth reaching for it. Hence the deliberate FAIL-OPEN below: an
# odd machine with no `wheel` group falls back to today's behaviour (let the real
# gate answer) instead of locking everyone out of the updater. Its Python twin
# lives in w-mcp/core.py (_is_admin), guarding _actuate() for the AI path.

# Is <user> (default: the caller) an administrator? root always is.
w_is_admin() {
  local u="${1:-}"
  if [[ -z "$u" ]]; then
    [[ "$EUID" -eq 0 ]] && return 0
    u="$(id -un 2>/dev/null)" || return 0    # unknown caller → let sudo/polkit answer
  fi
  [[ "$u" == root ]] && return 0
  # No wheel group at all → fail open (see header).
  getent group wheel >/dev/null 2>&1 || return 0
  id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx wheel
}

# The refusal text, shared so the three CLI fronts cannot drift apart.
# <action> reads as the subject of "requires administrator rights", e.g.
# "updating W", "upgrading packages", "installing a pack".
w_admin_msg() {
  printf '%s requires administrator rights — user '\''%s'\'' is not in the '\''wheel'\'' group. Ask a system administrator of this machine to run it.' \
    "$1" "$(id -un 2>/dev/null || echo '?')"
}
