# W preset — OpenCode (opt-in host)

OpenCode is a hybrid host: it carries its own subscription (**Zen**), the way
Claude Code and Codex carry theirs, but it also speaks to the full
[models.dev](https://models.dev) provider catalog — dozens of vendors, not
just one — the way goose does. W's job is the same as for every other host:
hand it actions, identity and approval as **launch flags**, writing nothing
into your `~/.config/opencode`, so an `opencode` you start yourself elsewhere
stays a plain OpenCode.

## Install and sign in

```
w-ai host install opencode      # OpenCode's own installer, per-user (~/.opencode/bin)
w-ai host login opencode        # runs `opencode auth login` (interactive picker)
w-ai host list                  # confirm: opencode / signed-in
```

W does not ship the binary. OpenCode updates itself (`opencode upgrade`, and
auto-checks at startup) and its logins belong to your account, so it is
installed per-user on demand rather than baked into the image — same reasoning
as Claude Code and Codex, not the AUR.

`opencode auth login` with no arguments opens an interactive picker covering
every provider OpenCode knows, Zen included — one command handles "sign in to
my subscription" and "sign in to some other vendor" alike.

## Use it as the assistant

Make a profile active, then every entry point follows — `w-ai`, `w-ai ask`, and
the desktop's `Super+W` palette all open OpenCode instead of goose:

```
w-ai profile use opencode       # or: Hub -> AI -> tap the opencode profile
w-ai status
```

### Provider: subscription, one of W's five, or anything else

Unlike Claude Code/Codex, OpenCode's `PROVIDER` field is **not** a closed
choice between "subscription" and one API vendor — `host.conf` leaves
`AUTH_MODES` open, exactly like goose:

| `PROVIDER` | What happens |
|---|---|
| `subscription` | OpenCode's own Zen login. W exports **no** key. |
| `anthropic` / `openai` / `google` / `openrouter` / `ollama` | W exports the matching key from the keyring (`w-ai key set <provider>`) — same catalog every other host shares. |
| anything else models.dev lists (mistral, groq, deepseek, xai, …) | **W does nothing at all.** Configure it directly in OpenCode itself — `opencode auth login -p <provider>` — and it lands in OpenCode's own credential store (`~/.local/share/opencode/auth.json`), independent of W's keyring. `w-ai status`/`key list` won't show it; that is expected, not a bug. |

This is deliberate: teaching W's keyring about every one of the dozens of
providers OpenCode can reach would mean growing the shared catalog forever for
a benefit OpenCode's own auth already provides. W only manages the handful of
providers every host shares, plus its own subscription entry point; anything
more exotic is OpenCode's native business.

Getting the subscription case wrong costs money in one direction: with an API
key present in the environment, most CLIs in this family bill the API instead
of the subscription — which is why `subscription` maps to an empty entry in
the provider catalog (`PROVIDER_ENV_subscription=` in
`/usr/share/w/defaults/ai.conf`) and W never exports anything for it.

## What `w-ai` passes, and why it leaves no trace

OpenCode has no per-run config-file flag, but it does have something better for
this purpose: **`OPENCODE_CONFIG_CONTENT`**, an environment variable holding an
inline JSON config that sits above your global `~/.config/opencode/opencode.json`
in OpenCode's own precedence chain (and below a project's own config) — so
nothing is ever written to disk, and this layer disappears the moment the
process exits.

```
OPENCODE_CONFIG_CONTENT='{
  "mcp": { "w-mcp": { "type": "local", "command": ["w-mcp"], "enabled": true } },
  "permission": { "mcp": { "w-mcp_*": "allow" } },
  "instructions": ["/usr/share/w/ai/AGENTS.md"]
}' opencode [--model <MODEL>]                        # bare session
# or, seeded (a bare positional prompt is a PROJECT PATH, not a question):
OPENCODE_CONFIG_CONTENT='…' opencode run "<your question>" --interactive [--model <MODEL>]
```

- **`mcp`** — the actions layer, `w-mcp`, registered under its plain name (tool
  names match what W's skills and docs say), plus one entry per active `mcp.d`
  pack server. Your own servers from `~/.config/opencode/opencode.json` still
  load alongside it — this is a config *layer*, not a replacement file.
- **`permission.mcp`** — OpenCode's per-server trust pattern (`<server>_<tool>`
  globs). `w-mcp_*` (and one entry per pack server) skips OpenCode's per-call
  approval prompts for W-curated tools only; a server you registered by hand
  keeps OpenCode's normal confirmation flow. Same trust line as Codex's
  `default_tools_approval_mode="approve"` and Claude Code's `--allowedTools` —
  W's tools are tier-audited and the privileged ones stop at W's own polkit
  prompt regardless, so a host-side confirm on top would be double-gating.
- **`instructions`** — identity, by absolute path, not inlined text. OpenCode
  is the one host in this family that reads `AGENTS.md` **on its own**
  (walking up from the project, plus `~/.config/opencode/AGENTS.md`) — so this
  entry does not replace that discovery, it *adds* W's system identity on top
  of whatever a project already contributes. Working in some other project
  under `w-ai --host opencode` gets both.
- **Knowledge** — same as under Codex: OpenCode has fixed skill-discovery paths
  and no per-launch skill-root flag, so W's skills are not shipped as native
  OpenCode skills (yet — see the project backlog for that). They reach OpenCode
  through `w-mcp` instead: the skill catalog rides the server's `instructions`
  (OpenCode shows it as the description of its `mcp__w_mcp`-style tool
  surface), and a skill's body is one `w_skill_read(name)` call away.
- **`--model`** — only passed when a profile pins one (`NEEDS_MODEL=no`:
  OpenCode picks interactively otherwise).

**Confirmed on the VM (2026-09-16, OpenCode 1.18.31, no login — a free
built-in model was enough):** `opencode debug config` shows `OPENCODE_CONFIG_CONTENT`
deep-merging its `mcp`/`permission`/`instructions` keys into the resolved
config alongside the existing `agent`/`mode`/`plugin`/`command`/`username`
fields — a layer, not a replacement — and `opencode mcp list` showed `w-mcp
✓ connected`. A live `w_time_status` tool call through it answered correctly.
**One thing the docs got wrong:** a bare positional prompt (`opencode
"<question>"`) is **not** a seed prompt the way it is under Claude Code and
Codex — it fails with "Failed to change directory to ~/<question>" because
the bare command's positional argument is a **project path**. The seed +
continue equivalent, confirmed working end-to-end, is `opencode run
"<question>" --interactive` (the same shape as goose's `run -t … --interactive`) —
that is what `w-ai ask` uses.

## Working on someone else's code

Just run `opencode` directly. None of the above applies: no `w-mcp`, no W
identity beyond whatever `AGENTS.md`/`.opencode` config that project already
has — a normal OpenCode in that project.

## Optional: `w-mcp` in a bare `opencode`

If you want `w-mcp` available without going through `w-ai`, add it to your own
`~/.config/opencode/opencode.json`:

```json
{ "mcp": { "w-mcp": { "type": "local", "command": ["w-mcp"], "enabled": true } } }
```
