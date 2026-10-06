---
name: 3d
description: >-
  The `3d` W-Pack: Blender 5 (modelling, sculpting, shading, animation,
  Cycles/EEVEE) — how YOU build and edit scenes in a running
  Blender through its MCP server (inspect, run bpy code, screenshot, export,
  Poly Haven assets), safe-mode limits, the W theme follower, Cycles GPU setup
  and troubleshooting. Load this to create or change 3D models/scenes, render,
  export GLB/FBX, preview a model file, or for Blender colours/add-on/GPU
  questions — when `w-pack status 3d` reports installed.
---

# W-Pack: 3d

3D content creation: **Blender 5** (official `extra` repo) for the whole
pipeline. Curated into `/usr/share/w/ai/skills/3d/` when the bundle is
installed. Not part of it: parametric CAD (FreeCAD), 3D-printing slicers, game
engines — other workflows.

## What the bundle actually did

1. Installed `blender`, `libdecor` (native Wayland), plus the Cycles GPU
   runtime this machine's GPU needs (`--asdeps`): AMD → `hip-runtime-amd` +
   `hiprt`; Intel Arc → `intel-compute-runtime`; NVIDIA → nothing (the driver
   runs Blender's precompiled CUDA/OptiX kernels).
2. `/etc/w/env.d/3d.sh` exports `BLENDER_SYSTEM_SCRIPTS=/usr/share/w/blender/scripts`
   — a version-independent scripts root whose `startup/w_integration.py` runs
   in every interactive Blender (never in `blender -b`). It (a) applies and
   live-updates the W theme, (b) copies the AI-bridge add-on into the running
   Blender version and enables it once. Until the next login a session shim
   (`~/.config/blender/<ver>/scripts/startup/w_session_shim.py`) does the same
   job, so the first launch after install is already integrated.
3. Per account (`w-pack setup 3d`, rootless): `uv tool install
   mcp-for-blender==2.1.3` (pinned) → `~/.local/bin/mcp-for-blender`, and the
   theme JSON `~/.config/w/blender-theme.json` (w-style axis `blender`).
4. Registered the MCP server for the W assistant (`/usr/share/w/ai/mcp.d/blender.conf`):
   every `w-ai` host (goose, Claude Code, Codex, OpenCode) gets it at launch.
   `w-ai status` → `MCP extra: blender` (or `(missing)` when the account has no
   uv tool yet — fix: `w-pack setup 3d`).

## Operating Blender as the assistant

The bridge: an add-on inside Blender listens on **localhost:9876** and starts
by itself with Blender (Auto-Start on). The MCP server relays your tool calls
to it. **Blender must be running** — if a tool reports it cannot connect,
start it (`w_launch_app`/launcher, or `blender <file.blend>`) and retry; do
not try to start the socket yourself. Two Blender instances: only the first
gets the port; tell the user which one you drive.

Work loop — inspect, change in small steps, verify:

1. **Inspect** — `get_scene_info` (needs a `user_prompt` argument: pass the
   user's request) and `get_object_info` for a named object. Never assume
   what is in the scene.
2. **Change** — `execute_blender_code` runs Python inside Blender (`bpy`,
   `bmesh`, `mathutils`). Prefer data-API edits (`bpy.data…`, bmesh) over
   context-dependent `bpy.ops`; set `obj.name` so you can find things later.
   Before large or destructive edits on a user's file, save first
   (`bpy.ops.wm.save_mainfile()` is allowed) or ask. Unsure about an operator,
   socket order or enum value → `bpy_api_lookup` / `describe_node_type` instead
   of guessing (Blender 5's API differs from older tutorials).
3. **Verify** — `get_viewport_screenshot` (look at it before claiming success)
   and re-read the object/scene info.
4. **Deliver** — `export_scene` (GLB/FBX of the scene, the selection or named
   objects), or render via code (`bpy.ops.render.render(write_still=True)` with
   `scene.render.filepath` set).

Assets and generation tools also present on the server:

- **Poly Haven** (CC0 HDRIs, textures, models; no key): `search_polyhaven_assets`,
  `download_polyhaven_asset`, `set_texture`. Check `get_polyhaven_status` first.
- **Poly Pizza / Sketchfab** (models) and **Hyper3D Rodin / Hunyuan3D / Tripo**
  (AI-generated meshes) need the user's own account key, entered in Blender →
  Edit → Preferences → Add-ons → MCP for Blender. W configures none of them
  and sends nothing on its own; check the matching `get_*_status` tool, and if
  it is off, say what it needs instead of failing silently. Cloud generation
  uploads the prompt/image to that service — tell the user.

### Safe mode — what code is refused

The server runs with `BLENDER_MCP_SAFE_MODE=1`: every script is checked
against an allowlist before it reaches Blender. Allowed: `bpy`, `bmesh`,
`mathutils`, pure-Python stdlib, rendering, open/save `.blend`, every
import/export operator, `bpy.path`. **Refused:** `os`/`sys`/`subprocess`/
`socket` and other process/file/network modules, `open`/`eval`/`exec`,
`bpy.app.handlers`/`timers`, drivers, `register_class`/`bpy.props`,
`bpy.ops.script.*`/`text.*`/`preferences.*`/`extensions.*`, `wm.append`/
`wm.link`. A rejection message names the line — rewrite with the allowed API
(e.g. paths via `bpy.path.abspath`, file output via export/render operators).
It guards against prompt injection from downloaded asset metadata; it is not a
sandbox. If the user deliberately wants it off for their account: copy
`/usr/share/w/ai/mcp.d/blender.conf` to `~/.config/w/ai/mcp.d/blender.conf`
and drop `BLENDER_MCP_SAFE_MODE=1` from `ARGS` (the user copy wins). Telemetry
(`DISABLE_TELEMETRY=true`) stays off either way.

### Without Blender's GUI

- Preview a model file (glTF/GLB, OBJ, STL, PLY, FBX, USD): import it into the
  running Blender (`bpy.ops.import_scene.gltf(filepath=…)`, `wm.obj_import`,
  `wm.stl_import`, `wm.ply_import`, `wm.usd_import`, `import_scene.fbx`) and `get_viewport_screenshot` — or headless,
  a `blender -b --python-expr` that imports it and renders a still.
- Batch work: `blender -b file.blend --python-expr '…'` or `-P script.py`;
  render: `blender -b file.blend -o //out_ -F PNG -f 1`. Background Blender has
  no MCP bridge and no W integration — by design.

## Theming — the W theme follower

Blender draws its own UI, so W themes it through the startup module: the
`blender` w-style axis writes `~/.config/w/blender-theme.json` (Blender's
Dark/Light preset by `W_APPEARANCE` + W colours by RNA path); the module turns
it into the user preset **W** (`~/.config/blender/<ver>/scripts/presets/interface_theme/W.xml`)
and makes it active. Ownership rule — Blender records the active preset in
Preferences → Themes:

- No theme ever chosen, or **W** chosen → W follows: `w-theme set` recolours a
  running Blender within ~2 s, and a closed one at its next start.
- Any other preset picked → stays the user's; W no longer touches it. To
  return: Preferences → Themes → **W**.

The Quick Setup splash on first start already shows Theme **W**; "Continue"
keeps it.

## Rendering on the GPU (Cycles)

Edit → Preferences → System → Cycles Render Devices: **HIP** (AMD), **oneAPI**
(Intel Arc), **OptiX/CUDA** (NVIDIA) — then Render Properties → Device: GPU.
An AMD desktop CPU with integrated graphics (Ryzen 7000+) shows up as a second
HIP device **named after the CPU** (e.g. "AMD Ryzen 7 7700") — that is the
iGPU, not the CPU; untick it, it only slows the discrete card down. In code:
`d.use = (d.type == "HIP" and "Radeon" in d.name)` over
`bpy.context.preferences.addons["cycles"].preferences.devices`.
If no device is listed: AMD/Intel — `pacman -Q hip-runtime-amd hiprt` /
`intel-compute-runtime` (re-run `w-pack install 3d` to add them); NVIDIA —
the proprietary driver must be active (`nvidia-smi`); if Blender asks to
compile kernels, the 5 GiB `cuda` toolkit is the user's decision. EEVEE needs
no runtime.

## Troubleshooting

- **Tools say Blender is not connected** — Blender not running, a second
  instance holds no port, or the add-on is disabled: Preferences → Add-ons →
  "MCP for Blender" on, then 3D viewport N-panel → tab "MCP for Blender" →
  "Connect to MCP server". If the user disabled it
  deliberately, W does not re-enable it (once per Blender version).
- **No W theme, no add-on in a session that started before the pack** — the
  session shim covers the installed Blender version; after a Blender upgrade
  before the next login, log out and in (env.d).
- **Add-on "outdated" warning** — W copies the add-on from the pinned uv tool
  at each Blender start; restart Blender after `w-pack setup 3d`.
- **"Save Theme" in Preferences errors** — upstream add-on bug (it stores its
  server object on `bpy.types`); the W module works around it for its own
  preset only.
- `w-ai status` shows `blender (missing)` — `w-pack setup 3d` for this account.

## Removal

`w-pack remove 3d` (add `--packages` to uninstall Blender) / `w-pack unsetup 3d`
(own account): removes the uv tool, the add-on copies, the W presets, the
shim, the theme JSON and the module's state. Kept: every `.blend` file and
Blender's current theme (pick another preset to change it). Never delete user
`.blend` files or `~/.config/blender` yourself.
