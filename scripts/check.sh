#!/usr/bin/env bash
# check.sh — W static verification suite (dev-side only, never ships).
#
# Single entry point for every consumer: developer, Claude session, git hook,
# CI (same script inside an archlinux container). Suites live in scripts/check/
# as chk_* functions; each prints its findings and returns non-zero on failure.
#
# Usage:
#   scripts/check.sh              # all offline suites (seconds)
#   scripts/check.sh --bash       # one suite (any of the flags below)
#   scripts/check.sh --online     # adds network checks (package existence)
#   scripts/check.sh --strict     # a skipped tool is a failure (CI only)
#
# Tools are optional: a missing linter SKIPs its suite with a warning instead
# of failing — the run degrades gracefully on a bare machine, while CI (with
# everything installed) always exercises the full set.
#
# --strict is the other half of that bargain, and belongs to the container
# alone: it turns "this tool is absent" into a failure, so an incomplete image
# can no longer report a green run over suites it never executed. It cost a
# nightly to learn the difference — v0.4.0 added two suites needing jq and
# ssh-keygen; one failed loudly for the environment's reason and the other
# skipped all 17 of its cases in silence, both on the same green-looking list.
set -euo pipefail

# macOS ships bash 3.2; the suites need >=4 (mapfile, assoc arrays). Re-exec
# into Homebrew bash when the system one is too old.
if ((BASH_VERSINFO[0] < 4)); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x $_b ]] && exec "$_b" "$0" "$@"
  done
  echo "check.sh: bash >= 4 required (brew install bash)" >&2
  exit 1
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; NC='\033[0m'
info() { echo -e "${MAGENTA}==>${NC} $*"; }
ok()   { echo -e "${GREEN} ok${NC} $*"; }
# Every warn() call site is a tool that is not installed — that is the only
# reason a suite steps aside. SKIPPED carries the fact out to the runner loop,
# which decides what it means (nothing, or a failure under --strict).
SKIPPED=0
warn() { SKIPPED=1; echo -e "${YELLOW}skip${NC} $*"; }
bad()  { echo -e "${RED}FAIL${NC} $*"; }

# ── Shared inventory ──────────────────────────────────────────────────────────
# Tracked + new-untracked files (git is the source of truth; .gitignore filters
# VM images, logs, __pycache__ etc). Untracked-but-not-ignored included so a
# freshly written script is checked before its first `git add`.
mapfile -t ALL_FILES < <(git ls-files --cached --others --exclude-standard)

# Vendored upstream scripts — not our style, not our churn. Excluded from lint;
# security-relevant changes there are reviewed at vendoring time instead.
VENDORED=(rootfs/usr/lib/w/papirus-folders)

is_vendored() {
  local f v
  for v in "${VENDORED[@]}"; do [[ "$1" == "$v" ]] && return 0; done
  return 1
}

# Shell inventory, split by how shellcheck must treat a file:
#   SH_ENTRY — has a shebang (checked as-is, dialect from the shebang)
#   SH_LIB   — sourced fragments without shebang (forced -s bash)
SH_ENTRY=(); SH_LIB=(); PY_FILES=()
for f in "${ALL_FILES[@]}"; do
  [[ -f "$f" ]] || continue
  is_vendored "$f" && continue
  case "$f" in
    # rootfs/etc/initcpio/* ships executable code into the initramfs — the one
    # place a 644 or a syntax error surfaces only as an unbootable machine.
    # vm/*.py is host-side harness code (the Ф.4 fault endpoint). Narrowed to *.py
    # on purpose: vm/ also holds ISO and qcow2 images, which have no business in a
    # lint inventory.
    *.sh|rootfs/usr/bin/*|rootfs/usr/lib/w/*|devtools/usr/local/bin/*|rootfs/etc/initcpio/*|vm/*.py) ;;
    *) continue ;;
  esac
  # First line via `read` (not $(head …)) — binary neighbors in these trees
  # would trip bash's "ignored null byte" warning under command substitution.
  head1=""; IFS= read -r head1 < <(head -c 64 "$f" 2>/dev/null) || true
  case "$f" in
    *.sh)
      if [[ "$head1" == "#!"* ]]; then SH_ENTRY+=("$f"); else SH_LIB+=("$f"); fi ;;
    *)
      case "$head1" in
        # ash = the busybox initramfs shell (mkinitcpio runtime hooks); those
        # files carry an inline `shellcheck shell=dash` so the linter can read them.
        "#!"*bash*|"#!/bin/sh"*|"#!"*ash*) SH_ENTRY+=("$f") ;;
        "#!"*python3*)           PY_FILES+=("$f") ;;
      esac ;;
  esac
done
unset f head1

# ── Suites ────────────────────────────────────────────────────────────────────
for s in "$SRC"/scripts/check/*.sh; do source "$s"; done

SUITES=(bash python unit perms manifests modules routing publish wconf i18n packages landmines paths qml theme pam docs)
ONLINE=0
STRICT=0
RUN=()

for arg in "$@"; do
  case "$arg" in
    --online) ONLINE=1 ;;
    --strict) STRICT=1 ;;
    --*)
      name="${arg#--}"
      [[ " ${SUITES[*]} " == *" $name "* ]] || { bad "unknown suite: $arg"; exit 2; }
      RUN+=("$name") ;;
    *) bad "unknown argument: $arg"; exit 2 ;;
  esac
done
[[ ${#RUN[@]} -eq 0 ]] && RUN=("${SUITES[@]}")

FAILED=()
for s in "${RUN[@]}"; do
  info "check: $s"
  SKIPPED=0
  rc=0; "chk_$s" || rc=$?
  if [[ $rc -eq 0 && $STRICT -eq 1 && $SKIPPED -eq 1 ]]; then
    echo "  --strict: the suite stepped aside for a missing tool; install it here"
    rc=1
  fi
  if [[ $rc -eq 0 ]]; then ok "$s"; else bad "$s"; FAILED+=("$s"); fi
done

echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
  info "All checks passed (${RUN[*]})"
else
  bad "Failed: ${FAILED[*]}"
  exit 1
fi
