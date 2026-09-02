#!/usr/bin/env bash
# scripts/test.sh — W development-automation orchestrator (release gate).
#
# Single entry point that chains the project's existing verification stages into
# one run and one machine-readable verdict — the materialisation of the release
# gate recipe in .claude/library/e2e-preset.md. The same script serves a human,
# a Claude /x-test session, a git hook and a future CI job (zero duplicated
# logic: every stage delegates to its own established entry point).
#
#   0. static  scripts/check.sh              static analysis + bats units (fast)
#   1. iso     scripts/build-iso.sh          fresh W ISO (e2e installs from it)
#   2. plain   vm/e2e.sh                      unattended install: btrfs + GRUB
#   3. crypt   vm/e2e.sh --encrypted          unattended install: LUKS2+Limine+TPM2
#   4. logscan journal-err of each phase's diag bundle (review, not a gate)
#
# Static is cross-platform and always runs. The e2e phases need Arch + KVM; on
# any other host they are recorded SKIP (not FAIL) so `--lint-only`-class use
# still works anywhere. Each phase's log + diag bundles are archived under
# vm/logs/x-test-<ts>/, and a summary.txt (KEY=value) is written there for the
# /x-test skill to parse.
#
# Usage:
#   bash scripts/test.sh                 # full gate: static → iso → plain → crypt → logscan
#   bash scripts/test.sh --lint-only     # static only (seconds; anywhere)
#   bash scripts/test.sh --no-iso        # reuse newest archiso/out/*.iso, skip the build
#   bash scripts/test.sh --plain-only    # static → iso → plain   (skip encrypted)
#   bash scripts/test.sh --encrypted-only# static → iso → crypt   (skip plain)
#   bash scripts/test.sh --fault-mirror  # + the Ф.4 stalled-mirror scenario in e2e
#
# Exit: 0 only if every executed gate phase passed. Log-scan findings never fail
# the run — they surface known-benign install-time races for a human/AI to judge.
#
# NOTE: deliberately not `set -e` — phase failures are captured explicitly so a
# summary is always produced, even when an early phase fails.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC" || exit 2

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; NC='\033[0m'
info() { echo -e "${MAGENTA}==>${NC} $*"; }
ok()   { echo -e "${GREEN} ok${NC} $*"; }
warn() { echo -e "${YELLOW}skip${NC} $*"; }
bad()  { echo -e "${RED}FAIL${NC} $*"; }
die()  { bad "$*"; exit 2; }

# ── Arguments ─────────────────────────────────────────────────────────────────
DO_ISO=1; DO_PLAIN=1; DO_CRYPT=1; LINT_ONLY=0
E2E_EXTRA=()
for arg in "$@"; do
  case "$arg" in
    --lint-only)      LINT_ONLY=1 ;;
    --fault-mirror)   E2E_EXTRA+=(--fault-mirror) ;;
    --no-iso)         DO_ISO=0 ;;
    --plain-only)     DO_CRYPT=0 ;;
    --encrypted-only) DO_PLAIN=0 ;;
    -h|--help)
      sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "unknown argument: $arg (see --help)" ;;
  esac
done
if (( LINT_ONLY )); then DO_ISO=0; DO_PLAIN=0; DO_CRYPT=0; fi

# ── Run directory + summary ───────────────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$SRC/vm/logs/x-test-$TS"
mkdir -p "$RUN_DIR"
SUMMARY="$RUN_DIR/summary.txt"

# Phase state (name → PASS|FAIL|SKIP) and durations, preserving insertion order.
declare -A ST=() DUR=()
ORDER=()
set_state() { ST["$1"]="$2"; ORDER+=("$1"); }

# ── Host capability probe (Arch + KVM for the e2e phases) ─────────────────────
kvm_ready=1; kvm_why=""
[[ "$(uname -s)" == Linux ]] || { kvm_ready=0; kvm_why="not Linux"; }
[[ -e /dev/kvm ]]            || { kvm_ready=0; kvm_why="${kvm_why:-/dev/kvm missing}"; }
command -v qemu-system-x86_64 &>/dev/null || { kvm_ready=0; kvm_why="${kvm_why:-qemu missing}"; }

