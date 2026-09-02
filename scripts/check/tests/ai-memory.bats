#!/usr/bin/env bats
# ai-memory.bats — modules/memory.py: _mem_context() (session-start context block).
#
# core.py is explicitly import-only/testable without the `mcp` package (its own
# header docstring), so this drives modules.memory directly via PYTHONPATH rather
# than through the w-mcp CLI — no python-mcp install required to run these.

load helpers

setup() {
  command -v python3 &>/dev/null || skip "python3 not installed"
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
  export W_AI_STATE_ROOT="$BATS_TEST_TMPDIR/state"
  MEMDIR="$W_AI_STATE_ROOT/memory"
  mkdir -p "$MEMDIR"
  # Layered-config seams (w-conf-lib.sh / core.conf_read). Pointing them at the
  # tmpdir also isolates these tests from the host's real /etc/w and ~/.config/w,
  # which the previous core.AI_CONF list read straight through on a W machine.
  export WCONF_ETC="$BATS_TEST_TMPDIR/etc-w"
  export WCONF_VENDOR_DIR="$BATS_TEST_TMPDIR/defaults"
  export WCONF_HOME="$BATS_TEST_TMPDIR/home"
  USER_CONF_DIR="$WCONF_HOME/.config/w"
  mkdir -p "$WCONF_ETC" "$WCONF_VENDOR_DIR" "$USER_CONF_DIR"
}

# Writes one fact file: write_fact <slug> <type> <description> <body>
write_fact() {
  local slug="$1" type="$2" desc="$3" body="$4"
  cat > "$MEMDIR/$slug.md" <<EOF
---
name: $slug
description: $desc
type: $type
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
---

$body
EOF
}

mem_context() {
  PYTHONPATH="$LIB" python3 -c "from modules import memory; print(memory._mem_context(), end='')"
}

@test "_mem_context: empty store returns empty string" {
  result="$(mem_context)"
  [[ -z "$result" ]]
}

@test "_mem_context: renders user facts (with body) and feedback facts (description only)" {
  write_fact "assistant-name" user "assistant is named Zak" "The assistant introduces itself as Zak."
  write_fact "terse-replies" feedback "user wants terse replies, no trailing summaries" "Do not summarize actions at the end of a response."
  result="$(mem_context)"
  [[ "$result" == *"About you and the user:"* ]]
  [[ "$result" == *"assistant is named Zak"* ]]
  [[ "$result" == *"The assistant introduces itself as Zak."* ]]
  [[ "$result" == *"Feedback to follow:"* ]]
  [[ "$result" == *"user wants terse replies, no trailing summaries"* ]]
  # feedback body is not rendered, only its description
  [[ "$result" != *"Do not summarize actions at the end"* ]]
}

@test "_mem_context: type=project/reference facts are excluded" {
  write_fact "some-project" project "mid-refactor of the auth module" "irrelevant to session start"
  result="$(mem_context)"
  [[ -z "$result" ]]
}

@test "_mem_context: over the cap, trims oldest first and appends a pointer to search" {
  # 20 user facts x ~400 chars of body each, well over MAX_CONTEXT_CHARS (6000)
  local i body
  for i in $(seq 1 20); do
    body="$(printf 'x%.0s' {1..400})"
    write_fact "fact-$i" user "fact number $i" "$body"
  done
  result="$(mem_context)"
  [[ "$result" == *"(…more in memory — use w_memory_search)"* ]]
  # hard cap (6000) plus the trailing marker line, with slack for section headers
  [[ "${#result}" -le 6100 ]]
}

# ── Stage 3: tasks, episodes, hygiene ─────────────────────────────────────────

mem_py() {  # mem_py <python expr on `memory`> — helper to drive private funcs directly
  PYTHONPATH="$LIB" python3 -c "
from modules import memory
$1
"
}

@test "_mem_task_add/_mem_task_list/_mem_task_done: full lifecycle" {
  mem_py "print(memory._mem_task_add('check the backups', '2026-08-01'))"
  result="$(mem_py "print(memory._mem_task_list())")"
  [[ "$result" == *"[open]"* ]]
  [[ "$result" == *"check the backups"* ]]
  [[ "$result" == *"(due 2026-08-01)"* ]]

  slug="$(mem_py "print(memory._slugify('check the backups'))")"
  mem_py "print(memory._mem_task_done('$slug'))"

  open_result="$(mem_py "print(memory._mem_task_list('open'))")"
  [[ "$open_result" == *"no tasks"* ]]
  done_result="$(mem_py "print(memory._mem_task_list('done'))")"
  [[ "$done_result" == *"[done]"* ]]
  [[ "$done_result" == *"(due 2026-08-01)"* ]]   # due survives the status flip
}

