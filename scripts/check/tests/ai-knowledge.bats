#!/usr/bin/env bats
# ai-knowledge.bats — modules/knowledge.py: Knowledge Search Unit Tests (Этап
# 7.4.4). _search_knowledge() is import-only/testable without the `mcp` package
# (same reasoning as ai-skills.bats). Covers fixed query->skill table tests,
# user-overlay-wins precedence, and the empty-query guard.
#
# The "index fallback" bullet of 7.4.4 (delete the index, search still works via
# rebuild) does not apply here — w_search_knowledge has no index at all (it's a
# live directory scan every call); that behavior belongs to modules/memory.py's
# FTS5 store and is covered by ai-memory.bats instead.

load helpers

setup() {
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
  export W_AI_SYS_ROOT="$BATS_TEST_TMPDIR/sysroot"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$W_AI_SYS_ROOT/skills/deploy-frontend" "$W_AI_SYS_ROOT/skills/w-theming"
  cat > "$W_AI_SYS_ROOT/skills/deploy-frontend/SKILL.md" <<'EOF'
---
name: deploy-frontend
description: how to deploy the frontend to production
---

# Deploy Frontend
Steps to deploy the frontend build to the prod server.
EOF
  cat > "$W_AI_SYS_ROOT/skills/w-theming/SKILL.md" <<'EOF'
---
name: w-theming
description: switch the active theme
---

# Theming
Use w_theme_set to switch the active W theme.
EOF
}

search() {  # search <query> [max_results]
  PYTHONPATH="$LIB" python3 -c "
from modules import knowledge
print(knowledge._search_knowledge('$1', ${2:-5}))
"
}

@test "query->skill mapping: 'switch theme' finds the theming skill" {
  result="$(search 'switch theme')"
  [[ "$result" == *"w-theming/SKILL.md"* ]]
}

@test "query->skill mapping: 'deploy frontend production' finds the deploy skill" {
  result="$(search 'deploy frontend production')"
  [[ "$result" == *"deploy-frontend/SKILL.md"* ]]
}

@test "empty query guard: blank query returns the empty-query marker, does not crash" {
  result="$(search '')"
  [[ "$result" == "(empty query)" ]]
}

@test "empty query guard: whitespace-only query is treated as empty" {
  result="$(search '   ')"
  [[ "$result" == "(empty query)" ]]
}

@test "no matches: an unrelated query returns a clear no-match marker" {
  result="$(search 'xyznonexistentqueryterm')"
  [[ "$result" == "(no matches for: xyznonexistentqueryterm)" ]]
}

@test "overlay priority: a user-overlay skill with the same relative path wins over the system one" {
  mkdir -p "$HOME/.config/w/ai/skills/deploy-frontend"
  cat > "$HOME/.config/w/ai/skills/deploy-frontend/SKILL.md" <<'EOF'
---
name: deploy-frontend
description: USER OVERRIDE deploy workflow
origin: agent-authored
---

# Deploy Frontend (user override)
This mentions a unique marker: OVERLAY-WINS-MARKER deploy frontend production.
EOF
  result="$(search 'deploy frontend production')"
  # only ONE entry for this relative path (the overlay shadows the system file,
  # not counted twice), and its full path resolves under the user overlay dir,
  # not the system root (the snippet line itself is just the first matching
  # line in the file — frontmatter's "name: deploy-frontend" — not necessarily
  # the marker sentence, so assert on the resolved path instead).
  count="$(grep -c 'deploy-frontend/SKILL.md' <<< "$result")"
  [[ "$count" -eq 1 ]]
  [[ "$result" == *"$HOME/.config/w/ai/skills/deploy-frontend/SKILL.md"* ]]
}
