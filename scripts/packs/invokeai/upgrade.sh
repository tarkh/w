#!/usr/bin/env bash
# invokeai bundle — UPGRADE of the engine itself. Run by `w-pack upgrade` as root,
# after the plan was shown and confirmed, with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_OUTDATED (outdated.sh rows)  PACK_FORCE(0|1)
#
# Upstream's upgrade is the manual install again with a version:
# `uv pip install --torch-backend=<be> invokeai==X` into the same venv. setup.sh
# never does that over an existing venv (refresh must not), so this is the one
# path that moves it, with what makes it safe to press — the comfyui pack's
# sequence, adapted to InvokeAI's two differences:
#   * the torch backend is read off the INSTALLED build (+rocm7.2, +cu128, …),
#     never re-detected: the upgrade keeps whatever the machine was given, and
#     InvokeAI pins torch per release, so the backend is what makes a torch
#     change come from the right index;
#   * the database migrates forward on the first start of the new version, one
#     way. InvokeAI backs it up itself before migrating, but a rollback needs the
#     copy that belongs to THIS attempt — taken here, with the service stopped
#     (no WAL in flight), and put back together with the old package set.
# The rest: a busy engine is not cut off (unless --force); the rollback point
# ($ROOT/.w-upgrade: `uv pip freeze` + the database) is one, the latest;
# setup.sh is replayed (PatchMatch is rebuilt if the new pypatchmatch dropped
# the .so); the new version must start and report itself on /api/v1/app/version,
# or the old one goes back. The service is left running only if it was before.

set -uo pipefail

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }
fail() { echo -e "  \033[1;31mERROR:\033[0m $*" >&2; }

target="$(awk -F'\t' '$1=="InvokeAI" {print $3}' <<< "${PACK_OUTDATED:-}")"
[[ -n "$target" && "$target" != unknown ]] || { fail "no target version in the plan."; exit 1; }

source /usr/lib/w/w-conf-lib.sh
wconf_load invokeai
LISTEN="$(wconf_get invokeai LISTEN 127.0.0.1)"
PORT="$(wconf_get invokeai PORT 9090)"
case "$LISTEN" in 0.0.0.0|::|'') LISTEN=127.0.0.1 ;; esac
URL="http://$LISTEN:$PORT"

# The RUNNING layout, not w-conf's: see outdated.sh.
DATA="$(systemctl show -P WorkingDirectory invokeai.service)"
ROOT="${DATA%/data}"
VENV="$ROOT/app/.venv"
DB="$DATA/databases"
SNAP="$ROOT/.w-upgrade"
SVC=invokeai.service
[[ -x "$VENV/bin/invokeai-web" ]] || { fail "no InvokeAI venv at $VENV — install it first: sudo w-pack refresh invokeai"; exit 1; }

run_as_invoke() {
  ( cd "$ROOT" && runuser -u invokeai -- env HOME="$ROOT" PATH="/usr/bin:/bin" "$@" )
}
dist_version() {                                        # <dist> → version from the dist-info name
  local d; d="$(compgen -G "$VENV/lib/python3*/site-packages/$1-*.dist-info" | head -n1)"
  d="${d##*/"$1"-}"; echo "${d%.dist-info}"
}
replay_setup() { info "Replaying the pack's machine setup (warnings only)..."; bash "$BUNDLE_DIR/setup.sh" >/dev/null; }

# `systemctl start` returns once ExecStartPost saw the port answer (the store
# sync waits for it), so the version check right after is the proof. A crash
# loop shows up as NRestarts > 0.
healthy() {                                             # <expected version>
  local got
  systemctl reset-failed "$SVC" 2>/dev/null
  systemctl start "$SVC" || return 1
  [[ "$(systemctl show -P NRestarts "$SVC")" == 0 ]] || return 1
  got="$(curl -fsS -m 10 "$URL/api/v1/app/version" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)"
  [[ "$got" == "$1" ]] && return 0
  warn "the engine answers as '${got:-nothing}', expected $1."; return 1
}

