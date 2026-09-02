# W preset — Local / offline (opt-in)

The private, offline path: goose bound to a local model server. No API key, no
data leaves the machine. `HOST=local` in `ai.conf` makes `w-ai` force
`PROVIDER=ollama` and reuse the goose preset + `w-mcp` extension.

## Ollama (simplest)

```
yay -S ollama            # or the ollama-cuda / ollama-rocm variant
systemctl enable --now ollama
ollama pull llama3.1     # any tool-calling capable model
```

Then in `~/.config/w/ai.conf`:

```
HOST=local
MODEL=llama3.1
# OLLAMA_HOST=127.0.0.1:11434   # only if not the default
```

Launch with `w-ai` (or `w-ai --host local`). w-ai exports `OLLAMA_HOST` when set.

## llama.cpp + MCPHost (alternative)

`llama.cpp` (March 2026+) ships a built-in MCP client and speaks the
OpenAI-compatible API; point goose at it as an Ollama/OpenAI-compatible endpoint,
or drive `w-mcp` via `MCPHost`. This route is unmanaged by W — use it if you
prefer llama.cpp's runtime. The knowledge/actions layers (`/usr/share/w/ai`,
`w-mcp`) are identical regardless of the local runtime.

Note: local models are best for routine work (log parsing, summaries,
classification). Route hard reasoning to a frontier provider — see
ai-integration.md §7 (model routing / local-first).
