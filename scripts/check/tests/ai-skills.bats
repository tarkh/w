#!/usr/bin/env bats
# ai-skills.bats — modules/skills.py: self-authored user-overlay skills.
#
# core.py is import-only/testable without the `mcp` package (same reasoning as
# ai-memory.bats). Covers the code-enforced parts of Этап 6: name validation,
# system-skill shadow refusal, size cap, and the four-criteria dedup gate
# (6.5) — the part that must be reliable regardless of whether the model
# remembers to search first.

load helpers

setup() {
  command -v python3 &>/dev/null || skip "python3 not installed"
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
  export HOME="$BATS_TEST_TMPDIR/home"
  export W_AI_SYS_ROOT="$BATS_TEST_TMPDIR/sysroot"
  mkdir -p "$HOME" "$W_AI_SYS_ROOT/skills/w-security"
  echo "---
name: w-security
description: system skill
---
body" > "$W_AI_SYS_ROOT/skills/w-security/SKILL.md"
}

skills_py() {  # skills_py <python expr on `skills`>
  PYTHONPATH="$LIB" python3 -c "
from modules import skills
$1
"
}

add() {  # add <name> <description> <content> [tags] [overwrite]
  local name="$1" desc="$2" content="$3" tags="${4:-}" overwrite="${5:-False}"
  skills_py "print(skills._skill_add('$name', '$desc', '$content', '$tags', $overwrite))"
}

@test "_skill_add: rejects an invalid name" {
  result="$(add 'Not Valid!' 'desc' 'content')"
  [[ "$result" == *"invalid name"* ]]
}

@test "_skill_add: refuses to shadow a system skill" {
  result="$(add 'w-security' 'desc' 'content')"
  [[ "$result" == *"refused"* ]]
  [[ "$result" == *"shadows a system skill"* ]]
  [[ ! -f "$HOME/.config/w/ai/skills/w-security/SKILL.md" ]]
}

@test "_skill_add: rejects content over the 32KB cap" {
  big="$(python3 -c "print('x' * 33000)")"
  result="$(add 'big-skill' 'desc' "$big")"
  [[ "$result" == *"too large"* ]]
}

@test "_skill_add: happy path creates the file with expected frontmatter" {
  result="$(add 'deploy-frontend' 'deploy the frontend to prod' 'Step 1. Step 2.')"
  [[ "$result" == *"created"* ]]
  f="$HOME/.config/w/ai/skills/deploy-frontend/SKILL.md"
  [[ -f "$f" ]]
  grep -q "^name: deploy-frontend$" "$f"
  grep -q "^origin: agent-authored$" "$f"
  grep -q "^description: deploy the frontend to prod$" "$f"
}

@test "_skill_add dedup: exact name match is refused without overwrite, allowed with it" {
  add 'deploy-frontend' 'deploy the frontend to prod' 'v1' >/dev/null
  result="$(add 'deploy-frontend' 'deploy the frontend to prod, v2' 'v2')"
  [[ "$result" == *"possible duplicate"* ]]
  [[ "$result" == *"exact-name"* ]]
  [[ "$(cat "$HOME/.config/w/ai/skills/deploy-frontend/SKILL.md")" == *"v1"* ]]

  result2="$(add 'deploy-frontend' 'deploy the frontend to prod, v2' 'v2' '' True)"
  [[ "$result2" == *"updated"* ]]
  [[ "$(cat "$HOME/.config/w/ai/skills/deploy-frontend/SKILL.md")" == *"v2"* ]]
}

@test "_skill_add dedup: substring name match is refused" {
  add 'deploy' 'deploy the app' 'content'  >/dev/null
  result="$(add 'deploy-prod' 'deploy the app to production' 'content2')"
  [[ "$result" == *"possible duplicate"* ]]
  [[ "$result" == *"'deploy'"* ]]
  [[ "$result" == *"substring-name"* ]]
}

@test "_skill_add dedup: tag overlap match is refused" {
  add 'setup-postgres-backup' 'back up postgres nightly' 'content' 'postgres,backup,cron' >/dev/null
  result="$(add 'nightly-db-dump' 'a totally different name and blurb' 'content2' 'postgres,backup,other')"
  [[ "$result" == *"possible duplicate"* ]]
  [[ "$result" == *"tag-overlap"* ]]
}

@test "_skill_add dedup: keyword top-3 match is refused" {
  add 'setup-postgres-backup' 'nightly postgres backup to s3 bucket' 'content' >/dev/null
  result="$(add 'postgres-backup-restore' 'restore postgres backup from s3 bucket' 'content2')"
  [[ "$result" == *"possible duplicate"* ]]
  [[ "$result" == *"keyword-top3"* ]]
}

@test "_skill_add dedup: overwrite=true creates a genuinely new, unrelated skill without checking" {
  add 'deploy-frontend' 'deploy the frontend' 'content' >/dev/null
  result="$(add 'unrelated-thing' 'totally unrelated workflow' 'content2' '' True)"
  [[ "$result" == *"created"* ]]
  [[ -f "$HOME/.config/w/ai/skills/unrelated-thing/SKILL.md" ]]
}

@test "_skill_add dedup: unrelated new skill is not flagged" {
  add 'deploy-frontend' 'deploy the frontend to prod' 'content' >/dev/null
  result="$(add 'setup-printer' 'configure the office printer' 'content2')"
  [[ "$result" == *"created"* ]]
}

@test "_skill_list: marks system vs user scope" {
  add 'my-workflow' 'a user workflow' 'content' >/dev/null
  result="$(skills_py "print(skills._skill_list())")"
  [[ "$result" == *"[system] w-security"* ]]
  [[ "$result" == *"[user]   my-workflow: a user workflow"* ]]
}

@test "_skill_add runtime lint: multi-line description breaking frontmatter is refused, nothing written" {
  # An embedded "\n---" in description terminates the hand-rolled frontmatter
  # parser early, pushing origin/created out of the parsed block — exactly the
  # drift lint-on-write (Этап 6.11) exists to catch before it hits disk.
  result="$(skills_py "print(skills._skill_add('broken-fm', 'line one'+chr(10)+'---'+chr(10)+'more', 'content', '', False))")"
  [[ "$result" == *"refused"* ]]
  [[ "$result" == *"runtime lint"* ]]
  [[ ! -f "$HOME/.config/w/ai/skills/broken-fm/SKILL.md" ]]
}

@test "_skill_add runtime lint: a soundly formed skill with a lint warning is still created" {
  # No H1/H2 heading in the body is a warning, not an error — write proceeds,
  # warning is surfaced in the response for the model/user to see.
  result="$(add 'no-heading-skill' 'a workflow with no heading' 'plain body, no heading at all')"
  [[ "$result" == *"created"* ]]
  [[ "$result" == *"lint warnings"* ]]
  [[ -f "$HOME/.config/w/ai/skills/no-heading-skill/SKILL.md" ]]
}

@test "_skill_rm: removes a user skill, refuses on a system skill name" {
  add 'my-workflow' 'a user workflow' 'content' >/dev/null
  result="$(skills_py "print(skills._skill_rm('my-workflow'))")"
  [[ "$result" == *"removed user skill: my-workflow"* ]]
  [[ ! -d "$HOME/.config/w/ai/skills/my-workflow" ]]

  result2="$(skills_py "print(skills._skill_rm('w-security'))")"
  [[ "$result2" == *"refused"* ]]
  [[ "$result2" == *"system skill"* ]]
}
