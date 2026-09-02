---
name: ai-extra
description: >-
  Managing the `ai-extra` W-Pack: local model inference (Ollama), the embedding
  model behind semantic memory, and the CLI tools that upgrade the system AI's
  web-access chains (ddgs, trafilatura). Load this when the user asks about local
  models, Ollama, semantic/vector memory setup, or why web search/reader quality
  changed — and `w-pack status ai-extra` reports installed.
---

# W-Pack: ai-extra

Advanced, opt-in AI stack on top of the always-present system AI. Never offered in
the TUI installer (`INSTALLER=off` in its `meta.conf`) — install from the running
system only. Curated into `/usr/share/w/ai/skills/ai-extra/` when installed.

## What the user has

- **Local inference engine:** Ollama, package variant matched to the GPU at
  install time (`ollama` / `ollama-cuda` / `ollama-rocm`), service `ollama.service`
  listening on `127.0.0.1:11434`. Models live in `/var/lib/ollama` (a nested btrfs
  subvolume, excluded from root snapshots).
- **Embedding model:** `qllama/bge-m3:q8_0` (~635MB, multilingual, dense 1024-dim,
  8K context) — pulled at install time if network was available. Backs the
  semantic-memory layer: set `W_AI_EMBED=ollama` in `~/.config/w/ai-features.conf`
  (or `w-ai features set W_AI_EMBED ollama`) to turn it on — `w_memory_search`/
  `w-ai memory search` then also catches cross-language recall (a Russian fact
  found by an English query, or vice versa) and paraphrases, hybridized with the
  existing keyword search via reciprocal-rank fusion. Off by default; degrades
  silently to keyword-only search if Ollama isn't reachable.
- **Web CLIs:** `ddgs` and `trafilatura`, installed via `uv tool install` for the
  target user (land in `~/.local/bin`). The moment they exist, `w-web`'s search
  and extract chains pick them up automatically — no config change needed.
- **`python-numpy`:** brute-force cosine search over embedding vectors (used by the
  semantic-memory layer, not by anything in this bundle directly).

## Common operations

- Ollama status: `systemctl status ollama` / `ollama list` (installed models).
- Re-pull the embedding model (e.g. it failed offline at install time):
  `ollama pull qllama/bge-m3:q8_0`.
- Pull an additional chat/completion model for local inference:
  `ollama pull <model>` (any tag from ollama.com's library), then point a
  `w-ai profile` at `HOST=local`/`PROVIDER=ollama`/that model.
- Remove an unwanted model: `ollama rm <model>`.
- Check the whole advanced-feature status: `w-ai features` (add `--porcelain` for
  a machine-readable form) — reports ddgs/trafilatura/ollama/model/numpy detection,
  the current toggles, and the size of the embedded-vector corpus.
- Change a toggle: `w-ai features set <KEY> <value>` — `W_AI_EMBED` (`off`|`ollama`),
  `W_AI_EMBED_MODEL`, `W_AI_EMBED_URL`, `W_AI_EMBED_KEEPALIVE` (Ollama `keep_alive`
  sent with every embed request — how long the embedding model stays resident in
  VRAM after last use before Ollama unloads it, e.g. `30s` on a GPU shared with
  other workloads, `5m` default, `30m`+ if you embed often; scoped to this model
  only — any other Ollama model you run, e.g. a `HOST=local` chat model, keeps its
  own independent lifecycle), `W_AI_SEARCH_PROVIDER`. Toggles live in
  `~/.config/w/ai-features.conf` (a separate user file so `w-ai profile use`
  swapping profiles never wipes them). The same toggles are also reachable from
  **Hub → AI → Advanced** (a `SelectRow` for web search provider/semantic memory,
  plus status-only rows for Reader/Local models) — greyed out with a one-click
  Install button until this pack is present.

## Gotchas

- **PATH:** `uv tool install` binaries land in `~/.local/bin`. The session-wide
  `PATH` fix applies at next login; `modules/web.py`'s `_which()` also probes
  `~/.local/bin` directly so the chains work in the *current* session right after
  install, without a relogin.
- **Model pull needs network:** if the machine was offline at install time, the
  bundle still succeeds (setup is best-effort) — re-pull manually with the command
  above.
- **GPU variant is picked once:** if you swap GPU vendors later, `w-pack install
  ai-extra` again will warn rather than replace an already-installed variant
  (avoids mixing `ollama`/`ollama-cuda`/`ollama-rocm`) — remove the old package
  yourself first if you want the new variant.
- **No config to reset:** this bundle carries no `manifest` — there is nothing for
  `w-reset ai-extra` to do beyond the (nonexistent) config files. Feature toggles
  are plain user preference, not a "default" to revert to.

## Reset / remove

- Bundle removal is a later phase (shared pacman deps, and Ollama models are large
  — decide deliberately) — do not `pacman -Rns` the stack manually without
  checking dependents.
