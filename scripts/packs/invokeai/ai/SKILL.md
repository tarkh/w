---
name: invokeai
description: >-
  Operating the `invokeai` W-Pack: local image generation with InvokeAI (canvas,
  inpainting, gallery) as a system service on :9090, the shared machine-wide model
  store (`ai-models.DIR`) registered in place, GPU-variant PyTorch install via uv,
  engine tuning in invokeai.yaml. Load this when the user asks about InvokeAI, its
  canvas/gallery, why a model from the store is (not) visible in InvokeAI, or where
  its images and downloads go — and `w-pack status invokeai` reports installed.
---

# W-Pack: invokeai

InvokeAI as a system service. Advanced, opt-in — never offered in the TUI installer
(`INSTALLER=off`); install from the running system only. It is the sibling of the
`comfyui` pack: independent of it, sharing the same model store.

## What the user has

- **`invokeai.service`** — the engine and its web interface on
  `http://127.0.0.1:9090/`, run by the `invokeai` account (groups `w-ai`, `video`,
  `render`). Installed but NOT enabled: the app-menu entry **InvokeAI** starts it
  (polkit) and opens the browser; `systemctl enable invokeai` to start at boot.
- **Engine tree `invokeai.ROOT`** (default `/var/lib/w/invokeai`):
  - `$ROOT/app/.venv` — the `invokeai` package + PyTorch on a uv-managed Python 3.12;
  - `$ROOT/data` — the runtime root (`INVOKEAI_ROOT`): `invokeai.yaml`,
    `databases/` (gallery, boards, model registry), `outputs/` (generated images),
    `nodes/` (custom nodes).
  `$ROOT` and `$ROOT/data` are `0750 invokeai:w-ai`; `data/outputs` is `2770`, so
  any `w-ai` member reaches the images from a file manager. Group membership
  applies at the next login.
- **Runtime drop-in** `/etc/systemd/system/invokeai.service.d/10-w.conf`, rendered
  by setup from w-conf on every install/refresh: `INVOKEAI_HOST/PORT`,
  `INVOKEAI_MODELS_DIR`, `INVOKEAI_ROOT`, `HF_HOME=$DIR/hf`, ExecStart, paths.
- **GPU build** chosen once, when the venv is built, from `invokeai.GPU` (`auto`):
  NVIDIA → `--torch-backend=cu128`, AMD → `rocm7.2`, discrete Intel Arc/Battlemage
  → `xpu`, anything else → `cpu` (works, slow). Check what landed:
  `sudo -u invokeai /var/lib/w/invokeai/app/.venv/bin/python -c "import torch; print(torch.__version__)"`.

## How models reach InvokeAI

InvokeAI keeps models in a database, not a folder layout, so it cannot simply be
pointed at the store like ComfyUI. W wires the store in by **in-place
registration**: after every start (and on `systemctl reload invokeai`) the helper
`w-invokeai-models sync` registers each model file under the store's class folders
(`$DIR/checkpoints`, `loras`, `vae`, `diffusion_models`, `text_encoders`, …) by
path — nothing is copied — and unregisters store models whose file was deleted.
Only the class folders count: other folders in the store (a ComfyUI custom node's
private weights, `hf/`) are never registered, and a record pointing there is removed.

- **Added a file to the store?** `sudo systemctl reload invokeai` (or restart).
  Registration hashes each new file once in the background; large stores take
  minutes on the first sync. Progress: `journalctl -u invokeai -f`.
- **A store file InvokeAI cannot use** (ComfyUI-only encoders, custom-node weights)
  is unregistered again and remembered in `$ROOT/data/w-store-skip.tsv` (keyed by
  size+mtime) — not retried until the file changes. Deleting a line retries it.
- **Downloads from InvokeAI's own model manager** (starter models, URLs, HF repos)
  land in `$DIR/invokeai/` — InvokeAI's layout, invisible to ComfyUI.
