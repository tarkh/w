#!/usr/bin/env bats
# release-attribution.bats — no authorship trailers or tool credits in release notes.
#
# attribution_lines() is lifted out of publish.sh (which cannot be sourced — it
# dispatches at the bottom) and run for real, so what passes here is the shipped code.

load helpers

setup() {
  [ -f "$REPO/scripts/publish.sh" ] || skip "public tree — publish.sh is dev-only"
  eval "$(sed -n '/^attribution_lines()/,/^}/p' "$REPO/scripts/publish.sh")"; }

@test "attribution: a plain changelog section is clean" {
  run attribution_lines <<<$'- **Faster boot.** Nothing to do.\n- Fixed a typo.'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "attribution: Co-Authored-By is caught, any case" {
  run attribution_lines <<<$'- Fix.\n\nCo-Authored-By: Someone <a@b.c>'
  [ "$status" -eq 0 ]
  run attribution_lines <<<'co-authored-by: x'
  [ "$status" -eq 0 ]
}

@test "attribution: a tool credit line is caught" {
  run attribution_lines <<<'Generated with [Claude Code](https://claude.com/claude-code)'
  [ "$status" -eq 0 ]
  run attribution_lines <<<'noreply@anthropic.com'
  [ "$status" -eq 0 ]
}

@test "attribution: the word co-authored mid-sentence is not a trailer" {
  run attribution_lines <<<'- The installer was co-authored-by-hand in a doc.'
  [ "$status" -eq 1 ]
}

@test "attribution: the real changelog sections are clean" {
  run bash -c "grep -inE '^[[:space:]]*co-authored-by:|generated with \[?claude|noreply@anthropic\\.com' '$REPO/CHANGELOG.md'"
  [ "$status" -eq 1 ]
}

@test "attribution: ordinary 'generated with' prose is not a credit line" {
  run attribution_lines <<<'- Themes generated with `w-theme new` keep their colours.'
  [ "$status" -eq 1 ]
}

# The gate as it sits in cmd_release, run under the script's own `set -euo pipefail`:
# grep exits 1 on a CLEAN section, and an unguarded assignment turned that into a
# silent exit before the release even started.
gate() {
  bash -c 'set -euo pipefail
    die() { echo "DIE: $*"; exit 1; }; ok() { echo "OK: $*"; }; CHANGELOG_FILE=x; version=v0
    '"$(sed -n '/^attribution_lines()/,/^}/p' "$REPO/scripts/publish.sh")"'
    run_gate() { local notes="$1"
    '"$(sed -n '/local attr; attr=/,/ok "no attribution/p' "$REPO/scripts/publish.sh")"'
    }
    run_gate "$1"' _ "$1"
}

@test "attribution gate: a clean section passes under set -e" {
  run gate '- Fixed a thing.'
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: no attribution"* ]]
}

@test "attribution gate: a dirty section stops the release with a message" {
  run gate $'- Fixed.\nCo-Authored-By: x'
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIE:"*"Co-Authored-By"* ]]
}
