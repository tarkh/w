# W preset — Codex CLI (opt-in host)

Codex is a provider-native host: it carries its own login (ChatGPT account), so
W never manages a key for it. W's job is to hand it the same layers every other
host gets — actions, identity, knowledge — **without writing anything into your
`~/.codex`**, so that a Codex you start yourself stays a plain Codex.

## Install and sign in

```
w-ai host install codex      # OpenAI's standalone installer, per-user (~/.local/bin)
w-ai host login codex        # runs `codex login` (browser flow)
w-ai host list               # confirm: codex / signed-in
```

W does not ship the binary. Codex updates itself (`codex update`) and its login
belongs to your account, so it is installed per-user on demand rather than baked
into the image. The AUR package is deliberately not used: a pacman-managed binary
fights Codex's own updater and lags behind it. On a machine without a browser,
`codex login --device-auth` runs the same sign-in as a device-code flow.

The desktop's readiness gate (`w-ai ready`, one per `Super+W`) remembers a
*successful* `codex login status` for 12 hours in `~/.cache/w-ai/`, so the
palette does not start a CLI just to open a text field. A failure is never
remembered, and `w-ai host login` forgets the stamp.

## Use it as the assistant

Make a profile active, then every entry point follows — `w-ai`, `w-ai ask`, and
the desktop's `Super+W` palette all open Codex instead of goose:

```
w-ai profile use codex       # or: Hub -> AI -> tap the codex profile
w-ai status
```

Subscription vs API key is the `PROVIDER` field of the profile:

| `PROVIDER` | What happens |
|---|---|
| `subscription` | Codex's own login. W exports **no** key. |
| `openai` | W exports `OPENAI_API_KEY` from the keyring (`w-ai key set openai`) — pay-per-token API billing. |

Getting this wrong costs money in one direction only, which is why
`subscription` maps to an empty entry in the provider catalog
(`PROVIDER_ENV_subscription=` in `/usr/share/w/defaults/ai.conf`) — there is
nothing for W to export.

## What `w-ai` passes, and why it leaves no trace

```
codex -c 'mcp_servers.w-mcp.command="w-mcp"' \
      -c 'developer_instructions="<contents of /usr/share/w/ai/AGENTS.md>"' \
      [--model <MODEL>] [<your question>]
```

Codex has no flag that takes a config *file* for one run, but `-c key=value`
overrides any config key for that invocation — and that is enough for both
layers, with nothing written to `~/.codex/config.toml`:

- **`-c mcp_servers.w-mcp.command`** — the actions layer, `w-mcp`: the machine's
  state, W's tools, the shared memory. Registered under its plain name, so tool
  names match what W's skills and docs say. Your own MCP servers from
  `~/.codex/config.toml` still load alongside it.
- **`-c developer_instructions`** — identity. Codex reads `AGENTS.md` from the
  project it is started in and from `~/.codex/`, neither of which is W's to
  write to, so W passes the file's text inline as developer instructions.
- **Knowledge** — W's skills reach Codex through `w-mcp`, exactly as they reach
  goose: as MCP resources and through `w_search_knowledge`. Codex discovers
  native skills only from fixed paths (`~/.agents/skills`, `/etc/codex/skills`,
  the repository), none of which can be handed to a single launch, and W does
  not touch them.

Memory, tool tiers and polkit need no flags: they arrive through `w-mcp`
exactly as they do under goose. A privileged (Tier-2) tool still raises W's own
polkit prompt — Codex's approval and sandbox settings are its UX, not the
security boundary. MCP servers run outside Codex's command sandbox.

## Working on someone else's code

Just run `codex` directly. None of the above applies: no `w-mcp`, no W identity
— a normal Codex in that project. The split is the launch command, not a
setting to remember to toggle.

## Optional: W's skills as native Codex skills

If you want W's skills in the `/skills` picker of *every* Codex on this machine
(the bare one included), point Codex's admin skill root at W's tree:

```
sudo ln -s /usr/share/w/ai/skills /etc/codex/skills
```

## Optional: `w-mcp` in a bare `codex`

If you want `w-mcp` available without going through `w-ai` — say, while working
on a project that configures this machine — register it yourself:

```
codex mcp add w-mcp -- w-mcp
```

or in `~/.codex/config.toml`:

```toml
[mcp_servers.w-mcp]
command = "w-mcp"
```