@test "_mem_task_add: non-ASCII descriptions that collide on the ASCII fallback slug get disambiguated, not clobbered" {
  # _slugify strips non-ASCII entirely, so two different Cyrillic-only task
  # descriptions both degrade to the fallback slug "fact" — must not overwrite.
  mem_py "print(memory._mem_task_add('проверить бэкапы'))"
  mem_py "print(memory._mem_task_add('обновить прошивку'))"
  result="$(mem_py "print(memory._mem_task_list('all'))")"
  [[ "$result" == *"проверить бэкапы"* ]]
  [[ "$result" == *"обновить прошивку"* ]]
  [[ "$(ls "$MEMDIR" | wc -l)" -eq 2 ]]
  # re-adding the exact same description is idempotent (reuses the slug)
  mem_py "print(memory._mem_task_add('проверить бэкапы'))"
  [[ "$(ls "$MEMDIR" | wc -l)" -eq 2 ]]
}

@test "w_memory_store (_mem_write_fact): non-ASCII descriptions colliding on the fallback slug get disambiguated, not clobbered" {
  # Same class of bug as the task test above, but for the general fact writer
  # (_mem_write_fact) behind w_memory_store — no explicit `name` given, so the
  # slug is auto-derived from `description` and both collapse to "fact".
  mem_py "memory._mem_write_fact('', 'зовут Зак', 'user', 'assistant name is Zak')"
  mem_py "memory._mem_write_fact('', 'зовут Тарх', 'user', 'user name is Tarkh')"
  result="$(mem_py "print(memory._mem_list())")"
  [[ "$result" == *"зовут Зак"* ]]
  [[ "$result" == *"зовут Тарх"* ]]
  [[ "$(ls "$MEMDIR" | wc -l)" -eq 2 ]]
  # re-storing the exact same description is idempotent (reuses the slug)
  mem_py "memory._mem_write_fact('', 'зовут Зак', 'user', 'assistant name is Zak, updated')"
  [[ "$(ls "$MEMDIR" | wc -l)" -eq 2 ]]
}

@test "_mem_context: renders Open tasks (open only) and Recent episodes (project episode-*)" {
  write_fact "episode-thing" project "2026-07-24: did a thing" "irrelevant"
  mem_py "memory._mem_task_add('check the backups')"
  mem_py "s=memory._slugify('done already'); memory._mem_task_add('done already'); memory._mem_task_done(s)"
  result="$(mem_context)"
  [[ "$result" == *"Open tasks:"* ]]
  [[ "$result" == *"check the backups"* ]]
  [[ "$result" != *"done already"* ]]           # done tasks don't resurface
  [[ "$result" == *"Recent episodes:"* ]]
  [[ "$result" == *"2026-07-24: did a thing"* ]]
}

@test "_mem_review: flags stale done-task and stale episode, honest in-context column" {
  write_fact "assistant-name" user "assistant is named Zak" "body"
  mem_py "memory._mem_task_add('fresh task')"
  mem_py "s=memory._slugify('old task'); memory._mem_task_add('old task'); memory._mem_task_done(s)"
  write_fact "episode-old" project "2026-01-01: ancient episode" "irrelevant"
  # Backdate the done task and the episode past their staleness thresholds (30d/60d).
  old_mtime=$(($(date +%s) - 90 * 86400))
  touch -d "@$old_mtime" "$MEMDIR/old-task.md" "$MEMDIR/episode-old.md"
  result="$(mem_py "print(memory._mem_review())")"
  [[ "$result" == *"assistant-name"*"user"*"yes"* ]]
  [[ "$result" == *"fresh-task"*"task"*"yes"* ]]
  [[ "$result" == *"old-task"*"(stale — consider rm)"* ]]
  [[ "$result" == *"episode-old"*"(stale — consider rm)"* ]]
}

@test "w_memory_store collision warning: overwriting a fact under a different type warns" {
  write_fact "foo" project "some project note" "body"
  warn="$(mem_py "print(memory._mem_collision_warning('foo', 'reference'))")"
  [[ "$warn" == *"warning: overwrote existing fact 'foo'"* ]]
  [[ "$warn" == *"was type=project, now type=reference"* ]]
  same_type="$(mem_py "print(memory._mem_collision_warning('foo', 'project'))")"
  [[ -z "$same_type" ]]
}

@test "index fallback (Этап 7.4.4): deleting memory.db still finds facts via a rebuilt index" {
  write_fact "vpn-note" reference "how the office VPN is configured" "wireguard, split tunnel"
  mem_py "print(memory._mem_search('VPN'))" > /dev/null   # build the index once
  [[ -f "$W_AI_STATE_ROOT/memory.db" ]]
  rm -f "$W_AI_STATE_ROOT/memory.db" "$W_AI_STATE_ROOT/memory.db-wal" "$W_AI_STATE_ROOT/memory.db-shm"
  result="$(mem_py "print(memory._mem_search('VPN'))")"
  [[ "$result" == *"vpn-note"* ]]
  [[ -f "$W_AI_STATE_ROOT/memory.db" ]]   # rebuilt, not left missing
}

