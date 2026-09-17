---
title: w-ai
section: reference
order: 0
summary: Launch and manage the W AI assistant — hosts, keys, memory, ask.
---

`w-ai` — Launch and manage the W AI assistant — hosts, keys, memory, ask.

## Usage

```
Usage: w-ai [--host <name>] [command]

Info: Launch and manage the W AI assistant — hosts, keys, memory, ask.

Launch (default when no command):
  w-ai                  Start the assistant with the configured host
  w-ai --host <name>    Override host for this run (goose|local|claude|codex|opencode)

Commands:
  ask <text…>           Start a session seeded with a question, then stay
                        interactive (the Quickshell "Ask W" palette calls this;
                        empty text is the same as a bare launch)
  ready                 Exit 0 if the active config is launch-ready (host binary
                        present, its login live or its API key in the keyring,
                        model set where the host needs one); exit 1 + a reason
                        word otherwise. Used by the Quickshell "Ask W" entry
                        point before it opens.
  status                Show host/provider/model, key presence, w-mcp self-test
  config                Edit the per-user override (~/.config/w/ai.conf)
  host list [--porcelain]   List hosts (goose|local|claude|codex|opencode) and state
  host status [<n>]     Show one host's contract (hosts/<n>/host.conf)
  host install <n>      Install a host's CLI with the vendor's own installer
  host login [<n>]      Sign in to a host that owns its auth (Claude Code, Codex)
  features [--porcelain]           Advanced-feature status (ai-extra pack):
                        ddgs/trafilatura/ollama/embed model/numpy, semantic
                        memory config, vector-corpus size
  features set <KEY> <value>       Set one advanced-feature key (W_AI_EMBED|
                        W_AI_EMBED_MODEL|W_AI_EMBED_URL|W_AI_EMBED_KEEPALIVE|
                        W_AI_SEARCH_PROVIDER) in ~/.config/w/ai-features.conf
  profile list          List provider profiles, marking the active one
  profile new <n> [--from <base>]   Create a profile (blank, or copied from <base>)
  profile edit <n>      Edit a profile in $EDITOR
  profile show <n>      Print a profile's contents
  profile use <n>       Make <n> the active profile (copies it into ai.conf override)
  profile rm <n>        Delete a profile
  profile field <n> <KEY> <value>   Set one KEY=VALUE line in a profile (uncomments
                        a commented default if present; the Hub's field editor uses
                        this instead of $EDITOR)
  key set <provider>    Store a provider API key in the keyring (prompts)
  key rm  <provider>    Remove a provider API key from the keyring
  key list              Show which providers have a key
  memory list           List stored assistant memories (shared across hosts)
  memory search <q>     Recall memories matching a query
  memory add            Write a new memory in $EDITOR (frontmatter template)
  memory rm <slug>      Delete a memory by slug
  memory context        Print the session-start memory context block
  memory review         Hygiene report: age, in-context, stale hints
  task list [status]    List tasks (default: open; also done|all)
  task add <text…>      Add an open task (append --due YYYY-MM-DD)
  task done <slug>      Mark a task done
  skills list           List system + user skills (the agent-authored overlay)
  skills show <name>    Print one skill's SKILL.md
  skills rm <name>      Delete a user skill (system skills are protected)
  recipe list           List available automation recipes (system + user overlay)
  run-recipe <name>     Run one recipe headlessly through goose, once (internal
                        entry point for the scheduled timer; safe to run by hand)
  schedule add <recipe> <OnCalendar>   Run a recipe on a systemd user timer
  schedule list          List active recipe schedules
  schedule rm <recipe>   Remove a recipe's schedule
  help                  Show this help

Config: $SYS_CONF (system) overlaid by $USER_CONF (user).
Secrets: gnome-keyring (attribute $KEY_ATTR=<provider>); nothing in plaintext.

Exit codes:
  0  Success   1  Runtime error   2  Usage error

Examples:
  w-ai key set openrouter
  w-ai --host local
  w-ai host install claude
  w-ai status
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-ai help`.
