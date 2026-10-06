#!/usr/bin/env bash
# comfyui bundle — UPGRADE of the engine itself. Run by `w-pack upgrade` as root,
# after the plan was shown and confirmed, with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_OUTDATED (outdated.sh rows)  PACK_FORCE(0|1)
#
# The engine is a git checkout + venv that pacman never sees and refresh never
# rebuilds (setup.sh skips an existing workspace on purpose), so this is the one
# path that moves it. Upstream's own tool does the move —
# `comfy update comfy --version X` checks the release tag out and reinstalls
# requirements.txt, leaving torch alone — and W adds what makes it safe to press:
#   1. a busy engine is not cut off (unless --force), a running one is stopped;
#   2. a rollback point: the checkout's revision + `uv pip freeze` of the venv,
#      in $ROOT/.w-upgrade (one, the latest — the venv itself is 7-10 GB, its
#      exact package list is kilobytes and the wheels sit in the uv/pip caches);
#   3. setup.sh replayed against the new tree — it re-syncs ComfyUI-Manager to the
#      version pinned next to the new release (manager_requirements.txt);
#   4. proof: torch is still the build the machine was given (a requirements bump
#      resolved from plain PyPI would be the CUDA build — wrong on AMD/CPU), and
#      the engine starts and reports the target version on /system_stats;
#   5. on failure: the journal tail, the old revision + the frozen package set
#      back, the same proof against the old version.
# The service is left running only if it was running before.
#
# Custom nodes are NOT upgraded: they are the user's, and ComfyUI-Manager in the
# web interface owns them (Manager → Update All). The rollback only catches "the
# engine does not start", not "node X stopped working" — said at the end.

set -uo pipefail

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }
fail() { echo -e "  \033[1;31mERROR:\033[0m $*" >&2; }

target="$(awk -F'\t' '$1=="ComfyUI" {print $3}' <<< "${PACK_OUTDATED:-}")"
[[ -n "$target" && "$target" != unknown ]] || { fail "no target version in the plan."; exit 1; }

source /usr/lib/w/w-conf-lib.sh
wconf_load comfyui
LISTEN="$(wconf_get comfyui LISTEN 127.0.0.1)"
PORT="$(wconf_get comfyui PORT 8188)"
case "$LISTEN" in 0.0.0.0|::|'') LISTEN=127.0.0.1 ;; esac
URL="http://$LISTEN:$PORT"

# The RUNNING layout, not w-conf's: see outdated.sh.
APP="$(systemctl show -P WorkingDirectory comfyui.service)"
ROOT="${APP%/app}"
PY="$APP/.venv/bin/python"
COMFY="$ROOT/.local/bin/comfy"
SNAP="$ROOT/.w-upgrade"
SVC=comfyui.service
[[ -x "$PY" && -x "$COMFY" ]] || { fail "no ComfyUI workspace at $APP — install it first: sudo w-pack refresh comfyui"; exit 1; }