# ── hybrid FTS5+vector semantic recall ────────
# All hermetic — no ollama/network involved. `_embed` is monkeypatched to a
# deterministic stub; `core.AI_CONF` is pointed at fixture files under
# BATS_TEST_TMPDIR so the real /etc/w/ai.conf / ~/.config/w/ai.conf never leak
# into these tests (precedence tests need full control of all three layers).

conf_py() {  # like mem_py, but also imports core+Path (layered-config tests)
  PYTHONPATH="$LIB" python3 -c "
from pathlib import Path
from modules import memory
import core
$1
"
}

@test "_mem_search: W_AI_EMBED=off (default, no ai-features.conf) is the pre-Stage-3 FTS5-only path" {
  write_fact "vpn-note" reference "how the office VPN is configured" "wireguard, split tunnel"
  result="$(mem_py "print(memory._mem_search('VPN'))")"
  [[ "$result" == "1 match(es):"* ]]
  [[ "$result" == *"[reference] vpn-note: how the office VPN is configured"* ]]
}

@test "_mem_search: W_AI_EMBED=ollama hybrid — RRF surfaces a vector-only hit alongside an FTS-only hit" {
  # photo-fact shares zero keywords with the query — only findable via the
  # (stubbed) vector channel. laptop-fact shares keywords — only via FTS.
  write_fact "photo-fact" reference "фотосинтез растений" \
    "замедляется при недостатке света, никак не связано с техникой"
  write_fact "laptop-fact" reference "ноутбук тормозит из-за профиля питания" \
    "ноутбук сильно тормозит после обновления"
  cat > "$USER_CONF_DIR/ai-features.conf" <<'EOF'
W_AI_EMBED=ollama
W_AI_EMBED_MODEL=test-model
EOF
  result="$(conf_py "
vecmap = {
    # note: a stored fact body always carries exactly one trailing '\n' (write_fact/
    # _mem_write_fact append it) — the embed text is description + '\n' + body.
    'фотосинтез растений\nзамедляется при недостатке света, никак не связано с техникой\n': [1.0, 0.0],
    'ноутбук сильно тормозит': [1.0, 0.0],   # the query string itself
}
memory._embed = lambda texts, conf: [vecmap.get(t, [0.0, 1.0]) for t in texts]
print(memory._mem_search('ноутбук сильно тормозит'))
")"
  [[ "$result" == *"photo-fact"* ]]
  [[ "$result" == *"laptop-fact"* ]]
}

@test "_VecIndex.search: cosine threshold (~0.35) filters out a dissimilar vector" {
  result="$(mem_py "
from modules.memory import _VecIndex, _mem_conn
with _mem_conn() as conn:
    vec = _VecIndex(conn)
    vec.upsert('memory', 'similar', 'h1', [1.0, 0.0])
    vec.upsert('memory', 'dissimilar', 'h2', [0.0, 1.0])
    conn.commit()
    print([ref for ref, _ in vec.search([1.0, 0.0])])
")"
  [[ "$result" == *"similar"* ]]
  [[ "$result" != *"dissimilar"* ]]
}

@test "_mem_search: numpy ImportError degrades to FTS5-only, no exception" {
  write_fact "vpn-note" reference "how the office VPN is configured" "wireguard, split tunnel"
  cat > "$USER_CONF_DIR/ai-features.conf" <<'EOF'
W_AI_EMBED=ollama
W_AI_EMBED_MODEL=test-model
EOF
  run conf_py "
import sys
sys.modules['numpy'] = None
memory._embed = lambda texts, conf: [[1.0, 0.0] for _ in texts]
print(memory._mem_search('VPN'))
"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"vpn-note"* ]]
}

@test "config precedence: ai-features.conf overrides user ai.conf overrides system ai.conf" {
  # The real layer chain (system → user → user-features), not a patched file list:
  # ai-features.conf must win because `w-ai profile use` rewrites the user file
  # wholesale and the feature toggles have to survive that.
  printf 'W_AI_EMBED=off\n'    > "$WCONF_ETC/ai.conf"
  printf 'W_AI_EMBED=ollama\n' > "$USER_CONF_DIR/ai.conf"
  printf 'W_AI_EMBED=off\n'    > "$USER_CONF_DIR/ai-features.conf"
  result="$(conf_py "print(core._ai_conf().get('W_AI_EMBED'))")"
  [[ "$result" == "off" ]]

  printf 'W_AI_EMBED=ollama\n' > "$USER_CONF_DIR/ai-features.conf"
  result="$(conf_py "print(core._ai_conf().get('W_AI_EMBED'))")"
  [[ "$result" == "ollama" ]]

  # And the user file still beats the system one when no feature file speaks.
  rm -f "$USER_CONF_DIR/ai-features.conf"
  result="$(conf_py "print(core._ai_conf().get('W_AI_EMBED'))")"
  [[ "$result" == "ollama" ]]
}
