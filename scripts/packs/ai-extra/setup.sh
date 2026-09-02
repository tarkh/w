#!/usr/bin/env bash
# ai-extra bundle — MACHINE layer. Run by `w-pack install` AFTER packages and
# config (none — this bundle ships no manifest), always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Installs the local-inference/embedding engine (Ollama, GPU-variant matched to
# the machine — same vendor detection as mod_gpu) and pulls the default embedding
# model. All of that is shared: one engine, one model store, one service for the
# whole machine.
#
# The per-account half — the uv-managed CLI tools that land in ~/.local/bin — is
# in setup-user.sh, because it reaches exactly one home and therefore has to be
# runnable again, per account, via `w-pack setup ai-extra`.
#
# Idempotent; best-effort — a hiccup warns rather than aborting (packages are
# already deployed by the time this runs). See ai-integration.md / pack-ai-extra.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. Ollama — GPU-variant package (mirrors mod_gpu's vendor detection) ─────
# Repo-only packages (no AUR), so a plain pacman is enough — pkgs.txt cannot list a
# fixed name because the right variant depends on the machine.
info "Detecting GPU vendor for the Ollama package variant..."
gpu_lines="$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)"
ollama_pkg="ollama"
echo "$gpu_lines" | grep -qi '\[10de:' && ollama_pkg="ollama-cuda"
echo "$gpu_lines" | grep -qi '\[1002:' && ollama_pkg="ollama-rocm"

# If a different variant is already installed, leave it alone (e.g. the user
# switched GPUs and hand-picked a variant) rather than mixing providers.
installed_variant="$(pacman -Qq 2>/dev/null | grep -E '^ollama(-cuda|-rocm)?$' | head -1 || true)"
if [[ -n "$installed_variant" && "$installed_variant" != "$ollama_pkg" ]]; then
  warn "ollama variant '$installed_variant' already installed — leaving as-is (wanted '$ollama_pkg')."
  ollama_pkg="$installed_variant"
elif [[ -z "$installed_variant" ]]; then
  info "Installing $ollama_pkg..."
  pacman -S --needed --noconfirm "$ollama_pkg" || warn "pacman install of $ollama_pkg failed."
fi

# ── 2. /var/lib/ollama as a nested btrfs subvolume (snapshot exclusion) ───────
# Models are large (hundreds of MB to GB) and fully re-downloadable — they do not
# belong inside root's snapper snapshots (non-recursive; nested subvolume is
# naturally excluded). Must exist BEFORE the first model pull/service start — an
# existing populated dir cannot be converted in place, so only act while absent or
# empty (see snapshots.md).
STORE="/var/lib/ollama"
info "Ensuring the Ollama model store is snapshot-excluded..."
if [[ ! -e "$STORE" ]] || [[ -z "$(ls -A "$STORE" 2>/dev/null)" ]]; then
  rmdir "$STORE" 2>/dev/null || true
  if btrfs subvolume create "$STORE" >/dev/null 2>&1; then
    chown ollama:ollama "$STORE" 2>/dev/null || true
    info "Created nested subvolume $STORE (excluded from root snapshots)."
  else
    install -d -o ollama -g ollama "$STORE" 2>/dev/null || install -d "$STORE"
    warn "not on btrfs (or subvolume create failed) — plain dir; no snapshot exclusion"
  fi
elif btrfs subvolume show "$STORE" >/dev/null 2>&1; then
  info "$STORE already a subvolume — nothing to do."
else
  warn "$STORE already exists as a regular populated dir — leaving as-is (will ride in root snapshots)"
fi

# ── 3. Enable the service ──────────────────────────────────────────────────────
info "Enabling ollama.service..."
systemctl enable --now ollama.service || warn "ollama.service enable failed."

# ── 4. Embedding model (best-effort, needs network) ───────────────────────────
# qllama/bge-m3:q8_0 — Q8_0 quantization of BAAI/bge-m3 (multilingual, dense 1024,
# 8K context), ~635MB; verified live on ollama.com 2026-07-25 (654.9K downloads).
# Q8_0 is near-lossless for embedders; the official ollama.com/library/bge-m3 has
# no q8_0 tag (only latest/fp16 at 1.2GB), hence the community quantization.
# Machine-scope: the model store is shared, so this is pulled once, not per account.
EMBED_MODEL="qllama/bge-m3:q8_0"
info "Pulling embedding model $EMBED_MODEL (best-effort, needs network)..."
if command -v ollama >/dev/null; then
  if ollama pull "$EMBED_MODEL"; then
    info "Embedding model ready."
  else
    warn "ollama pull $EMBED_MODEL failed — no network at install time? Retry later: ollama pull $EMBED_MODEL"
  fi
else
  warn "ollama binary not found — package install above must have failed. Skipping model pull."
fi

# ── 5. Offline verification ───────────────────────────────────────────────────
# No network calls here — the model pull above already tried, and its outcome
# does not gate bundle success (it may legitimately be offline at install time).
info "Verifying ai-extra machine components (offline)..."
command -v ollama >/dev/null && info "ollama: OK" || warn "ollama: binary not found"
if python3 -c "import numpy" 2>/dev/null; then
  info "python-numpy: OK"
else
  warn "python-numpy: import failed — package install above may have failed."
fi

info "ai-extra machine setup complete."
exit 0
