#!/usr/bin/env bash
# comfyui bundle — MACHINE layer. Run by `w-pack install` AFTER packages and
# config are deployed, always as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Installs the local image/video generation engine: the `comfyui` service account
# and `w-ai` model-store group, the ComfyUI app tree (comfy-cli → `comfy install`,
# GPU-variant matched to the machine), a lockable drop-in overriding the shipped
# unit, and a snapshot-excluded model store. It enables NOTHING — ComfyUI is a
# pull-the-trigger service (see pack-comfyui.md for the "no AUTOSTART" decision).
#
# The per-account half — being a `w-ai` member to write into the shared model
# store — is in setup-user.sh, because membership is per account and has to be
# runnable again for later accounts via `w-pack setup comfyui`.
#
# Everything lives in two admin-set paths that w-conf read BEFORE any step (they
# may have been chosen long before the pack was installed):
#   comfyui.ROOT   where the engine + venv go (default /var/lib/w/comfyui)
#   ai-models.DIR  where models are shared machine-wide (default /var/lib/w/ai-models)
# Only the runtime env changes with the path — the service stays new-style
# user/group (declared in sysusers, resolved by the daemon), so a plain
# `w-pack refresh comfyui` re-points it. NEVER re-run the whole install on
# refresh: the workspace check below must be skipped once a venv exists.
#
# Idempotent; best-effort — a hiccup warns rather than aborting (packages are
# already deployed by the time this runs). See pack-comfyui.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 0. The admin's choices (w-conf, read BEFORE any step) ─────────────────────
# Both subsystems ship vendor defaults in /usr/share/w/defaults/; the admin layer
# /etc/w/*.conf overrides. REFRESH re-reads them here and re-renders the drop-in,
# which is the whole point of making the service re-pointable without reinstalling.
source /usr/lib/w/w-conf-lib.sh
wconf_load comfyui
wconf_load ai-models
ROOT="$(wconf_get comfyui ROOT /var/lib/w/comfyui)"
LISTEN="$(wconf_get comfyui LISTEN 127.0.0.1)"
PORT="$(wconf_get comfyui PORT 8188)"
GPU="$(wconf_get comfyui GPU auto)"
ARGS="$(wconf_get comfyui ARGS '')"
DIR="$(wconf_get ai-models DIR /var/lib/w/ai-models)"

