#!/usr/bin/env bash
# invokeai bundle — MACHINE layer. Run by `w-pack install` AFTER packages and
# config are deployed, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Installs InvokeAI the way upstream's manual install does — a uv virtualenv on
# a uv-managed Python 3.12 plus `uv pip install invokeai --torch-backend=<gpu>` —
# under the `invokeai` service account, then renders a drop-in pointing the
# shipped unit at the admin's paths and at the shared model store. It enables
# NOTHING: InvokeAI is a pull-the-trigger service, like comfyui.
#
# Two admin-set paths, read BEFORE any step (they may predate the pack):
#   invokeai.ROOT  engine + venv + runtime root   (default /var/lib/w/invokeai)
#   ai-models.DIR  the machine-wide model store   (default /var/lib/w/ai-models)
# REFRESH re-reads them and re-renders the drop-in; it never rebuilds an
# existing venv (the check in step 5 IS the idempotency guard).
#
# Idempotent; best-effort — a hiccup warns rather than aborting. The path,
# identity and store steps mirror the comfyui pack line for line on purpose:
# both engines share one store contract. See pack-invokeai.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 0. The admin's choices (w-conf) ───────────────────────────────────────────
source /usr/lib/w/w-conf-lib.sh
wconf_load invokeai
wconf_load ai-models
ROOT="$(wconf_get invokeai ROOT /var/lib/w/invokeai)"
LISTEN="$(wconf_get invokeai LISTEN 127.0.0.1)"
PORT="$(wconf_get invokeai PORT 9090)"
GPU="$(wconf_get invokeai GPU auto)"
VERSION="$(wconf_get invokeai VERSION latest)"   # the release a fresh venv gets
DIR="$(wconf_get ai-models DIR /var/lib/w/ai-models)"