# ── Phase runner ──────────────────────────────────────────────────────────────
# run_phase <name> <logfile> <cmd...> : run the delegate, sending ALL of its
# verbose output to <log> only — stdout carries just the compact phase status
# lines below. This keeps the run cheap for a backgrounded AI consumer (the
# whole stdout buffer stays a few dozen lines; the firehose lives in files),
# while a human still gets phase-level progress and can `tail -f` the log.
run_phase() {
  local name="$1" log="$2"; shift 2
  local start rc
  info "phase [$name]: $*  (verbose → $log)"
  start=$SECONDS
  "$@" > "$log" 2>&1
  rc=$?
  DUR["$name"]=$(( SECONDS - start ))
  if [[ $rc -eq 0 ]]; then
    set_state "$name" PASS; ok "[$name] passed (${DUR[$name]}s)"
  else
    set_state "$name" FAIL; bad "[$name] failed rc=$rc (${DUR[$name]}s)"
  fi
  return $rc
}

# Snapshot diag bundles produced since <sentinel> into the run dir under <name>.
archive_diags() {
  local name="$1" sentinel="$2"
  local dest="$RUN_DIR/$name"
  mkdir -p "$dest"
  local found=0 f
  while IFS= read -r -d '' f; do
    cp "$f" "$dest/" && found=1
  done < <(find "$SRC/vm/logs" -maxdepth 1 -name 'diag-*.tar.gz' -newer "$sentinel" -print0 2>/dev/null)
  # Also grab the mirrored install log for the record (newest since sentinel).
  find "$SRC/vm/logs" -maxdepth 1 -name 'w-install-*.log' -newer "$sentinel" \
    -exec cp {} "$dest/" \; 2>/dev/null || true
  (( found )) || echo "(no diag bundle captured for $name)" > "$dest/NO-DIAG.txt"
}

# Non-gating log review: scan each phase's diag bundles for error/fail lines
# across the journal AND the installer's own /var/log/w logs (install / apply /
# firstboot) — "collect and analyse everything, just in case". A per-source
# breakdown goes to logscan.txt and a total to the summary for a human/AI to
# judge; benign install-time races (dbus/resolve1) are expected here, so this
# never fails the gate.
scan_logs() {
  local name="$1"
  local dest="$RUN_DIR/$name"
  [[ -d "$dest" ]] || { echo "logscan.$name.errors=n/a" >> "$SUMMARY"; return; }
  local sources=(journal-err.txt install.log apply.log firstboot.log)
  local tb src errs n total=0
  for tb in "$dest"/diag-*.tar.gz; do
    [[ -f "$tb" ]] || continue
    for src in "${sources[@]}"; do
      errs="$(tar -xzOf "$tb" --wildcards "*/$src" 2>/dev/null | grep -inE 'error|fail' || true)"
      [[ -n "$errs" ]] || continue
      n=$(printf '%s\n' "$errs" | grep -c .)
      total=$(( total + n ))
      { echo "--- [$name] $src: $n error/fail line(s) (from $(basename "$tb")) ---"
        printf '%s\n' "$errs" | head -12; echo; } >> "$RUN_DIR/logscan.txt"
    done
  done
  echo "logscan.$name.errors=$total" >> "$SUMMARY"
  if (( total )); then
    warn "[logscan:$name] $total error/fail line(s) across journal + /var/log/w — review $RUN_DIR/logscan.txt"
  else
    ok "[logscan:$name] no error/fail lines"
  fi
}

# ── Phase 0: static ───────────────────────────────────────────────────────────
run_phase static "$RUN_DIR/static.log" bash "$SRC/scripts/check.sh"
if [[ "${ST[static]}" == FAIL ]]; then
  info "static gate failed — stopping before the expensive phases."
  DO_ISO=0; DO_PLAIN=0; DO_CRYPT=0
