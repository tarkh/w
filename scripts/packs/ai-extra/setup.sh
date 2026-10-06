#!/usr/bin/env bash
# ai-extra bundle — MACHINE layer. Run by `w-pack install` AFTER packages and
# config (none — this bundle ships no manifest), always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Installs the local-inference/embedding engine (Ollama base + GPU backend matched
# to the machine — same vendor detection as mod_gpu) and pulls the default embedding
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

# ── 1. Ollama — base + GPU backend (via the shared w-gpu-lib.sh seam) ────────
# Repo-only packages (no AUR), so a plain pacman is enough — pkgs.txt cannot list a
# fixed name because the right backend depends on the machine.
info "Detecting GPU vendor for the Ollama backend package..."
GPU_LIB="${W_GPU_LIB:-/usr/lib/w/w-gpu-lib.sh}"
ollama_pkg="ollama"
if [[ -r "$GPU_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$GPU_LIB"
  w_gpu_has nvidia && ollama_pkg="ollama-cuda"
  w_gpu_has amd    && ollama_pkg="ollama-rocm"
else
  warn "w-gpu-lib.sh missing — cannot detect GPU, installing CPU-only ollama backend."
fi

# Arch packages Ollama as base + backend, not as competing builds: `ollama` is the
# binary, `ollama-cuda`/`ollama-rocm` are GPU backends that DEPEND on it and pull
# it in. So the base being installed says nothing about acceleration, and only
# another BACKEND means the user made their own pick (e.g. after a GPU swap) —
# that one is left alone rather than mixing providers.
installed_backend="$(pacman -Qq ollama-cuda ollama-rocm 2>/dev/null | head -1 || true)"
if [[ -n "$installed_backend" && "$installed_backend" != "$ollama_pkg" ]]; then
  warn "ollama backend '$installed_backend' already installed — leaving as-is (wanted '$ollama_pkg')."
  ollama_pkg="$installed_backend"
elif ! pacman -Qq "$ollama_pkg" &>/dev/null; then
  info "Installing $ollama_pkg..."
  pacman -S --needed --noconfirm "$ollama_pkg" || warn "pacman install of $ollama_pkg failed."
fi

# ── 2. The model store: $DIR/ollama inside the shared `ai-models` store ─────
# One store for every AI application on the machine (ai-models.conf): ComfyUI and
# InvokeAI read their weights from it, and Ollama keeps its own content-addressed
# layout (blobs/ + manifests/) in the `ollama/` subtree via OLLAMA_MODELS. The
# path is the admin's `ai-models DIR`, read here so a relocated store takes Ollama
# along. The vendor home /var/lib/ollama stays — it holds the server's identity
# key (.ollama/), which is state, not a download.
source /usr/lib/w/w-conf-lib.sh
wconf_load ai-models
DIR="$(wconf_get ai-models DIR /var/lib/w/ai-models)"

# Same rules as the comfyui/invokeai packs: absolute, no whitespace/';' (the
# drop-in is space-split by systemd), outside the system trees, parent present.
reject_dirs=('/usr' '/etc' '/boot' '/home')
check_path() {                                  # <kind> <path> <default>
  local kind="$1" p="$2" dflt="$3" d
  [[ "$p" == /* ]] || { warn "$kind '$p' not absolute — using default '$dflt'."; echo "$dflt"; return; }
  if [[ "$p" =~ [[:space:]\;] ]]; then
    warn "$kind '$p' contains whitespace or ';' — unsafe for the unit drop-in, using default '$dflt'."
    echo "$dflt"; return
  fi
  p="${p%/}"
  for d in "${reject_dirs[@]}"; do
    if [[ "$p" == "$d" || "$p" == "$d/"* ]]; then
      warn "$kind '$p' is inside the system tree $d/ — using default '$dflt'."
      echo "$dflt"; return
    fi
  done
  local parent="${p%/*}"; [[ -n "$parent" ]] || parent="/"
  if [[ ! -d "$parent" ]]; then
    warn "$kind parent '$parent' does not exist — using default '$dflt'."
    echo "$dflt"; return
  fi
  echo "$p"
}
DIR="$(check_path 'ai-models.DIR' "$DIR" /var/lib/w/ai-models)"
LEGACY="/var/lib/ollama"         # the vendor OLLAMA_MODELS (and the account's HOME)
MODELS="$DIR/ollama"

# The `w-ai` group owns the store (sysusers fragment shipped by this pack too), so
# the store has its contract owner whichever AI pack arrives first.
systemd-sysusers /usr/lib/sysusers.d/w-ai-extra.conf 2>/dev/null \
  || warn "systemd-sysusers failed — the w-ai group may not exist."

# Snapshot exclusion, same rule as the other store users: act only while absent
# or empty; off the root filesystem there is nothing to exclude.
in_root_snapshots() {
  [[ "$(findmnt -no FSTYPE --target "$1" 2>/dev/null)" == btrfs ]] \
    && [[ "$(findmnt -no TARGET --target "$1" 2>/dev/null)" == / ]]
}
info "Ensuring the shared model store $DIR..."
mkdir -p "${DIR%/*}"
if [[ ! -e "$DIR" ]] || [[ -z "$(ls -A "$DIR" 2>/dev/null)" ]]; then
  rmdir "$DIR" 2>/dev/null || true
  if btrfs subvolume create "$DIR" >/dev/null 2>&1; then
    info "Created nested subvolume $DIR (excluded from root snapshots)."
  elif in_root_snapshots "${DIR%/*}"; then
    warn "$DIR is on the root filesystem but could not be made a subvolume — it will ride in root snapshots"
  fi
  install -d -o root -g w-ai -m 2775 "$DIR" 2>/dev/null || install -d -m 2775 "$DIR"
fi
install -d -o ollama -g ollama -m 0755 "$MODELS" 2>/dev/null || warn "could not create $MODELS"
install -d -o ollama -g ollama "$LEGACY" 2>/dev/null || true

# One-time move out of the vendor path. W changed where Ollama keeps its models,
# so W carries them over — unlike a later `ai-models DIR` change, which follows
# the store contract (re-point, print the rsync line, the data stays). reflink
# makes this instant between subvolumes of one btrfs; across disks it is a copy.
# A failed copy leaves everything where it was and keeps Ollama on the old path.
has_models() { [[ -n "$(ls -A "$1/manifests" 2>/dev/null)" ]]; }
size_of()    { find "$@" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print NR":"s+0}'; }   # files:bytes — directory sizes differ per fs
if [[ "$LEGACY" != "$MODELS" ]] && has_models "$LEGACY"; then
  if has_models "$MODELS"; then
    warn "models in both $LEGACY and $MODELS — using $MODELS, leaving $LEGACY as-is (merge by hand)."
  else
    info "Moving Ollama models $LEGACY → $MODELS..."
    systemctl stop ollama.service 2>/dev/null || true
    parts=(); for d in blobs manifests metadata; do [[ -d "$LEGACY/$d" ]] && parts+=("$d"); done
    rm -rf "${parts[@]/#/$MODELS/}"
    if cp -a --reflink=auto "${parts[@]/#/$LEGACY/}" "$MODELS/" \
       && [[ "$(size_of "${parts[@]/#/$LEGACY/}")" == "$(size_of "${parts[@]/#/$MODELS/}")" ]]; then
      rm -rf "${parts[@]/#/$LEGACY/}"
      info "Moved $(du -sh "$MODELS" 2>/dev/null | cut -f1) of models to $MODELS."
    else
      rm -rf "${parts[@]/#/$MODELS/}"
      warn "copy to $MODELS failed — Ollama stays on $LEGACY. Fix the target and re-run: sudo w-pack refresh ai-extra"
      MODELS="$LEGACY"
    fi
  fi
fi

# ── 3. The drop-in (rendered from w-conf) + the service ───────────────────────
# Only OLLAMA_MODELS changes: a later Environment= line wins over the vendor one,
# HOME and the rest of the unit stay vendor. RequiresMountsFor keeps the server
# from writing into an empty mount point when the store sits on a second disk.
DROPIN_DIR="/etc/systemd/system/ollama.service.d"
DROPIN="$DROPIN_DIR/10-w.conf"
prev="$(sed -n 's/^Environment=OLLAMA_MODELS=//p' "$DROPIN" 2>/dev/null)"
want="[Unit]
RequiresMountsFor=$MODELS

[Service]
Environment=OLLAMA_MODELS=$MODELS"
changed=0
if [[ "$(cat "$DROPIN" 2>/dev/null)" != "$want" ]]; then
  mkdir -p "$DROPIN_DIR" && printf '%s\n' "$want" > "$DROPIN"
  systemctl daemon-reload
  changed=1
  info "Ollama models directory: $MODELS (drop-in $DROPIN)."
  if [[ -n "$prev" && "$prev" != "$MODELS" && "$prev" != "$LEGACY" ]] && has_models "$prev"; then
    info "Models under the previous store $prev stay where they are (W never moves them). To bring them along:"
    info "    sudo rsync -a --chown=ollama:ollama $prev/ $MODELS/ && sudo rm -rf $prev"
  fi
fi
systemd-analyze verify ollama.service >/dev/null 2>&1 \
  || warn "systemd-analyze verify found issues — inspect: systemd-analyze verify ollama.service"

info "Enabling ollama.service..."
if (( changed )) && systemctl is-active --quiet ollama.service; then
  systemctl restart ollama.service || warn "ollama.service restart failed."
fi
systemctl enable --now ollama.service || warn "ollama.service enable failed."
for _ in {1..20}; do ollama list &>/dev/null && break; sleep 0.5; done

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
