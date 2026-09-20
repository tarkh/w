---
name: w-ai
description: >-
  How the W assistant itself is configured: the w-ai CLI (host, provider, model,
  approval mode), named provider profiles, API keys in the keyring, and the
  Hub's AI panel, a root-level tile (the GUI equivalent). Load this when the user
  asks about switching models/providers, setting up a new AI profile, adding an
  API key, or how to reach AI settings from the Hub — including "help me
  configure yourself" requests.
sources:
  - path: .claude/library/w-ai.md
    sha256: 03a5fdbf137556293d33480cd23ea657356315aea50fe6b2a83a5271c7ef2359
---

# W AI (configuring the assistant)

`w-ai` is both the launcher for this assistant and its configuration tool. Bare
`w-ai` starts a session with whatever is currently configured — it is not an error.
Everything below is about the *configuration* side: which host/provider/model runs,
how to switch, and how to help the user set it up (from a terminal or from the Hub).

## Where the config lives

W's own defaults in `/usr/share/w/defaults/ai.conf` (updates overwrite it, which is
how the switch shipped with a new tool arrives), then the machine's deviations in
`/etc/w/ai.conf`, overlaid by `~/.config/w/ai.conf` (per-user override, wins) and, on
a fleet machine, by `/etc/w/policy.d/ai.conf` — a site policy that pins a key outright
(`w-conf origin ai <KEY>` reports layer `policy`, and no local edit can override it). Key fields:

| Field | Values | Meaning |
|---|---|---|
| `HOST` | `goose` (default) \| `local` \| `claude` \| `codex` \| `opencode` | which runtime launches. `local` is goose forced onto Ollama. `claude`/`codex`/`opencode` are optional provider CLIs, installed on demand. |
| `PROVIDER` | `openrouter` \| `anthropic` \| `openai` \| `google` \| `ollama` \| `subscription` \| (opencode only: anything else models.dev lists) | for goose: the LLM backend it talks to. For `claude`/`codex`/`opencode` it selects the **auth mode**: `subscription` means the CLI's own login (OpenCode calls its own subscription "Zen") and W passes no key at all; naming the API provider instead (`anthropic` for Claude Code, `openai` for Codex, any of the five shared ones for OpenCode) makes W pass a key from the keyring, which switches the user to pay-per-token API billing. For claude/codex a value outside the host's short list falls back to its first accepted one, so a profile copied from a goose one can't leave `claude` looking like it needs an OpenRouter key. OpenCode is the exception: it accepts ANY provider it knows about, even ones W has never heard of (mistral, groq, …) — those are entirely the user's own `opencode auth login -p <provider>`, outside W's keyring. |
| `MODEL` | provider-specific id | e.g. `anthropic/claude-sonnet-5` on OpenRouter, `llama3.1` on Ollama. **Required** for goose/local — W never runs `goose configure`, so an empty value fails at launch regardless of provider (`w-ai ready` catches this first). **Optional** for `claude`/`codex`/`opencode`: those pick a model inside the session, so leave it empty unless the user wants to pin one. |
| `MODE` | `auto` (default) \| `smart_approve` \| `approve` \| `chat` | how eagerly the host runs tools without asking. This is host-level UX, not the real security boundary — privileged actions always stop at a system password/fingerprint prompt regardless of `MODE`. W's own tools (`w-mcp` and the pack servers) are never held for host confirmation on any host: goose carries a pre-approved `permission.yaml`, codex/claude/opencode get server-level allow rules — so switching to a stricter mode prompts for the *host's* tools only. MCP servers the user registered by hand keep the host's normal confirmation flow. |
| `OLLAMA_HOST` | host:port | only relevant for `PROVIDER=ollama` / `HOST=local`. |
| `MCP_PROFILE` | empty (auto) \| `full` \| `minimal` | how much of this assistant's own tool surface is offered — irrelevant to end users, leave empty. |

## Commands

- `w-ai status` — current host/provider/model/mode, whether the host binary is
  installed, whether a key is present in the keyring, and `MCP extra:` — the MCP
  servers optional bundles registered for the assistant (`mcp.d` drop-ins, e.g.
  `inkscape, gimp` from the `graphics` bundle). Every host gets them at launch, as
  launch flags, alongside `w-mcp`; one marked `(missing)` is registered on the
  machine but not set up for this account — `w-pack setup <bundle>` fixes it, then
  launch `w-ai` again (the flags are computed per launch, nothing is cached).