fi

# ── Guard: e2e phases require Arch + KVM ──────────────────────────────────────
if (( DO_PLAIN || DO_CRYPT )) && (( ! kvm_ready )); then
  warn "e2e phases skipped: $kvm_why (Arch + KVM host required)."
  (( DO_PLAIN )) && set_state plain SKIP
  (( DO_CRYPT )) && set_state crypt SKIP
  DO_PLAIN=0; DO_CRYPT=0
fi

# ── Phase 1: build ISO ────────────────────────────────────────────────────────
if (( DO_ISO )) && (( DO_PLAIN || DO_CRYPT )); then
  run_phase iso "$RUN_DIR/iso.log" bash "$SRC/scripts/build-iso.sh"
  if [[ "${ST[iso]}" == FAIL ]]; then
    info "ISO build failed — cannot run e2e against a stale/absent ISO."
    DO_PLAIN=0; DO_CRYPT=0
  fi
elif (( ! DO_ISO )) && (( DO_PLAIN || DO_CRYPT )); then
  warn "iso build skipped (--no-iso) — reusing newest archiso/out/*.iso."
  set_state iso SKIP
fi

# ── Phase 2: e2e plain (btrfs + GRUB) ─────────────────────────────────────────
if (( DO_PLAIN )); then
  SENT="$RUN_DIR/.sentinel-plain"; touch "$SENT"
  run_phase plain "$RUN_DIR/plain.log" bash "$SRC/vm/e2e.sh" "${E2E_EXTRA[@]}"
  archive_diags plain "$SENT"; scan_logs plain
fi

# ── Phase 3: e2e encrypted (LUKS2 + Limine + TPM2) ────────────────────────────
if (( DO_CRYPT )); then
  if ! command -v swtpm &>/dev/null; then
    warn "encrypted phase skipped: swtpm not installed (sudo pacman -S swtpm)."
    set_state crypt SKIP
  else
    SENT="$RUN_DIR/.sentinel-crypt"; touch "$SENT"
    run_phase crypt "$RUN_DIR/crypt.log" bash "$SRC/vm/e2e.sh" --encrypted "${E2E_EXTRA[@]}"
    archive_diags crypt "$SENT"; scan_logs crypt
  fi
fi

# ── Summary + verdict ─────────────────────────────────────────────────────────
VERDICT=PASS
for p in "${ORDER[@]}"; do
  [[ "${ST[$p]}" == FAIL ]] && VERDICT=FAIL
done

{
  echo "run_dir=$RUN_DIR"
  echo "timestamp=$TS"
  for p in "${ORDER[@]}"; do
    echo "phase.$p=${ST[$p]}${DUR[$p]:+ (${DUR[$p]}s)}"
  done
} > "$SUMMARY.tmp"
# logscan lines were appended straight to $SUMMARY during scan_logs; merge.
[[ -f "$SUMMARY" ]] && cat "$SUMMARY" >> "$SUMMARY.tmp"
echo "verdict=$VERDICT" >> "$SUMMARY.tmp"
mv "$SUMMARY.tmp" "$SUMMARY"

echo
info "── x-test summary ─────────────────────────────"
for p in "${ORDER[@]}"; do
  case "${ST[$p]}" in
    PASS) ok   "$p${DUR[$p]:+  ${DUR[$p]}s}" ;;
    SKIP) warn "$p" ;;
    FAIL) bad  "$p${DUR[$p]:+  ${DUR[$p]}s}" ;;
  esac
done
[[ -f "$RUN_DIR/logscan.txt" ]] && info "log-scan findings (review): $RUN_DIR/logscan.txt"
info "artifacts: $RUN_DIR"
info "summary:   $SUMMARY"
echo
if [[ "$VERDICT" == PASS ]]; then
  ok "VERDICT: PASS — all executed gate phases passed."
  exit 0
else
  bad "VERDICT: FAIL — see failed phase log(s) in $RUN_DIR."
  exit 1
fi
