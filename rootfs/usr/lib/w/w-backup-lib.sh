# w-backup-lib.sh — W's safety copies, taken before a destructive config change.
#
# One rule, shared by every tool that overwrites or deletes a config file W owns:
# THE BACKUP FOLLOWS THE OWNER OF THE DATA. A tool acts on a user's behalf, so a
# home path is copied into that user's own state dir (and ends up user-owned) even
# when root is the one running the command; system paths go under /var/lib/w,
# which is root's. One invocation may touch both, so the two roots are created
# lazily, per path — a run that never leaves the home says nothing about /var/lib.
#
# Extracted from w-reset when `w-pack remove` needed exactly the same primitive:
# both hand a user their files back before removing them, and two copies of this
# reasoning would be two ways to get the ownership wrong.
#
# The system root keeps the name `reset-backups` although it is no longer only
# w-reset's: w-conf-lib and w-power already drop their one-off pre-migration
# copies there, and the AI's w-maintenance skill documents it as THE place W puts
# safety copies. A second root would be a second place to look during a recovery.
#
# Usage:
#   source /usr/lib/w/w-backup-lib.sh
#   w_backup_init "$TARGET_USER" "$TARGET_HOME"   # once, before any w_backup_path
#   w_backup_path /etc/w/env.d/dev.sh             # no-op if the path is absent
#   w_backup_finalize                             # hand the home tree to its owner
#   w_backup_summary                              # print whichever roots were used
#
# The caller owns the decision of WHAT to back up; this file only answers where it
# lands and who ends up owning it.

W_BACKUP_SYS_ROOT="${W_BACKUP_SYS_ROOT:-/var/lib/w/reset-backups}"
W_BACKUP_HOME_REL="${W_BACKUP_HOME_REL:-.local/state/w/reset-backups}"

W_BK_TS=""; W_BK_USER=""; W_BK_HOME=""; W_BK_HOME_DIR=""; W_BK_SYS_DIR=""

# w_backup_init <user> <home> — start one timestamped backup generation. Both
# arguments may be empty for a caller that only ever touches system paths.
w_backup_init() {
  W_BK_TS="$(date +%Y%m%d-%H%M%S)"
  W_BK_SYS_DIR=""
  w_backup_target "${1:-}" "${2:-}"
}

# w_backup_target <user> <home> — point the home half at a different account
# WITHOUT starting a new generation, so one `w-pack remove` walking every account
# that has a bundle leaves one timestamp across all of their homes and /var/lib,
# instead of a fresh one per account. Call w_backup_finalize before switching: it
# hands the tree just written to the account it belongs to.
w_backup_target() {
  W_BK_USER="${1:-}"; W_BK_HOME="${2:-}"
  W_BK_HOME_DIR=""
}

_w_backup_ensure_home() {
  [[ -n "$W_BK_HOME_DIR" ]] && return 0
  [[ -n "$W_BK_HOME" ]] || return 1
  # Own each parent from the home root down, so a root-run backup never leaves a
  # root-owned .local/state/w behind (the trap the deploy SDK guards).
  local acc="$W_BK_HOME" part
  local IFS=/
  for part in $W_BACKUP_HOME_REL "$W_BK_TS"; do
    acc="$acc/$part"
    if [[ $EUID -eq 0 && -n "$W_BK_USER" ]]; then install -d -o "$W_BK_USER" -g "$W_BK_USER" "$acc"
    else install -d "$acc"; fi
  done
  unset IFS
  W_BK_HOME_DIR="$W_BK_HOME/$W_BACKUP_HOME_REL/$W_BK_TS"
}

_w_backup_ensure_sys() {
  [[ -n "$W_BK_SYS_DIR" ]] && return 0
  W_BK_SYS_DIR="$W_BACKUP_SYS_ROOT/$W_BK_TS"
  mkdir -p "$W_BK_SYS_DIR"
}

# w_backup_path <abs-path> — snapshot the current version (file, dir or symlink)
# if it exists. Absent path = nothing to preserve, which is a success.
w_backup_path() {
  local p="$1" dest
  [[ -e "$p" || -L "$p" ]] || return 0
  if [[ -n "$W_BK_HOME" && "$p" == "$W_BK_HOME"/* ]]; then
    _w_backup_ensure_home || return 1
    dest="$W_BK_HOME_DIR/${p#"$W_BK_HOME"/}"
  else
    _w_backup_ensure_sys
    dest="$W_BK_SYS_DIR/${p#/}"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$p" "$dest"
}

# Hand the home backup tree to the user (root-run copies inherit their source's
# owner, but the intermediate dirs mkdir -p created above are root-owned).
w_backup_finalize() {
  [[ $EUID -eq 0 && -n "$W_BK_HOME_DIR" && -n "$W_BK_USER" ]] \
    && chown -R "$W_BK_USER:$W_BK_USER" "$W_BK_HOME_DIR" || true
}

# Report where backups landed (either or both roots may be unused). Ends with an
# explicit `return 0` — a trailing `[[…]] && echo` that goes false would otherwise
# return 1 and trip `set -e` in the caller.
w_backup_summary() {
  [[ -n "$W_BK_HOME_DIR" ]] && echo "  home backup:   $W_BK_HOME_DIR"
  [[ -n "$W_BK_SYS_DIR"  ]] && echo "  system backup: $W_BK_SYS_DIR"
  return 0
}
