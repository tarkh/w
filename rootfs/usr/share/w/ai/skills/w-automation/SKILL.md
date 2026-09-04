---
name: w-automation
description: >-
  Proactive/scheduled work: goose recipes (declarative task files, curated to
  read-only tools + a final notification) triggered by systemd user timers —
  "every morning, digest me" / "check the logs hourly". Load this for scheduling
  a recurring or one-off automated task, listing/removing an existing schedule,
  or explaining what a recipe is allowed to do unattended.
sources:
  - path: .claude/library/ai-integration.md
    sha256: bc82176c3f78dbb8dd2941a2fcc4767f02ef5072572f7c7364d2666ee028550e
tools:
  - w_recipe_list
  - w_schedule_add
  - w_schedule_list
  - w_schedule_rm
---

# W Automation (recipes + scheduling)

A **recipe** is a goose YAML task file — a declarative, reviewable unit of work,
not something you author on the fly. A **schedule** is a systemd user timer that
runs one recipe headlessly, on a repeating or one-off calendar expression. This is
NOT goose's own built-in scheduler (`goose schedule …`): that one is host-local and
outside W's journald-audited automation story, so W never uses it.

Recipes always run through goose, whichever host the user chats with — `--recipe` is a
goose feature, not a cross-host abstraction. On a machine whose active profile is a
provider CLI (Claude Code, Codex), goose can legitimately be absent; scheduling still
works, but the timer will fail until goose is installed. If a user reports a schedule
that never fires there, check that goose is present before looking anywhere else.

## The hard constraint (never forget this)

A headless run has nobody to answer a tool-approval prompt. Recipes are therefore
restricted **by convention** to read-only tools plus `w_notify` as the final step —
`w-ai run-recipe` forces `GOOSE_MODE=auto` regardless of `ai.conf`. This is not a
separate technical gate: a Tier-2 tool is just as reachable from a recipe as from
a normal session, and the barrier is the same one it always is — `pkexec` +
polkit. With no live graphical session it fails outright; with one (the normal
case on a personal desktop), it raises the same interactive prompt any manual
Tier-2 action would, at a moment the user didn't expect — never a silent
privilege grant, but also not a clean failure you can rely on. The real boundary
is the recipe's own convention (never call Tier-2). Never write or suggest a
recipe that assumes privileged access.

## Commands

- `w_recipe_list` — the catalog: system recipes plus any user overlay
  (`~/.config/w/ai/recipes/`), same precedence as host presets (user wins). Always
  call this before scheduling — a recipe name is a bare catalog entry, not a path.
- `w_schedule_add(recipe, oncalendar)` — arm a systemd user timer for a recipe. One
  schedule per recipe name; adding again replaces the time. `oncalendar` is a
  systemd `OnCalendar` expression: `daily`, `hourly`, `*:0/30` (every 30 min),
  `Mon *-*-* 09:00:00`, or an absolute one-shot (`2026-08-01 09:00:00`).
- `w_schedule_list` — active schedules, next/last run time.
- `w_schedule_rm(recipe)` — remove a schedule.

Only offer scheduling when the user explicitly asks for something recurring or
deferred ("every morning...", "remind me in an hour...", "check X hourly") —
never create a schedule unprompted. For a one-off reminder in *this* session
instead of a recurring background job, prefer `w_task_add` (memory) — scheduling
is for unattended work that should actually run, not just resurface as a note.

## The bundled recipes

- **`morning-digest`** — pending updates, failed systemd units, free disk on `/`,
  and open tasks, compiled into one `w_notify`. Skips sections with nothing to
  report.
- **`log-anomaly`** — scans `journalctl -p err` since the last hour for fresh
  error patterns; notifies only if something turns up (silent on a healthy
  machine). Assumes an hourly schedule (that is the `since` window baked into the
  recipe) — don't schedule it much more sparsely than that without also widening
  its window.

## Recipe from the CLI (for a human, or to inspect one)

`w-ai recipe list` / `w-ai run-recipe <name>` (run once, by hand) / `w-ai schedule
{add,list,rm}` — the same commands these tools wrap. Recipe YAML files live under
`/usr/share/w/ai/recipes/<name>.yaml` (system) or `~/.config/w/ai/recipes/<name>.yaml`
(user overlay, wins on a name collision) — plain text, reviewable like any other W
knowledge file.