- `w-ai config` — open the user override in an editor.
- `w-ai key set|rm|list <provider>` — store/remove/list an API key in the system
  keyring (never plaintext). `set` prompts interactively — never ask the user to
  paste a key into chat.
- `w-ai ask <text>` — seed a session with a question and stay interactive (what
  the "Ask W" palette hands off to).
- `w-ai ready` — exit 0 if the active config is launch-ready, else exit 1 with one
  reason word: `no-host-bin` (the host's CLI isn't installed), `not-logged-in` (it is
  installed but signed out), `no-provider`, `no-key`, `no-model`, `bad-host`. This is
  the first thing to run for "the assistant won't start" / "Ask W shows a warning
  instead of opening" reports — the word says exactly which fix applies.

## Hosts — the runtimes the assistant can run on

goose ships with W. The provider CLIs do not: they carry their own login and their
own updater, so they are installed per-user on request.

- `w-ai host list` — every host with its state: `ready`, `absent` (CLI not
  installed), `not-logged-in`, `signed-in`, `installed`; the active one is marked.
  This one command answers "why won't Claude Code start".
- `w-ai host install <name>` — install that host's CLI with the vendor's own
  installer (`claude`: Anthropic's, `codex`: OpenAI's, `opencode`: its own —
  all per-user, all self-updating; the AUR is deliberately not used).
  Idempotent: it does nothing when the binary is already there.
- `w-ai host login <name>` — run the CLI's own sign-in (`claude auth login`,
  `codex login`, `opencode auth login` — the last one is an interactive picker
  covering OpenCode's own Zen subscription and every other provider it knows),
  a browser flow. Needed once per account for a `subscription` profile.
- All three provider CLIs get W as **launch flags** from `w-ai` — nothing is
  written into `~/.claude`, `~/.codex` or `~/.config/opencode`, so a
  `claude`/`codex`/`opencode` started by hand in some project is the plain tool.
  Claude Code gets W's skills natively (plugin dir); Codex and OpenCode have no
  per-launch skill root, so under them W's knowledge arrives the goose way — the
  skill catalog in `w-mcp`'s session-start instructions, one skill at a time
  through `w_skill_read` — and identity as inline instructions (OpenCode also
  reads `AGENTS.md` on its own from the project, so W's system identity is an
  addition there, not a replacement). Every host sees the same catalog exactly
  once: natively where the host loads skills itself, in the instructions
  everywhere else.
- `w-ai host status <name>` — what that host declares: its binary, which `PROVIDER`
  values it accepts, whether it needs a `MODEL`, what it is good for.

For a host with its own login, `w-ai ready` remembers a **successful** sign-in check
for 12 hours (`~/.cache/w-ai/auth-<host>`), so the `Super+W` palette does not start a
CLI just to open a text field. A failed check is never remembered, and `w-ai host
login` forgets the stamp — so "I just signed in and it still refuses" is not a thing.
`w-ai status` and `w-ai host list` always ask the CLI itself: when the two disagree,
trust those two, and treat the palette as up to 12 hours behind.

Automation is goose-only: scheduled recipes (`w-ai recipe` / `w-ai schedule`) always
run through goose no matter which host the user chats with. So a machine whose active
profile is Claude Code still needs goose present for its timers to fire.

## Profiles — switching between setups

A **profile** is a named, saved combination of the fields above, so a user can keep
e.g. a `local` (offline Ollama) and an `openrouter` (cloud) setup side by side and
flip between them without hand-editing `ai.conf`.

- `w-ai profile list` — every profile; the active one is marked `(active)`, or
  `(active, modified since)` only if its file was hand-edited outside `w-ai` (e.g.
  directly editing the `.conf` file) after being selected.
- `w-ai profile new <name> [--from <existing>]` — create one, blank or copied.
- `w-ai profile field <name> <KEY> <value>` — set one field (`HOST`, `PROVIDER`,
  `MODEL`, `MODE`, `OLLAMA_HOST`, or `MCP_PROFILE`) without opening an editor —
  this is the command to use when building up a profile step by step. If `<name>`
  is the active profile, the change reaches `ai.conf` immediately — no need to
  re-`use` it.