- **Deleting a model in InvokeAI** deletes the file only if it is under
  `$DIR/invokeai/`; a store model is just unregistered (and re-registered on the
  next start while the file exists). To drop a store model for good, delete the
  file — that affects every engine using the store.
- `ai-models.DIR` is shared: never clean it "for InvokeAI".

## Common operations

- Start/stop/status: `systemctl start|stop|status invokeai`; logs:
  `journalctl -u invokeai`.
- Move engine or store: `sudo w-conf set invokeai ROOT /path` /
  `sudo w-conf set ai-models DIR /path`, then `sudo w-pack refresh invokeai` and
  `sudo systemctl restart invokeai`. W never moves data — rsync it first.
- **Engine tuning** — `invokeai-web` has no tuning flags; settings live in
  `$ROOT/data/invokeai.yaml` (written by the engine on first start;
  `invokeai.example.yaml` next to it lists every key): `max_cache_ram_gb`,
  `max_cache_vram_gb`, `enable_partial_loading`, `device_working_mem_gb`,
  `attention_type`, `precision`, `remote_api_tokens` (tokens for gated downloads),
  `hashing_algorithm` (`blake3_multi` is faster on SSD). Edit with
  `sudo -u invokeai $EDITOR …` and restart. `host`, `port` and `models_dir` in that
  file are ignored: the environment set by W wins.
- **Environment tuning** (`HSA_OVERRIDE_GFX_VERSION`, `PYTORCH_HIP_ALLOC_CONF`,
  `CUDA_VISIBLE_DEVICES`, any `INVOKEAI_*`): your own drop-in —
  `sudo systemctl edit --drop-in=20-local invokeai.service`, `Environment=` lines
  only (it sorts after 10-w.conf and adds to it; an `ExecStart=` there breaks the
  unit), then restart.
- **Upgrade InvokeAI / change GPU build**: `sudo systemctl stop invokeai`,
  `sudo rm -rf $ROOT/app`, (`sudo w-conf set invokeai GPU …`),
  `sudo w-pack refresh invokeai`. Gallery, boards and registry live in
  `$ROOT/data` and survive; the database migrates forward on first start.

## Gotchas

- Web interface has no authentication in single-user mode; keep `LISTEN` on
  loopback unless a firewall rule of the user's own guards it.
- `systemctl start` returns only once the port answers (up to ~10 min on a cold
  CPU start) — that is the store sync waiting, not a hang.
- PatchMatch (canvas infill) is built by setup against the system `opencv`
  (Arch ships OpenCV 5; setup links only the modules it needs). Check:
  `curl -s 127.0.0.1:9090/api/v1/app/patchmatch_status` → `true`. `false` after an
  OpenCV update (a changed soname) → `sudo w-pack refresh invokeai` rebuilds it.
- **Several GPUs are all used by default** (`generation_devices: auto` runs one
  session per GPU in parallel). On an AMD dGPU + Ryzen iGPU machine ROCm lists the
  iGPU too (`cuda:1`, named after the CPU, backed by system RAM), so half the jobs
  crawl on it. Pin the discrete card in invokeai.yaml: `device: cuda:0` (or
  `generation_devices: ["cuda:0"]`), then restart. Check the startup log line
  "Starting session processor with N parallel workers on devices: …".
- `Could not detect ROCm GPU architecture … rocminfo` at startup is bitsandbytes
  logging a value nothing uses — harmless, no package needed.
- No models ship with the pack: until the store has files (or starter models are
  downloaded from the Model Manager tab), generation has nothing to run.

## Reset / remove

- `w-reset invokeai` restores the unit, sysusers fragment, helpers and desktop entry.
- `sudo w-pack remove invokeai` stops the service and removes W's wiring; the
  engine tree and `$DIR/invokeai` are kept and their sizes printed. Membership in
  `w-ai` is kept while another engine pack (comfyui) still uses the group.
