---
name: comfyui
description: >-
  Operating the `comfyui` W-Pack: local image/video generation (ComfyUI) as a
  system service on :8188, the shared machine-wide model store under
  `/var/lib/w/ai-models`, GPU-variant install via comfy-cli, model management into
  the store, and custom nodes through the built-in ComfyUI-Manager. Load this when
  the user asks about ComfyUI, local image/video generation, Stable Diffusion /
  Flux workflows, installing custom nodes, or where generated/model files go —
  and `w-pack status comfyui` reports installed.
---

# W-Pack: comfyui

Local image/video generation (ComfyUI) as a system service. Advanced, opt-in — never
offered in the TUI installer (`INSTALLER=off` in its `meta.conf`); install from the
running system only. Curated into `/usr/share/w/ai/skills/comfyui/` when installed.

## What the user has

- **ComfyUI engine** as the system service `comfyui.service`, a Node-based workflow
  editor and generation backend listening on `http://127.0.0.1:8188/`. Installed at
  `comfyui.ROOT` (default `/var/lib/w/comfyui`): the app tree + venv under
  `$ROOT/app/` (comfy-cli's `--workspace`) and the **runtime base directory** under
  `$ROOT/data/` — a separate tree whose standard subfolders (`custom_nodes`,
  `input`, `output`, `user`, `workflow_templates`) are seeded by setup because the
  engine's prestartup scan `listdir`s `custom_nodes/` and dies if it is absent. The
  runtime override lives in `/etc/systemd/system/comfyui.service.d/10-w.conf`
  (ExecStart, `HOME=$ROOT`, `HF_HOME=$DIR/hf`, `ReadWritePaths`, `WorkingDirectory`),
  rendered by setup on every install/refresh.
- **Generated images and video land in `$ROOT/data/output`** — the first question
  after a first render, and not guessable. That directory and `$ROOT/data/input`
  are `comfyui:w-ai 2770` (setgid), and `$ROOT` itself is `0750 comfyui:w-ai`, so
  any `w-ai` member browses the tree, collects renders and drops img2img sources
  with a file manager. `$ROOT/data/custom_nodes`, `app/` and `.venv` are NOT
  group-writable on purpose: the engine imports node code at startup as its own
  account. A user who cannot open `$ROOT` is simply not in `w-ai` YET in this
  session — the group applies at the next login.
- **GPU-variant install** matched to the machine at install time, key `comfyui.GPU`
  (`auto` default): `--nvidia` / `--amd --rocm-version 7.2` / `--intel-arc` (only
  for a discrete Intel card — Arc/Battlemage, recognised by PCI device id, not by
  the card's name) / `--cpu`. Telemetry is off (`DO_NOT_TRACK`,
  `COMFY_NO_TELEMETRY`).
- **ComfyUI-Manager, on.** Since v4 the manager is a pip package the engine CORE
  knows about, not a custom node — setup installs it into the workspace venv from
  the engine tree's own pinned `manager_requirements.txt` (so its version always
  matches the ComfyUI next to it), and the drop-in runs the engine with
  `--enable-manager`. That is the supported way to add nodes: the user installs
  them from the web interface, and nothing needs to be cloned by hand. Installed
  nodes land in `$ROOT/data/custom_nodes` (the manager resolves paths through
  `folder_paths`, so it follows `--base-directory`); the manager's own state —
  `config.ini`, snapshots, cache — sits in `$ROOT/data/user/__manager`.
- **Shared model store** under `ai-models.DIR` (default `/var/lib/w/ai-models`),
  a nested btrfs subvolume (excluded from root snapshots) owned `root:w-ai` with
  setgid 2775 dirs for `checkpoints`, `diffusion_models`, `loras`, `vae`, `clip`,
  `clip_vision`, `text_encoders`, `controlnet`, `embeddings`, `upscale_models`,
  `unet`, `style_models`, `video_models`, `inpaint`, plus `hf/` for the HF cache.
  ComfyUI reads/writes models there via `--models-directory $DIR` (HF cache via
  `HF_HOME=$DIR/hf`). The engine account `comfyui` and every human account that ran
  `w-pack setup comfyui` are in the `w-ai` group → the `w-ai` group is the shared
  write boundary, both directions (the store is an `ai-models` subsystem contract,
  not a ComfyUI-private path).
