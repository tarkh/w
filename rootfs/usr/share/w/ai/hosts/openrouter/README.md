# W preset — OpenRouter (default provider for goose)

OpenRouter is a pay-per-use hub to 500+ models behind one OpenAI-compatible key.
It is W's default `PROVIDER` for the goose host — no separate host to install,
just a key.

## Set it up

```
w-ai key set openrouter          # paste your key; stored in gnome-keyring
```

Then in `ai.conf` (system default already `PROVIDER=openrouter`):

```
HOST=goose
PROVIDER=openrouter
MODEL=anthropic/claude-sonnet-5   # any OpenRouter model id
```

Launch with `w-ai`. The wrapper looks up the key from the keyring and exports it
as `OPENROUTER_API_KEY` (see `PROVIDER_ENV_openrouter` in ai.conf) — nothing is
written to disk in plaintext.

## Why this shape

OpenRouter is a *provider*, not a host: any OpenAI-compatible host (goose, and
provider CLIs in OpenAI-compat mode) can point at it. Model routing across cheap
and frontier models lives here — see ai-integration.md §7.