# ── 1. A busy engine is not cut off ───────────────────────────────────────────
was_active=0
if systemctl is-active --quiet "$SVC"; then
  was_active=1
  busy="$(curl -fsS -m 5 "$URL/api/v1/queue/default/status" 2>/dev/null | jq '.queue.in_progress + .queue.pending' 2>/dev/null)"
  if [[ "${busy:-0}" -gt 0 && "${PACK_FORCE:-0}" != 1 ]]; then
    fail "InvokeAI is generating ($busy item(s) in the queue) — let it finish, or re-run with --force."
    exit 1
  fi
  info "Stopping $SVC..."
  systemctl stop "$SVC"
fi
restore_state() { [[ $was_active -eq 1 ]] || systemctl stop "$SVC"; }

# ── 2. Rollback point ─────────────────────────────────────────────────────────
old_ver="$(dist_version invokeai)"; torch="$(dist_version torch)"
if [[ "$torch" != *+* ]]; then
  fail "cannot tell which torch build this venv carries ($torch) — nothing was changed."
  [[ $was_active -eq 1 ]] && systemctl start "$SVC"
  exit 1
fi
backend="${torch#*+}"
info "Recording the rollback point ($old_ver + database) in $SNAP..."
rm -rf "$SNAP"; install -d -o invokeai -g invokeai -m 0700 "$SNAP"   # the restore runs as invokeai
run_as_invoke uv pip freeze --python "$VENV/bin/python" > "$SNAP/freeze.txt" 2>/dev/null
if [[ ! -s "$SNAP/freeze.txt" ]] || { [[ -d "$DB" ]] && ! cp -a "$DB" "$SNAP/databases"; }; then
  fail "could not record the rollback point — nothing was changed."
  [[ $was_active -eq 1 ]] && systemctl start "$SVC"
  exit 1
fi

# ── 3. The move ───────────────────────────────────────────────────────────────
ok=1
info "Moving InvokeAI $old_ver → $target (torch backend: $backend)..."
run_as_invoke uv pip install --python "$VENV/bin/python" --python-preference only-managed \
  --torch-backend="$backend" "invokeai==$target" || ok=0
[[ $ok -eq 1 ]] && { replay_setup || ok=0; }

# ── 4. Proof ──────────────────────────────────────────────────────────────────
if [[ $ok -eq 1 ]]; then
  info "Starting the new version and waiting for it to answer (the first start migrates the database)..."
  healthy "$target" || ok=0
fi
if [[ $ok -eq 1 ]]; then
  restore_state
  info "InvokeAI $target is ready (torch $(dist_version torch); rollback point for $old_ver kept in $SNAP until the next upgrade)."
  info "If something misbehaves on the new version: sudo w-conf set invokeai VERSION $old_ver && sudo w-pack upgrade invokeai"
  info "  (going back that way keeps the NEW database, which an older InvokeAI may refuse — the copy in $SNAP/databases is the one that matches $old_ver)."
  exit 0
fi

# ── 5. Rollback ───────────────────────────────────────────────────────────────
journalctl -u "$SVC" -n 25 --no-pager -o cat 2>/dev/null | sed 's/^/    /' >&2
fail "InvokeAI $target did not come up — putting $old_ver back."
systemctl stop "$SVC" 2>/dev/null
restore_db() { [[ -d "$SNAP/databases" ]] || return 0; rm -rf "$DB" && cp -a "$SNAP/databases" "$DB"; }
if run_as_invoke uv pip sync --python "$VENV/bin/python" --python-preference only-managed \
     --torch-backend="$backend" "$SNAP/freeze.txt" \
   && restore_db && replay_setup && healthy "$old_ver"; then
  restore_state
  fail "rolled back: InvokeAI $old_ver runs as before, with its database as it was."
else
  restore_state
  fail "the rollback did not come up either. The database copy is in $SNAP/databases; a clean venv:"
  fail "    sudo rm -rf $VENV && sudo w-pack refresh invokeai"
fi
exit 1