- **Launcher entry** "ComfyUI" in the app menu (`w-comfyui-open`): starts the
  service through W's polkit, waits for the port, opens the browser. The service is
  intentionally NOT enabled at boot — the launcher and `systemctl start` are
  deliberate triggers (no AUTOSTART decision).
- **Per-user layer** = membership in `w-ai` (nothing else — no per-user daemon).

## Common operations

- Start / stop / status:
  `systemctl start comfyui` / `systemctl stop comfyui` / `systemctl status comfyui`.
  Web UI: `xdg-open http://127.0.0.1:8188/` (or the app menu item, which starts the
  service first). Make it start at boot — the user's call, not the installer's:
  `sudo systemctl enable comfyui`.
- Pull a model into the store (needs network; large). comfy-cli is installed as the
  service account — resolve it through the engine root:
  `sudo -u comfyui env HOME=/var/lib/w/comfyui /var/lib/w/comfyui/.local/bin/comfy model download --url <URL> --relative-path checkpoints` —
  the paths are relative to the store (ComfyUI's `--models-directory`), so
  `--relative-path loras`, `vae`, `clip`, etc. If the user knows a direct
  `wget`/HF URL, dropping the file into `/var/lib/w/ai-models/<class>/` works just
  as well (setgid keeps it group-writable for every `w-ai` member).
- Install a custom node: **from the web interface**, through the Manager button —
  not by cloning into `custom_nodes`, which stopped installing the manager itself
  in v4 and is not how node packs are meant to arrive either. Check the manager is
  live: `curl -s http://127.0.0.1:8188/api/v2/manager/version` (the routes are
  under `v2`; a bare `/api/manager/...` 404s even on a healthy engine).
- Free VRAM without stopping the service: `curl -X POST
  http://127.0.0.1:8188/free` (unloads models; the service keeps running).
- Find the store / per-user access:
  `w-conf get ai-models DIR` (or `comfyui.ROOT` for the engine tree) — a user who
  cannot write models is not in `w-ai`: `sudo usermod -aG w-ai <user>` (next login).
- Move engine or store (paths are layered w-conf, re-pointing is a refresh away):
  `sudo w-conf set comfyui ROOT /srv/comfyui && sudo w-pack refresh comfyui`
  (refresh re-renders the drop-in and `systemctl daemon-reload`; the service must
  then be started again — refresh never auto-starts it).

## Gotchas

- **Refresh is not reinstall:** `w-pack refresh comfyui` re-renders the drop-in and
  relock paths; it skips `comfy install` once `$ROOT/app/.venv` exists. It DOES
  re-apply `manager_requirements.txt`, which is how an engine installed before
  Manager v4 — or one whose manager install failed offline — gains the manager
  without a venv rebuild. Reinstalling the engine from scratch = delete the app
  tree yourself, then refresh.
- **The store is shared** (`ai-models` subsystem): don't "clean" it to make room or
  move models into a ComfyUI-private `models/` dir — other consumers read the same
  paths; keep files in `$DIR/<class>/`.
- **CPU installs are slow** — warn a user who expects real-time generation on a
  machine that matched none of the GPU checks (`lspci -nn`: `[10de:` NVIDIA,
  `[1002:` AMD, Intel **discrete** by device id `4f8x`/`56xx`/`e2xx`). An Intel
  iGPU is not a match: it resolves to a CPU install, and so does a discrete DG1.
- **A CPU (/ Arc) engine MUST run with its own `--cpu` flag** — the drop-in adds
  it when the install resolved to CPU. Without it the engine defaults to a CUDA
  device and dies with `AssertionError: Torch not compiled with CUDA enabled` even
  though a CPU torch is installed; the engine only honours a CPU runtime when told.
  The flag comes from the drop-in (the venv is never rebuilt on refresh), so a GPU
  swap is one `w-conf set comfyui GPU …` + refresh away.
- **CPU/Arc installs skip `--fast-deps` on purpose** (upstream gap, comfy-cli
  #344/#750): the uv-path's `DependencyCompiler` only selects torch for NVIDIA
  (`/whl/cu*`) and AMD (`/whl/rocm*`); `--cpu` reaches it as `gpu=None` → "no
  index" → the DEFAULT PyPI build **is CUDA** (6.6G of nvidia wheels). The pip
  path maps `gpu=None`→`/whl/cpu` and Arc→`/whl/xpu`, so those two variants run
  without `--fast-deps`. Don't "optimize" by forcing `--fast-deps` on a CPU box —
  that is the bug; `torch 2.x+cu***` in `.venv` on a GPU-less machine is the symptom.
- **`LISTEN=0.0.0.0` switches node installation off** — and it is the manager, not
  W, that does it: at its default security level it permits a node install only
  while `--listen` is a loopback address. A user who exposed the engine and then
  found the Manager buttons refusing is not looking at a bug; there is no W key
  that lifts it. Put the engine back on `127.0.0.1` (`w-conf set comfyui LISTEN`
  + refresh + restart) to install, or edit the manager's own `config.ini` in
  `$ROOT/data/user/__manager` knowing exactly what that opens up.
- **The Manager's "Restart" button is systemd-safe**: it re-execs the running
  process in place (`os.execv` with the same argv), so the PID and the unit are
  untouched and `systemctl restart comfyui` is not needed after installing a node.
  If the engine does die instead, `Restart=on-failure` brings it back.
- **A broken custom node takes the whole engine down at startup** — node code is
  imported before the server listens, so a bad install reads as "the service
  won't start" in `journalctl -u comfyui`. Way out: add `--disable-all-custom-nodes`
  to `comfyui.ARGS` (w-conf) + refresh + restart, then remove the offender from
  `$ROOT/data/custom_nodes` (or disable it in the Manager) and drop the flag again.
- **Node dependencies go into the shared workspace venv.** Installing a node pack
  can move a pinned package (torch, transformers, numpy) under the engine and break
  generation that used to work. That is upstream's model, not W's; a venv rebuild
  is deleting `$ROOT/app` and running `w-pack refresh comfyui`.
- **First start is slow**: PyTorch import + frontend unpack can take a minute; the
  launcher's wait is generous on purpose. If the desktop item says "failed", check
  `journalctl -u comfyui` — usually a failed model path or a huge download.
- **No config to reset:** the bundle's manifest rows are all *managed* system files
  (unit, sysusers, helper, desktop); the drop-in is rendered, not shipped —
  `w-reset comfyui` restores the shipped unit, not a user's manual tweaks. Two
  separate channels for custom runtime tuning, never mix them:
  - **Extra CLI flags** (`--lowvram`, `--cuda-device 0`, …) → `comfyui.ARGS`
    (w-conf), portable and refresh-aware:
    `sudo w-conf set comfyui ARGS -- "--lowvram" && sudo w-pack refresh comfyui`
    (the `--` is required whenever the value itself starts with `-`, or
    `w-conf`'s own option parser mistakes it for an unknown flag).
  - **Extra env vars** (`HSA_ENABLE_SDMA`, `PYTORCH_HIP_ALLOC_CONF`, …) → the
    admin's own drop-in, which this pack never renders into or overwrites:
    `sudo systemctl edit --drop-in=20-local comfyui.service` (add `Environment=`
    lines under `[Service]`), then `sudo systemctl daemon-reload && sudo systemctl
    restart comfyui`. It sorts after this pack's `10-w.conf`, so its
    `Environment=` lines ADD to `HOME`/`HF_HOME` instead of replacing them. Never
    put `ExecStart=` there — it collides with the one `10-w.conf` renders
    ("Service has more than one ExecStart"); flags belong in `ARGS` above.

## Reset / remove

- `sudo w-pack remove comfyui` disables/stops the service, removes the rendered
  drop-in and the comfy-cli toolchain, then w-pack removes the shipped unit/sysusers/
  launcher. **The engine tree and the model store are preserved** (user content) —
  delete them yourself if truly unwanted:
  `sudo rm -rf /var/lib/w/comfyui /var/lib/w/ai-models` (plain dirs) or
  `sudo btrfs subvolume delete /var/lib/w/comfyui /var/lib/w/ai-models` (subvolumes).
- `w-reset comfyui` re-seeds the shipped unit/sysusers/helper/desktop from the
  bundle tree, then re-renders the drop-in — safe to run when a manual edit broke
  the service. The rendered drop-in itself is never reset (it IS the current intent).