# ── 1. Path validation ─────────────────────────────────────────────────────────
# ROOT/DIR must be absolute, and must not sit inside the system-critical trees a
# misplaced path would dump gigabytes into (a admin typo like ROOT=/usr would
# clone a whole app tree over the libs). noexec on the parent is a hard NO — the
# workspace MUST carry a runnable .venv/bin/python; a plain dir on non-btrfs is
# NOT an error (ensure_subvol degrades gracefully below), so only noexec fails.
reject_dirs=('/usr' '/etc' '/boot' '/home')
check_path() {                                  # <kind> <path> <default>
  local kind="$1" p="$2" dflt="$3" d
  [[ "$p" == /* ]] || { warn "$kind '$p' not absolute — using default '$dflt'."; return 1; }
  # The drop-in's ExecStart and Environment lines are space-split by systemd — a
  # path with whitespace or ';' would break the unit silently at start time.
  if [[ "$p" =~ [[:space:]\;] ]]; then
    warn "$kind '$p' contains whitespace or ';' — unsafe for the unit drop-in, using default '$dflt'."
    return 1
  fi
  p="${p%/}"
  for d in "${reject_dirs[@]}"; do
    if [[ "$p" == "$d" || "$p" == "$d/"* ]]; then
      warn "$kind '$p' is inside the system tree $d/ — using default '$dflt'."
      return 1
    fi
  done
  if [[ -n "${roo_t:-}" && ( "$p" == "${roo_t}"/* || "$roo_t" == "$p"/* ) ]]; then
    warn "$kind '$p' nests inside the engine root — using default '$dflt'."
    return 1
  fi
  local parent="${p%\/*}"; [[ "$parent" == "$p" ]] && parent="/"
  if ! [[ -d "$parent" ]]; then
    warn "$kind parent '$parent' does not exist — using default '$dflt' (must a path on / exist)."
    return 1
  fi
  if findmnt -no OPTIONS --target "$parent" 2>/dev/null | tr ',' '\n' | grep -qx 'noexec'; then
    warn "$kind parent '$parent' is mounted noexec — using default '$dflt' (a venv needs a runnable python)."
    return 1
  fi
  echo "$p"
}
roo_t="$(check_path 'comfyui.ROOT' "$ROOT" /var/lib/w/comfyui)"
ROOT="$roo_t"
[[ -n "$ROOT" ]] || { warn 'comfyui.ROOT empty after validation — aborting.'; exit 1; }
DIR="$(check_path 'ai-models.DIR' "$DIR" /var/lib/w/ai-models)"
[[ -n "$DIR" ]] || { warn 'ai-models.DIR empty after validation — aborting.'; exit 1; }

# ── 2. Identities: the `comfyui` account and the `w-ai` store group ───────────
# Declared in /usr/lib/sysusers.d/w-comfyui.conf and created by systemd-sysusers
# (idempotent — a rerun is a no-op). The account's home defaults to /var/lib/w/
# comfyui but follows a relocated ROOT via `usermod -d`; the group's membership
# of the engine account (comfyui + video/render) makes the walled-off store
# writable by the service without touching the root-owned parent.
info "Provisioning the 'comfyui' service account and 'w-ai' store group..."
systemd-sysusers /usr/lib/sysusers.d/w-comfyui.conf 2>/dev/null \
  || warn "systemd-sysusers failed — accounts/group may not exist."
if [[ "$(getent passwd comfyui | cut -d: -f6)" != "$ROOT" ]]; then
  if systemctl is-active --quiet comfyui.service 2>/dev/null; then
    # usermod -d refuses while the account owns a live process ("currently used").
    # The runtime never uses the passwd home (ExecStart + HOME=$ROOT are explicit,
    # so the relocation below already works) — but keep the contract honest: the
    # home re-syncs on the next refresh taken while the service is stopped.
    warn "comfyui home still points at the old ROOT — usermod -d needs the service stopped. It will re-sync on a stopped-state refresh (paths themselves already moved)."
  else
    usermod -d "$ROOT" comfyui 2>/dev/null && info "comfyui home set to $ROOT." \
      || warn "could not set comfyui home to $ROOT."
  fi
fi

# ── 3. ROOT and DIR as nested btrfs subvolumes (snapshot exclusion) ───────────
# Both trees are large and re-downloadable — they do not belong inside root's
# snapper snapshots (non-recursive; nested subvolume is naturally excluded). Same
# rule as /var/lib/ollama: act only while absent or empty, an existing populated
# dir is left as-is with a warning (see snapshots.md).
#
# Snapshot talk only makes sense for a path that snapper could actually reach:
# the root filesystem. A relocated ROOT/DIR on a second disk is outside every
# snapper config by construction, so saying "no snapshot exclusion" there names a
# loss that does not exist — and it fires in exactly the scenario the pack
# advertises (put the engine on the big disk). Both branches below decide from
# the mount, not from btrfs alone.
in_root_snapshots() {                          # <path> → true if snapper reaches it
  [[ "$(findmnt -no FSTYPE --target "$1" 2>/dev/null)" == btrfs ]] \
    && [[ "$(findmnt -no TARGET --target "$1" 2>/dev/null)" == / ]]
}
ensure_subvol() {                              # <label> <owner> <group> <mode> <path>
  local label="$1" owner="$2" group="$3" mode="$4" p="$5"
  if [[ ! -e "$p" ]] || [[ -z "$(ls -A "$p" 2>/dev/null)" ]]; then
    rmdir "$p" 2>/dev/null || true
    if btrfs subvolume create "$p" >/dev/null 2>&1; then
      chown "$owner:$group" "$p" 2>/dev/null || true; chmod "$mode" "$p" 2>/dev/null || true
      info "Created nested subvolume $p (excluded from root snapshots)."
    else
      install -d -o "$owner" -g "$group" -m "$mode" "$p" 2>/dev/null || install -d -m "$mode" "$p"
      if in_root_snapshots "$p"; then
        warn "$p is on the root filesystem but could not be made a subvolume — it will ride in root snapshots"
      else
        info "Created $p on $(findmnt -no FSTYPE --target "$p" 2>/dev/null) at $(findmnt -no TARGET --target "$p" 2>/dev/null) — outside root snapshots already."
      fi
    fi
  elif btrfs subvolume show "$p" >/dev/null 2>&1; then
    info "$p already a subvolume — nothing to do."
  elif in_root_snapshots "$p"; then
    warn "$p already exists as a regular populated dir on the root filesystem — leaving as-is (it will ride in root snapshots)"
  else
    info "$p already exists — leaving as-is (on $(findmnt -no TARGET --target "$p" 2>/dev/null), outside root snapshots)."
  fi
}
mkdir -p /var/lib/w 2>/dev/null || true
# Group w-ai on the engine tree, not comfyui: the humans who use ComfyUI have to
# reach their own generated output (step 6c sets the modes that make that real).
ensure_subvol 'engine tree' comfyui w-ai 750 "$ROOT"
ensure_subvol 'model store' root w-ai 2775 "$DIR"

# ── 4. Canonical model layout + HF cache (shared, machine-wide store) ─────────
# ComfyUI resolves folder_paths against the store — a ComfyUI-Manager style
# directory *inside* the engine tree would silently diverge from what every other
# consumer (ai-models split, user's `w-ai` group) reads. Ownership root:w-ai + 2775
# (setgid): new files inherit the group, and every w-ai member can write.
info "Laying out the shared model store under $DIR..."
for d in checkpoints diffusion_models loras vae clip clip_vision text_encoders \
         controlnet embeddings upscale_models unet style_models video_models inpaint; do
  install -d -o root -g w-ai -m 2775 "$DIR/$d" 2>/dev/null || {
    install -d "$DIR/$d" 2>/dev/null || warn "could not create $DIR/$d"
  }
done
install -d -o root -g w-ai -m 2775 "$DIR/hf" 2>/dev/null || install -d "$DIR/hf"

# ── 5. comfy-cli toolchain into the service account's scope ───────────────────
# The engine's on-disk state (app + venv + per-user config) belongs to comfyui,
# so the CLI that manages it lives in its HOME too ($ROOT/.local/bin), not in any
# account's ~/.local. uv resolves the tool's own Python; `comfy install` builds
# the workspace venv afterwards. Same as ai-extra: needs network, best-effort.
run_as_comfy() {   # safe cwd → clean env headed for the service account
  ( cd "$ROOT" && runuser -u comfyui -- env HOME="$ROOT" PATH="/usr/local/bin:/usr/bin:/bin" "$@" )
}
info "Ensuring the comfy-cli tool (uv tool) for the 'comfyui' account..."
if command -v uv >/dev/null 2>&1; then
  run_as_comfy uv tool install comfy-cli || warn "uv tool install comfy-cli failed."
else
  warn "uv not found — comfy-cli (and therefore ComfyUI) cannot be installed. Install uv (w-software) and run 'w-pack refresh comfyui'."
fi
COMFY="$ROOT/.local/bin/comfy"

# ── 6. ComfyUI workspace via comfy-cli (only while not already present) ───────
# `comfy install` clones the app into the workspace and builds its `.venv`; the
# GPU flag is chosen from the GPU key (auto → the shared w-gpu-lib.sh seam,
# INTEL_ARC only for a real Intel discrete card). REFRESH must never rebuild an
# existing workspace — the venv check below IS the idempotency guard.
# ComfyUI-Manager is NOT settled here (`comfy install` does pip it in, but only
# on a fresh workspace, and the engine ignores it without a flag) — step 6d
# owns it. Telemetry is off via the standard env wins.
GPU_LIB="${W_GPU_LIB:-/usr/lib/w/w-gpu-lib.sh}"
gpu_flags=""
case "$GPU" in
  nvidia) gpu_flags="--nvidia" ;;
  amd)    gpu_flags="--amd --rocm-version 7.2" ;;
  intel)  gpu_flags="--intel-arc" ;;
  cpu)    gpu_flags="--cpu" ;;
  auto)
    if [[ -r "$GPU_LIB" ]]; then
      # shellcheck source=/dev/null
      source "$GPU_LIB"
      if   w_gpu_has nvidia;      then gpu_flags="--nvidia"
      elif w_gpu_has amd;         then gpu_flags="--amd --rocm-version 7.2"
      elif w_gpu_intel_discrete;  then gpu_flags="--intel-arc"
      elif w_gpu_has intel; then
        gpu_flags="--cpu"
        warn 'Intel graphics found, but not a supported discrete Arc/Battlemage — installing CPU-only (real-time synthesis will be slow).'
      else gpu_flags="--cpu"; warn 'no supported GPU matched — installing CPU-only (real-time synthesis will be slow).'
      fi
    else
      gpu_flags="--cpu"
      warn "w-gpu-lib.sh missing — cannot detect GPU, installing CPU-only."
    fi
    ;;
  *) warn "GPU='$GPU' unknown (nvidia|amd|intel|cpu|auto) — falling back to CPU."; gpu_flags="--cpu" ;;
esac

if [[ ! -d "$ROOT/app/.venv" ]]; then
  info "Installing ComfyUI workspace at $ROOT/app (GPU flags: ${gpu_flags:-none})..."
  if [[ -x "$COMFY" ]]; then
    # --fast-deps only for the engines whose torch variant the uv-path actually
    # selects. comfy-cli's DependencyCompiler handles NVIDIA (/whl/cu*) and AMD
    # (/whl/rocm*) but drops GPU_OPTION.CPU and INTEL_ARC — `--cpu` is wired as
    # gpu=None, whose Resolve_Gpu maps to "no index", i.e. the DEFAULT CUDA build.
    # The pip path treats gpu=None as CPU (-extra-index-url /whl/cpu) and handles
    # Arc via /whl/xpu, so pair those two with --fast-deps=no. See comfy-cli
    # #344/#750. Deliberate: a CPU install must not land 6.6G of CUDA wheels.
    case "$gpu_flags" in
      *"--cpu"*|*"--intel-arc"*) fast_deps=() ;;
      *) fast_deps=(--fast-deps) ;;
    esac
    run_as_comfy env DO_NOT_TRACK=1 COMFY_NO_TELEMETRY=1 \
      "$COMFY" --skip-prompt --workspace "$ROOT/app" install --version latest \
      "${fast_deps[@]}" $gpu_flags || warn "comfy install failed — the engine is not ready. Retry: w-pack refresh comfyui"
  else
    warn "comfy-cli lost after tool install — no engine."
  fi
else
  info "$ROOT/app/.venv exists — workspace already installed; refresh leaves it alone."
fi

# ── 6b. Seed the runtime base directory ──────────────────────────────────────
# The engine reads the `--base-directory` OUTSIDE the app tree ($ROOT/data), and
# its prestartup scan requires the standard subfolders to already exist there —
# a stock install ships them inside the repo, a redirected base path does not.
# Without these the service dies on `listdir(custom_nodes)`. Re-run on refresh:
# keep the scaffold in place even if the user deleted a folder (idempotent).
run_as_comfy mkdir -p \
  "$ROOT/data/custom_nodes" \
  "$ROOT/data/input" \
  "$ROOT/data/output" \
  "$ROOT/data/user" \
  "$ROOT/data/workflow_templates" \
  || warn "could not seed the runtime base directory under $ROOT/data"

# ── 6c. Human access to the engine tree (group w-ai) ──────────────────────────
# The store is shared with people (step 4); the engine's OUTPUT has to be too, or
# the generated images are unreachable from the file manager and the only way to
# a finished render is downloading it one by one through the web UI. Same group,
# same boundary: w-ai members traverse $ROOT and read/write input + output, while
# the tree stays owned by the service account.
#
# custom_nodes is DELIBERATELY left out of the group-writable set: the engine
# imports whatever sits there at startup, as its own account — granting group
# write would turn "may drop a model" into "may run code as the service".
#
# Enforced on every run, not just at creation: ensure_subvol only sets ownership
# on a tree it made itself, so an install that predates this contract (or a user
# chmod) would otherwise keep the old modes forever. Targeted, never recursive —
# a chown -R across a 10 GB venv is both slow and a known foot-gun (update-system.md).
info "Opening the engine tree to group w-ai (traverse + input/output)..."
chown comfyui:w-ai "$ROOT" 2>/dev/null && chmod 0750 "$ROOT" 2>/dev/null \
  || warn "could not set w-ai group access on $ROOT — the desktop account will not see its own output."
for d in input output; do
  [[ -d "$ROOT/data/$d" ]] || continue
  chown comfyui:w-ai "$ROOT/data/$d" 2>/dev/null && chmod 2770 "$ROOT/data/$d" 2>/dev/null \
    || warn "could not make $ROOT/data/$d group-writable for w-ai."
done

# ── 6d. ComfyUI-Manager: the half that installs custom nodes ─────────────────
# Manager v4 (Dec 2025) stopped being a custom node and became a pip package that
# ComfyUI's core knows about: `git clone` into custom_nodes no longer installs it
# at all. Two halves have to meet — the package in the venv (here) and
# `--enable-manager` on the command line (step 7). Without BOTH, the engine runs
# with no way to add a node from the web interface, and silently so: core exposes
# `extension.manager.supports_v4` in /api/features either way, while every
# /api/v2/manager/* route 404s. That is exactly how this shipped before.
#
# The version comes from the engine tree's own manager_requirements.txt (a single
# pinned line, e.g. comfyui_manager==4.2.2), so the manager always matches the
# ComfyUI release next to it and re-syncs on a refresh taken after `comfy update`
# — never a version we chose and would have to chase.
#
# `uv pip`, not `.venv/bin/python -m pip`: the nvidia/amd workspaces are built
# with --fast-deps, which leaves a uv-managed venv that may carry no pip at all.
# uv is a base-system tool here (package-python.md) and needs no bootstrap.
# Re-run on every refresh: this is how a machine installed before v4 — or one
# whose manager install failed offline — picks the manager up without rebuilding
# a 10 GB venv.
MANAGER_REQ="$ROOT/app/manager_requirements.txt"
if [[ ! -d "$ROOT/app/.venv" ]]; then
  warn "no workspace venv — skipping ComfyUI-Manager (retry: w-pack refresh comfyui)."
elif [[ ! -f "$MANAGER_REQ" ]]; then
  warn "$MANAGER_REQ missing — ComfyUI too old for the built-in manager; nodes must be installed by hand."
elif command -v uv >/dev/null 2>&1; then
  info "Ensuring ComfyUI-Manager ($(tr -d '[:space:]' < "$MANAGER_REQ")) in the workspace venv..."
  run_as_comfy uv pip install --python "$ROOT/app/.venv/bin/python" -r "$MANAGER_REQ" \
    || warn "could not install ComfyUI-Manager — the engine still starts, but the web interface cannot add nodes. Retry: w-pack refresh comfyui"
else
  warn "uv not found — cannot install ComfyUI-Manager."
fi

# The engine defaults to a CUDA device and only honours a CPU runtime when told
# explicitly: `--cpu` (comfy/cli_args.py) sets CPUState.CPU; without it,
# model_management.resolve_device falls through to torch.cuda.current_device()
# and a CPU-only torch dies with "Torch not compiled with CUDA enabled". The
# install above chose the torch variant from $gpu_flags, so lock the runtime to
# the SAME result — never rebootstrapped from scratch-level hardware probing,
# so a refresh after a GPU swap re-runs the same resolution and stays consistent
# with whatever venv actually exists.
ENGINE_CPU_FLAG=""
[[ "$gpu_flags" == *"--cpu"* ]] && ENGINE_CPU_FLAG="--cpu"

# ── 7. Drop-in: lock the runtime to the chosen paths/config (never edit vendor) ─
# /etc/systemd/system/comfyui.service.d/10-w.conf overrides the shipped unit's
# ExecStart + Environment + ReadWritePaths + WorkingDirectory with the w-conf values. Rendered on
# every setup (install AND refresh), so a path/port/args change is exactly one
# `w-pack refresh comfyui` away — no unit surgery.
DROPIN_DIR="/etc/systemd/system/comfyui.service.d"
DROPIN="$DROPIN_DIR/10-w.conf"
info "Rendering the runtime drop-in $DROPIN..."
mkdir -p "$DROPIN_DIR"
{
  echo "[Service]"
  echo "Environment="
  echo "Environment=HOME=$ROOT"
  echo "Environment=HF_HOME=$DIR/hf"
  # ExecStart needs the same empty-reset the list settings above get: a drop-in
  # ASSIGNS to the base unit's value (vendor main.py), it does not replace it —
  # two ExecStart lines on a non-oneshot service are refused by systemd. Reset
  # first, then emit the locked runtime command. systemd-analyze verify in step 8
  # would catch a regression here ("more than one ExecStart").
  echo "ExecStart="
  # --enable-manager is emitted unconditionally, even when step 6d could not land
  # the package: core's main.py checks for the module, logs what to install and
  # clears the flag itself, so the worst case is an engine that starts without a
  # manager — never one that refuses to start. Manager resolves its own paths
  # through folder_paths, so it honours --base-directory without being told.
  echo "ExecStart=$ROOT/app/.venv/bin/python $ROOT/app/main.py --base-directory $ROOT/data --models-directory $DIR --listen $LISTEN --port $PORT --enable-manager $ENGINE_CPU_FLAG $ARGS"
  echo "ReadWritePaths="
  echo "ReadWritePaths=$ROOT $DIR"
  # WorkingDirectory is a plain (non-list) setting, so no reset is needed — but it
  # MUST be re-pointed: the vendor unit hardcodes the default ROOT, and systemd
  # chdir's before exec. A relocated ROOT left the engine starting in a path that
  # does not exist → 200/CHDIR before python was ever reached (the ExecStart path
  # itself is right, which is exactly why the failure reads as a mystery).
  echo "WorkingDirectory=$ROOT/app"
} > "$DROPIN"
systemctl daemon-reload
# Refresh re-pointed the runtime, but a RUNNING service still executes the old
# ExecStart until restarted — never do that on our own (a generation in flight
# must not be killed by a path change), just say it once, loudly.
if systemctl is-active --quiet comfyui.service; then
  warn "comfyui.service is running with the PREVIOUS layout — restart it to apply:"
  warn "    systemctl restart comfyui"
fi

# ── 8. Offline verification / how-to ──────────────────────────────────────────
# systemd-analyze verify is deliberately a warn-level gate: it cannot know whether
# the app tree exists, but it does catch a malformed ExecStart/drop-in early, when
# the names are still readable. Install is fine; a broken drop-in would otherwise
# surface only as "Service has more than one ExecStart" at the first `systemctl start`.
if systemd-analyze verify "$DROPIN_DIR/../comfyui.service" >/dev/null 2>&1; then
  info "comfyui.service passes systemd-analyze verify."
else
  warn "systemd-analyze verify found issues in comfyui.service — inspect: systemd-analyze verify comfyui.service"
fi
info "comfyui layer done. ComfyUI is NOT started or enabled (pull-the-trigger design):"
info "  systemctl start comfyui    → start it"
info "  systemctl enable comfyui   → start it at every boot"
info "GUI: open 'ComfyUI' from the app menu; CLI model pulls land in $DIR/checkpoints."
info "Extra launch flags (portable, survives refresh):"
info "  sudo w-conf set comfyui ARGS -- \"--lowvram ...\" && sudo w-pack refresh comfyui"
info "Extra env vars (e.g. HSA_ENABLE_SDMA, PYTORCH_HIP_ALLOC_CONF) — your own drop-in,"
info "never touched by this pack:"
info "  sudo systemctl edit --drop-in=20-local comfyui.service   # add Environment= lines under [Service]"
info "  sudo systemctl daemon-reload && sudo systemctl restart comfyui"
info "  (do NOT add ExecStart= there — two ExecStart lines break the unit; use ARGS above for flags)"