- `w-ai profile show <name>` — print its current fields.
- `w-ai profile use <name>` — make it active.
- `w-ai profile rm <name>` — delete it (the two bundled profiles, `local` and
  `openrouter`, come back the next time `profile` is used — `rm` only resets them).

## The same thing from the Hub (GUI)

**W Hub → AI** — a root-level tile (robot icon, first in the grid) opens the AI
profiles panel directly:

- Each profile is a row. Tapping an inactive row makes it active immediately (same
  tap-to-apply idiom as the language/keyboard pickers). The active profile shows a
  checkmark instead.
- A chevron on a row expands an inline editor for all six fields (dropdowns for
  HOST/PROVIDER/MODE/MCP_PROFILE, text fields for MODEL/OLLAMA_HOST) — changes apply
  as soon as they're picked, no separate save step. The PROVIDER dropdown adapts to
  the chosen HOST: for Claude Code it offers *subscription* and *anthropic*, for
  Codex *subscription* and *openai*, for the local path only *ollama*, for OpenCode
  *subscription* (its Zen) plus every provider W shares across hosts (a provider
  outside that list is set from a terminal instead — `w-ai profile field opencode
  PROVIDER <name>` — and configured directly in OpenCode itself), and MODEL is
  labelled optional where the CLI picks its own.
- When the chosen host needs attention, a row appears right under HOST: **"not
  installed → Install"** or **"not signed in → Sign in"**, each opening a terminal
  that runs the matching `w-ai host` command. No password prompt — a provider CLI is
  installed for that user only.
- A "New profile…" row prompts for a name and, optionally, an existing profile to
  copy from.
- The expanded editor also carries an **API-key row** (under the provider dropdown,
  shown only when the provider needs one — hidden for `ollama` and for
  `subscription`): it reports
  whether a key is stored, offers a masked field to set one, and a remove button. The
  key is provider-scoped and shared by every profile using that provider — it is stored
  in the same keyring `w-ai key set` writes to (the panel pipes it straight there, never
  to disk/logs). So a user with the machine in front of them can add a key entirely in
  the GUI, no terminal needed.
- None of this needs a password/fingerprint prompt — profile switching is a plain
  user-setting, like keyboard layouts.

## Recipe: help the user set up or switch a profile

1. `w-ai profile list` first — don't create a duplicate of something that already
   exists.
2. If nothing fits, `w-ai profile new <name> [--from <similar>]`, then
   `w-ai profile field <name> HOST <host>` / `PROVIDER <provider>` /
   `MODEL <model>` / `MODE <mode>` for each value the user wants. **`MODEL` is not
   optional** for `goose`/`local` — leaving it empty makes the profile launch-broken
   (`w-ai ready` will refuse it) regardless of provider. Leave it empty for
   `claude`/`codex`/`opencode`.
3. For a subscription CLI (`HOST=claude`/`codex`/`opencode` with `PROVIDER=subscription`),
   there is no key to set. Run `w-ai host list` and follow the state: `absent` →
   `w-ai host install <host>`, `not-logged-in` → `w-ai host login <host>`. **Do not
   store an API key for a subscriber** — with one present the CLI bills the API
   instead of their subscription.
4. For a key-based cloud provider (anything but `ollama`/`subscription`), check
   `w-ai key list`. If the key
   is missing, **do not ask the user to paste it into the chat** (it would end up in
   logs/history) — tell them to run `w-ai key set <provider>` themselves (it prompts
   interactively), or point them at Hub → AI (expand the profile → the "API key" row
   under the provider has a masked field) if they'd rather click through. Under
   `opencode`, a provider that isn't one of the five W shares across hosts is not
   W's to manage at all — send the user to `opencode auth login -p <provider>`
   instead of `w-ai key set`.
5. `w-ai profile use <name>` to activate it — or suggest doing it from Hub → AI
   if they're at the machine and prefer the GUI. The active profile decides
   everything: bare `w-ai`, `w-ai ask` and the desktop's Super+W palette all open
   that profile's host.
6. Confirm with `w-ai status`.

These are all plain, unprivileged, user-scope shell commands — reach for your own
shell access rather than looking for a dedicated tool; there isn't one for this
(the same reasoning as keyboard layouts and keybindings: a rootless per-user config
surface doesn't get its own tool when running the CLI directly already works).