# ── 1. Path validation ────────────────────────────────────────────────────────
# Absolute, outside the system trees, no whitespace/';' (the drop-in is
# space-split by systemd), ROOT and DIR not nested in each other, parent present
# and not noexec (the venv must carry a runnable python). Same rules as comfyui.
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
  if [[ -n "${ROOT_OK:-}" && ( "$p" == "$ROOT_OK"/* || "$ROOT_OK" == "$p"/* ) ]]; then
    warn "$kind '$p' nests inside the engine root — using default '$dflt'."
    echo "$dflt"; return
  fi
  local parent="${p%/*}"; [[ -n "$parent" ]] || parent="/"
  if [[ ! -d "$parent" ]]; then
    warn "$kind parent '$parent' does not exist — using default '$dflt'."
    echo "$dflt"; return
  fi
  if findmnt -no OPTIONS --target "$parent" 2>/dev/null | tr ',' '\n' | grep -qx noexec; then
    warn "$kind parent '$parent' is mounted noexec — using default '$dflt' (a venv needs a runnable python)."
    echo "$dflt"; return
  fi
  echo "$p"
}
ROOT_OK="$(check_path 'invokeai.ROOT' "$ROOT" /var/lib/w/invokeai)"
ROOT="$ROOT_OK"
DIR="$(check_path 'ai-models.DIR' "$DIR" /var/lib/w/ai-models)"
OWN="$DIR/invokeai"            # InvokeAI's own downloads — the only tree it deletes from

# ── 2. Identities: the `invokeai` account and the `w-ai` store group ─────────
info "Provisioning the 'invokeai' service account and 'w-ai' store group..."
systemd-sysusers /usr/lib/sysusers.d/w-invokeai.conf 2>/dev/null \
  || warn "systemd-sysusers failed — accounts/group may not exist."
if [[ "$(getent passwd invokeai | cut -d: -f6)" != "$ROOT" ]]; then
  if systemctl is-active --quiet invokeai.service 2>/dev/null; then
    # usermod -d refuses while the account owns a live process; the runtime does
    # not read the passwd home (HOME=$ROOT is explicit in the drop-in).
    warn "invokeai home still points at the old ROOT — it re-syncs on a refresh taken while the service is stopped."
  else
    usermod -d "$ROOT" invokeai 2>/dev/null && info "invokeai home set to $ROOT." \
      || warn "could not set invokeai home to $ROOT."
  fi
fi

# ── 3. ROOT and DIR as nested btrfs subvolumes (snapshot exclusion) ───────────
# Same rule as comfyui/ai-extra: act only while absent or empty; a populated dir
# is left as-is; off the root filesystem there is nothing to exclude.
in_root_snapshots() {
  [[ "$(findmnt -no FSTYPE --target "$1" 2>/dev/null)" == btrfs ]] \
    && [[ "$(findmnt -no TARGET --target "$1" 2>/dev/null)" == / ]]
}
ensure_subvol() {                              # <owner> <group> <mode> <path>
  local owner="$1" group="$2" mode="$3" p="$4"
  if [[ ! -e "$p" ]] || [[ -z "$(ls -A "$p" 2>/dev/null)" ]]; then
    rmdir "$p" 2>/dev/null || true
    if btrfs subvolume create "$p" >/dev/null 2>&1; then
      chown "$owner:$group" "$p"; chmod "$mode" "$p"
      info "Created nested subvolume $p (excluded from root snapshots)."
    else
      install -d -o "$owner" -g "$group" -m "$mode" "$p" 2>/dev/null || install -d -m "$mode" "$p"
      if in_root_snapshots "$p"; then
        warn "$p is on the root filesystem but could not be made a subvolume — it will ride in root snapshots"
      else
        info "Created $p on $(findmnt -no FSTYPE --target "$p") at $(findmnt -no TARGET --target "$p") — outside root snapshots already."
      fi
    fi
  elif btrfs subvolume show "$p" >/dev/null 2>&1; then
    info "$p already a subvolume — nothing to do."
  elif in_root_snapshots "$p"; then
    warn "$p already exists as a regular populated dir on the root filesystem — leaving as-is (it will ride in root snapshots)"
  else
    info "$p already exists — leaving as-is (on $(findmnt -no TARGET --target "$p"), outside root snapshots)."
  fi
}
mkdir -p /var/lib/w
ensure_subvol invokeai w-ai 750 "$ROOT"
ensure_subvol root w-ai 2775 "$DIR"

# ── 4. Store layout: the canonical class folders + InvokeAI's own subtree ────
# The class folders are the ai-models contract (ComfyUI's layout) — created here
# too, so the store is complete whichever engine arrives first. `invokeai/` is
# where InvokeAI's model manager downloads to (INVOKEAI_MODELS_DIR): its own
# layout, invisible to ComfyUI (which reads only the class folders), and the one
# subtree InvokeAI deletes files from when a model is removed in its interface.
info "Laying out the shared model store under $DIR..."
for d in checkpoints diffusion_models loras vae clip clip_vision text_encoders \
         controlnet embeddings upscale_models unet style_models video_models inpaint \
         hf invokeai; do
  install -d -o root -g w-ai -m 2775 "$DIR/$d" 2>/dev/null || warn "could not create $DIR/$d"
done

# ── 5. The virtualenv (only while absent) ─────────────────────────────────────
# Upstream's manual install, verbatim in substance: a relocatable venv on a
# uv-managed Python 3.12 (invokeai requires <3.13, and the system python is
# newer), then the package with uv's torch-backend selection. Everything runs as
# the service account with HOME=$ROOT, so the managed interpreter and the uv
# cache land under $ROOT, never in someone's ~ or on the system disk.
run_as_invoke() {
  ( cd "$ROOT" && runuser -u invokeai -- env HOME="$ROOT" PATH="/usr/bin:/bin" "$@" )
}
# The torch backend is decided only when a venv is actually built — a refresh
# over an existing one must not re-detect (or re-warn about) the hardware.
pick_backend() {
  local GPU_LIB="${W_GPU_LIB:-/usr/lib/w/w-gpu-lib.sh}"
  case "$GPU" in
    nvidia) backend=cu128 ;;
    amd)    backend=rocm7.2 ;;
    intel)  backend=xpu ;;
    cpu)    backend=cpu ;;
    auto)
      if [[ -r "$GPU_LIB" ]]; then
        # shellcheck source=/dev/null
        source "$GPU_LIB"
        if   w_gpu_has nvidia;     then backend=cu128
        elif w_gpu_has amd;        then backend=rocm7.2
        elif w_gpu_intel_discrete; then backend=xpu
        elif w_gpu_has intel; then
          backend=cpu; warn 'Intel graphics found, but not a supported discrete Arc/Battlemage — installing CPU-only (generation will be slow).'
        else backend=cpu; warn 'no supported GPU matched — installing CPU-only (generation will be slow).'
        fi
      else
        backend=cpu; warn "w-gpu-lib.sh missing — cannot detect GPU, installing CPU-only."
      fi ;;
    *) warn "GPU='$GPU' unknown (nvidia|amd|intel|cpu|auto) — falling back to CPU."; backend=cpu ;;
  esac
}

VENV="$ROOT/app/.venv"
if [[ -x "$VENV/bin/invokeai-web" ]]; then
  info "$VENV exists — InvokeAI already installed; refresh leaves it alone."
elif ! command -v uv >/dev/null 2>&1; then
  warn "uv not found — InvokeAI cannot be installed. Install uv (apply.sh --uv) and run 'w-pack refresh invokeai'."
else
  pick_backend
  pkg=invokeai; [[ "$VERSION" == latest ]] || pkg="invokeai==${VERSION#v}"
  info "Installing InvokeAI into $VENV (torch backend: $backend)..."
  run_as_invoke mkdir -p "$ROOT/app"
  # rocm7.2, not the rocm7.1 the manual still names: torch 2.12 on the 7.1 index
  # breaks generation (InvokeAI #9410), closed upstream on 2.13/2.14+rocm7.2 —
  # the index the comfyui pack uses too.
  if run_as_invoke uv venv --relocatable --prompt invoke --python 3.12 \
       --python-preference only-managed "$VENV" \
     && run_as_invoke uv pip install --python "$VENV/bin/python" \
       --python-preference only-managed --torch-backend="$backend" "$pkg"; then
    info "InvokeAI $("$VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("invokeai"))' 2>/dev/null) installed."
  else
    # A half-built venv would pass the guard above on the next refresh only if
    # the entry point exists — it does not, so the retry rebuilds from scratch.
    rm -rf "$VENV"
    warn "InvokeAI install failed — the engine is not ready. Retry: sudo w-pack refresh invokeai"
  fi
fi

# ── 5b. PatchMatch (canvas infill) against the system OpenCV ─────────────────
# pypatchmatch compiles its C++ extension on first import — but only while the
# .so is absent, and it looks OpenCV up as `opencv`/`opencv4` in pkg-config. Arch
# ships OpenCV 5 (`opencv5.pc`), so the engine's own build finds no headers, and
# the full opencv5 link line would pull in every module — `viz` needs VTK, which
# is not installed, so the library would build and then fail to load. Built here
# instead, against a throwaway `opencv4.pc` alias naming only the four modules
# the code uses (core, imgproc, imgcodecs, highgui — the last for its debug
# imshow; it links the Qt6 W already carries). Rebuilt on refresh when ldd finds
# a library gone — an OpenCV soname bump — since the engine never rebuilds an
# existing .so on its own.
PM="$(compgen -G "$VENV/lib/python3*/site-packages/patchmatch" | head -1)"
if [[ -n "$PM" ]] && { [[ ! -f "$PM/libpatchmatch.so" ]] || ldd "$PM/libpatchmatch.so" | grep -q 'not found'; }; then
  info "Building PatchMatch (canvas infill) against the system OpenCV..."
  pc="$(mktemp -d)"; chmod 755 "$pc"
  if ! pkg-config --exists opencv4 && pkg-config --exists opencv5; then
    printf 'Name: opencv4\nDescription: W alias for PatchMatch\nVersion: 5\nCflags: %s\nLibs: -lopencv_core -lopencv_imgproc -lopencv_imgcodecs -lopencv_highgui\n' \
      "$(pkg-config --cflags opencv5)" > "$pc/opencv4.pc"
  fi
  run_as_invoke env PKG_CONFIG_PATH="$pc" make -s -C "$PM" clean >/dev/null 2>&1
  if run_as_invoke env PKG_CONFIG_PATH="$pc" make -s -C "$PM" >/dev/null 2>&1 \
     && ! ldd "$PM/libpatchmatch.so" | grep -q 'not found'; then
    info "PatchMatch built."
  else
    rm -f "$PM/libpatchmatch.so"
    warn "PatchMatch build failed (is the opencv package installed?) — the canvas falls back to its other infill methods."
  fi
  rm -rf "$pc"
fi

# ── 6. Runtime root + human access ────────────────────────────────────────────
# $ROOT/data is INVOKEAI_ROOT: invokeai.yaml, databases/, outputs/, nodes/. The
# engine creates its tree on first start; setup only makes outputs/ exist early
# so the group contract below can apply to it. Same boundary as comfyui: w-ai
# members traverse $ROOT and read/write the generated images; nodes/ (code the
# engine imports) stays private. Targeted, never recursive.
run_as_invoke mkdir -p "$ROOT/data/outputs"
info "Opening the engine tree to group w-ai (traverse + outputs)..."
chown invokeai:w-ai "$ROOT" "$ROOT/data" && chmod 0750 "$ROOT" "$ROOT/data" \
  || warn "could not set w-ai group access on $ROOT."
chown invokeai:w-ai "$ROOT/data/outputs" && chmod 2770 "$ROOT/data/outputs" \
  || warn "could not make $ROOT/data/outputs group-writable for w-ai."

# ── 7. Drop-in: the runtime, locked to w-conf (never edit the vendor unit) ────
# W-owned settings go in as INVOKEAI_* variables: the engine merges its own
# invokeai.yaml WITHOUT clobbering the environment, so the admin tunes the engine
# in that file and w-conf keeps the address and the model tree. Every list
# setting is reset first (a drop-in appends to the base unit's value), ExecStart
# included — two ExecStart lines on a non-oneshot unit are refused.
DROPIN_DIR="/etc/systemd/system/invokeai.service.d"
DROPIN="$DROPIN_DIR/10-w.conf"
info "Rendering the runtime drop-in $DROPIN..."
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" <<EOF
[Service]
Environment=
Environment=HOME=$ROOT
Environment=HF_HOME=$DIR/hf
Environment=INVOKEAI_ROOT=$ROOT/data
Environment=INVOKEAI_HOST=$LISTEN
Environment=INVOKEAI_PORT=$PORT
Environment=INVOKEAI_MODELS_DIR=$OWN
Environment=W_AI_MODELS_DIR=$DIR
ExecStart=
ExecStart=$VENV/bin/invokeai-web --root $ROOT/data
ReadWritePaths=
ReadWritePaths=$ROOT $DIR
WorkingDirectory=$ROOT/data
EOF
systemctl daemon-reload
if systemctl is-active --quiet invokeai.service; then
  warn "invokeai.service is running with the PREVIOUS layout — restart it to apply:"
  warn "    systemctl restart invokeai"
fi

# ── 8. Offline verification / how-to ──────────────────────────────────────────
if systemd-analyze verify invokeai.service >/dev/null 2>&1; then
  info "invokeai.service passes systemd-analyze verify."
else
  warn "systemd-analyze verify found issues — inspect: systemd-analyze verify invokeai.service"
fi
info "invokeai layer done. InvokeAI is NOT started or enabled (pull-the-trigger design):"
info "  systemctl start invokeai    → start it (web interface: http://$LISTEN:$PORT/)"
info "  systemctl enable invokeai   → start it at every boot"
info "Models: every file in the store's class folders ($DIR/checkpoints, loras, …) is"
info "  registered in place on each start; after adding files: sudo systemctl reload invokeai"
info "  Downloads made from InvokeAI's model manager land in $OWN."
info "Engine tuning (ram, vram, attention_type, …): $ROOT/data/invokeai.yaml"
info "  (written by the engine on first start; see invokeai.example.yaml next to it)."
info "Extra env vars (e.g. HSA_OVERRIDE_GFX_VERSION, PYTORCH_HIP_ALLOC_CONF) — your own drop-in:"
info "  sudo systemctl edit --drop-in=20-local invokeai.service   # Environment= lines only"
