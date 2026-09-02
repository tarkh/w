# W preset — Claude Code (opt-in host)

Claude Code is a provider-native host: it carries its own login, so W never
manages a key for it. W's job is to hand it the same three layers every other
host gets — knowledge, actions, identity — **without writing anything into your
`~/.claude`**, so that a Claude Code you start yourself stays a plain Claude Code.

## Install and sign in

```
w-ai host install claude     # vendor's native installer, per-user (~/.local/bin)
w-ai host login claude       # runs `claude auth login` (browser flow)
w-ai host list               # confirm: claude / ready
```

W does not ship the binary. Claude Code updates itself and its login belongs to
your account, so it is installed per-user on demand rather than baked into the
image. The AUR package is deliberately not used: a pacman-managed binary fights
Claude Code's own updater and lags behind it.

The desktop's readiness gate (`w-ai ready`, one per `Super+W`) remembers a
*successful* `claude auth status` for 12 hours in `~/.cache/w-ai/`, so the palette
does not start a CLI just to open a text field. A failure is never remembered, and
`w-ai host login` forgets the stamp; `w-ai status` and `w-ai host list` always ask
the CLI itself, so the diagnostics never answer from the cache.

## Use it as the assistant

Make a profile active, then every entry point follows — `w-ai`, `w-ai ask`, and
the desktop's `Super+W` palette all open Claude Code instead of goose:

```
w-ai profile use claude      # or: Hub -> AI -> tap the claude profile
w-ai status
```

Subscription vs API key is the `PROVIDER` field of the profile:

| `PROVIDER` | What happens |
|---|---|
| `subscription` | Claude Code's own login. W exports **no** key. |
| `anthropic` | W exports `ANTHROPIC_API_KEY` from the keyring (`w-ai key set anthropic`) — pay-per-token API billing. |

Getting this wrong costs money in one direction only: with `ANTHROPIC_API_KEY`
present in the environment, Claude Code bills the API even for a Pro subscriber.
That is why `subscription` maps to an empty entry in the provider catalog
(`PROVIDER_ENV_subscription=` in `/usr/share/w/defaults/ai.conf`) — there is
nothing for W to export.

## What `w-ai` passes, and why it leaves no trace

```
claude --plugin-dir  /usr/share/w/ai/hosts/claude/plugin \
      [--plugin-dir  $XDG_RUNTIME_DIR/w-ai/user-plugin] \
       --mcp-config  /usr/share/w/ai/hosts/claude/mcp.json \
       --append-system-prompt-file /usr/share/w/ai/AGENTS.md \
       [--model <MODEL>] [<your question>]
```

- **`--plugin-dir`** — the knowledge layer. The plugin's `skills/` is a symlink
  to `/usr/share/w/ai/skills`, so W's skills load *in place*, for this session
  only. (Installing the same thing through a plugin marketplace would instead
  copy it into `~/.claude/plugins/cache`, where it would go stale on the next
  `w-update`.)
- **`--plugin-dir` a second time** — the skills the assistant wrote for *itself*
  (`w_skill_add` → `~/.config/w/ai/skills/`), passed only when that overlay holds
  at least one skill. `--plugin-dir` takes a plugin *root*, so `w-ai` generates a
  thin wrapper around the overlay under `$XDG_RUNTIME_DIR` (a manifest naming the
  plugin `w-user`, plus a `skills` symlink back to your overlay). It is rebuilt on
  every launch and copies nothing, so it cannot go stale, and your config
  directory stays a config directory. In the session the two trees are told apart
  by name: `w:w-network` is shipped, `w-user:<name>` is yours. A skill written
  *during* a session becomes a native skill on the **next** launch — until then it
  is still reachable, as always, through `w_search_knowledge`.
- **`--mcp-config`** — the actions layer, `w-mcp`. Kept *outside* the plugin on
  purpose: a plugin-bundled server registers as `plugin:w:w-mcp` and its tools
  as `mcp__w:w-mcp__*`, which no permission rule or skill written against the
  normal `mcp__w-mcp__*` name would match. Not `--strict-mcp-config`, so your own
  MCP servers still load alongside it.
- **`--append-system-prompt-file`** — identity. Claude Code does **not** read
  `AGENTS.md` on its own (it reads `CLAUDE.md`, walking up from the working
  directory), so W passes it explicitly. Being stable and first in the context,
  it is also what makes the prompt cache work (ai-integration.md §7).

Memory, tool tiers and polkit need no flags: they arrive through `w-mcp` exactly
as they do under goose. A privileged (Tier-2) tool still raises W's own polkit
prompt — the host's own approval mode is UX, not the security boundary.

## Working on someone else's code

Just run `claude` directly. None of the above applies: no W skills, no `w-mcp`,
no W identity — a normal Claude Code in that project. The split is the launch
command, not a setting to remember to toggle.

## Manual MCP registration (optional)

If you want `w-mcp` in a bare `claude` too — say, while working on a project that
configures this machine — register it yourself, per project or per user:

```
claude mcp add w-mcp -- w-mcp        # user scope
```

Or drop a `.mcp.json` in the project root:

```json
{ "mcpServers": { "w-mcp": { "command": "w-mcp", "args": [] } } }
```