run_as_comfy() {
  ( cd "$ROOT" && runuser -u comfyui -- env HOME="$ROOT" PATH="$ROOT/.local/bin:/usr/local/bin:/usr/bin:/bin" \
      DO_NOT_TRACK=1 COMFY_NO_TELEMETRY=1 "$@" )
}
version_of() { sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$APP/comfyui_version.py" 2>/dev/null; }
torch_of() {   # installed torch version, read off the dist-info name — no import
  local d; d="$(compgen -G "$APP/.venv/lib/python3*/site-packages/torch-*.dist-info" | head -n1)"
  d="${d##*/torch-}"; echo "${d%.dist-info}"
}
replay_setup() { info "Replaying the pack's machine setup (warnings only)..."; bash "$BUNDLE_DIR/setup.sh" >/dev/null; }

# Started and answering with the expected version within the cold-start budget
# (torch import + frontend unpack; minutes on a CPU). A crash loop shows up as
# NRestarts > 0 long before the budget runs out.
healthy() {                                             # <expected version>
  local i got
  systemctl reset-failed "$SVC" 2>/dev/null
  systemctl start "$SVC" || return 1
  for ((i = 0; i < 300; i += 3)); do
    got="$(curl -fsS -m 3 "$URL/system_stats" 2>/dev/null | jq -r '.system.comfyui_version // empty' 2>/dev/null)"
    if [[ -n "$got" ]]; then
      [[ "$got" == "$1" ]] && return 0
      warn "the engine answers as $got, expected $1."; return 1
    fi
    [[ "$(systemctl show -P NRestarts "$SVC")" == 0 ]] || return 1
    systemctl is-active --quiet "$SVC" || [[ "$(systemctl show -P ActiveState "$SVC")" == activating ]] || return 1
    sleep 3
  done
  warn "no answer on $URL within 300 s."; return 1
}

# ── 1. A busy engine is not cut off ───────────────────────────────────────────
was_active=0
if systemctl is-active --quiet "$SVC"; then
  was_active=1
  busy="$(curl -fsS -m 5 "$URL/queue" 2>/dev/null | jq '(.queue_running | length) + (.queue_pending | length)' 2>/dev/null)"
  if [[ "${busy:-0}" -gt 0 && "${PACK_FORCE:-0}" != 1 ]]; then
    fail "ComfyUI is generating ($busy job(s) in the queue) — let it finish, or re-run with --force."
    exit 1
  fi
  info "Stopping $SVC..."
  systemctl stop "$SVC"
fi
restore_state() { [[ $was_active -eq 1 ]] || systemctl stop "$SVC"; }

# ── 2. Rollback point ─────────────────────────────────────────────────────────
old_ver="$(version_of)"; old_torch="$(torch_of)"
old_rev="$(run_as_comfy git -C "$APP" rev-parse HEAD 2>/dev/null)"
info "Recording the rollback point ($old_ver, $(cut -c1-12 <<< "$old_rev")) in $SNAP..."
rm -rf "$SNAP"; install -d -o comfyui -g comfyui -m 0700 "$SNAP"   # the restore runs as comfyui
run_as_comfy uv pip freeze --python "$PY" > "$SNAP/freeze.txt" 2>/dev/null
echo "$old_rev" > "$SNAP/rev"
if [[ -z "$old_rev" || ! -s "$SNAP/freeze.txt" ]]; then
  fail "could not record the rollback point — nothing was changed."
  [[ $was_active -eq 1 ]] && systemctl start "$SVC"
  exit 1
fi
# torch's local version tag IS the build (+rocm7.2, +cu128, +cpu, +xpu) and the
# --torch-backend a restore must fetch it from; none means plain PyPI.
backend=""; [[ "$old_torch" == *+* ]] && backend="--torch-backend=${old_torch#*+}"

# ── 3. The move ───────────────────────────────────────────────────────────────
ok=1
info "Updating comfy-cli..."
run_as_comfy uv tool upgrade comfy-cli || warn "comfy-cli upgrade failed — moving with the installed one."
info "Moving ComfyUI $old_ver → $target..."
run_as_comfy "$COMFY" --skip-prompt --workspace "$APP" update comfy --version "$target" || ok=0
[[ $ok -eq 1 ]] && { replay_setup || ok=0; }

# ── 4. Proof ──────────────────────────────────────────────────────────────────
if [[ $ok -eq 1 && "$(torch_of)" != "$old_torch" ]]; then
  warn "torch moved from $old_torch to $(torch_of) — not the build this machine was set up with."
  ok=0
fi
if [[ $ok -eq 1 ]]; then
  info "Starting the new version and waiting for it to answer..."
  healthy "$target" || ok=0
fi
if [[ $ok -eq 1 ]]; then
  restore_state
  info "ComfyUI $target is ready (rollback point for $old_ver kept in $SNAP until the next upgrade)."
  info "Custom nodes were not touched — update them in the web interface: Manager → Update All."
  info "If a node misbehaves on the new version: sudo w-conf set comfyui VERSION $old_ver && sudo w-pack upgrade comfyui"
  exit 0
fi

# ── 5. Rollback ───────────────────────────────────────────────────────────────
journalctl -u "$SVC" -n 25 --no-pager -o cat 2>/dev/null | sed 's/^/    /' >&2
fail "ComfyUI $target did not come up — putting $old_ver back."
systemctl stop "$SVC" 2>/dev/null
# shellcheck disable=SC2086 # $backend is one flag or nothing
if run_as_comfy git -C "$APP" checkout -q "$old_rev" \
   && run_as_comfy uv pip sync --python "$PY" $backend "$SNAP/freeze.txt" \
   && replay_setup && healthy "$old_ver"; then
  restore_state
  fail "rolled back: ComfyUI $old_ver runs as before. Nothing else changed."
else
  restore_state
  fail "the rollback did not come up either. A clean rebuild keeps models and outputs (it installs comfyui.VERSION):"
  fail "    sudo rm -rf $APP && sudo w-pack refresh comfyui"
fi
exit 1
