---
name: graphics
description: >-
  The `graphics` W-Pack: GIMP 3 (raster/photo), Inkscape 1.4 (vector), Krita 6
  (painting) and G'MIC — how they follow the W theme and how YOU operate them:
  the Inkscape MCP server (typed SVG tools + live window bridge), the GIMP MCP
  bridge (run Python inside a running GIMP, screenshot its viewport) and both
  headless CLIs. Load this to draw, edit, retouch, vectorise, export or
  batch-convert images, for GIMP/Inkscape/Krita colours or plug-ins, or for
  generative AI in an editor — when `w-pack status graphics` reports installed.
---

# W-Pack: graphics

The 2D creative bundle, all from the official `extra` repo: **GIMP 3.2** (raster
editing, photo retouching; GTK3), **Inkscape 1.4** (vector drawing, design,
SVG; GTK3), **Krita 6** (digital painting; Qt6, native Wayland) and
**G'MIC-Qt** (500+ filters inside GIMP: Filters → G'MIC-Qt). Curated into
`/usr/share/w/ai/skills/graphics/` when the bundle is installed. Not part of
it: Blender (3D) and darktable/RawTherapee (RAW photo) — other workflows,
future bundles; the base system already ships `imv` (viewing), `imagemagick`,
`grim`/`slurp`/`satty` (screenshots + annotation).

## What the bundle actually did

1. Installed `gimp`, `gimp-plugin-gmic`, `inkscape`, `krita` (~950 MiB with
   dependencies; `python-mcp`, which the GIMP bridge runs on, is already there
   from the base AI module).
2. Seeded, once per account (class `user`, never overwritten):
   `~/.config/GIMP/3.0/gimprc` with `(theme "System")` +
   `(theme-color-scheme system)`, `~/.config/inkscape/preferences.xml` with
   the W-following theme state (see Theming), `~/.config/kritarc` with
   `[theme] Theme=W`, and `~/.config/mcpinkscape.conf`. An existing `kritarc`
   (Krita ran before) gets `Theme=W` added only while it has no theme key.
3. Registered two **MCP servers** for the W assistant through the `mcp.d`
   channel (`/usr/share/w/ai/mcp.d/inkscape.conf`, `gimp.conf`): every
   `w-ai` launch (goose, Claude Code, Codex) gets them as launch flags, with
   whatever model the active profile names — local Ollama or cloud. No key of
   the bundle's own.
4. Per account (`setup-user.sh`, rootless via `w-pack setup graphics`):
   `mcpinkscape` via `uv tool install` (→ `~/.local/bin/mcpinkscape`) and the
   GIMP bridge `gimpmcp` (pinned release, sha256-checked) unpacked into
   `~/.config/GIMP/3.0/plug-ins/gimpmcp/`. A drop-in is offered only when its
   binary/file exists for the account — `w-ai status` line `MCP extra:` shows
   `inkscape, gimp` or `(missing)` per server.

No session env, no window rules, no units. Krita's generative-AI plugin
(krita-ai-diffusion) is NOT installed by this bundle — see "Generative AI".

## Theming — what follows W and what does not

| App | How | Notes |
|---|---|---|
| GIMP | theme `System` = GTK chrome → W's gtk axis (`w-gtk`); colour scheme `system` → light/dark from the appearance axis | seeded only if GIMP had not run before; otherwise one visit: Edit → Preferences → Interface → Theme: **System**, colour scheme **System**. GIMP rewrites `gimprc` itself — W never touches it again |
| Inkscape | seeded `preferences.xml`: no `gtkTheme` (= "Use system theme (w-gtk)"), `iconTheme` multicolor + symbolic, `/options/boot/theme` "custom" | **without the seed a first launch is Adwaita**: Inkscape's Quick Setup applies its default "Colorful" row, which hard-codes the GTK theme to Adwaita. The seeded "custom" makes that first-run step a no-op (the Appearance combo shows empty — expected). An account whose Inkscape ran before the pack: Preferences → Interface → Theming → Change GTK theme → **Use system theme (w-gtk)** |
| Krita | theme **"W"** in Settings → Themes = the KDE colour scheme W's qt axis renders to `~/.local/share/color-schemes/W.colors` on every theme switch; selected by `kritarc` `[theme] Theme=W` | seeded / added while unset; a theme the user picked stays. Re-rendered colours reach Krita at its next start |
| G'MIC-Qt | Qt dialog inside GIMP → W's qt axis (qt6ct palette) | — |

`w-theme set` recolours GIMP, Inkscape and Krita at their next start (GTK3 does
not live-reload the theme name; Krita reads the scheme file when it starts).

## Operating the editors as the assistant

Three surfaces, from most to least capable. Pick by what the user wants:

### 1. Inkscape — MCP server `mcpinkscape` (57 typed tools)

Prefer this for anything vector: diagrams, posters, icons, logos, layout
fixes, exports. Tools are typed and safe — no shell, no raw SVG replacement:

- **Documents:** `create_document`, `open_document`, `save_document`,
  `list_documents`, `get_document_info`, `list_layers`, `create_layer`.
  Documents live under **`<Pictures>/mcpinkscape/`** — `mcpinkscape` under the
  user's Pictures folder, whose name follows the system language
  (`xdg-user-dir PICTURES`: `~/Pictures`, `~/Изображения`, …). It is the
  configured `document_root`; paths outside it are refused — copy a user's
  file in, or ask them to save there.
- **Draw:** `create_rectangle/ellipse/circle/line/polyline/polygon/path/text`,
  `set_text`; absolute units accepted (`mm`, `cm`, `in`, `pt`, `px`).
- **Style/transform:** `set_fill`, `set_stroke`, `set_style`, `set_opacity`,
  `create_gradient` + `apply_gradient`, `move/rotate/scale_objects`,
  `group/ungroup`, `raise/lower`, `duplicate`, `delete`, `import_image`.
- **See your work:** `render_snapshot` → `get_snapshot_base64` (look at the
  PNG before declaring done), `export_document` (svg / plain svg / png / pdf).
- **Live window** (`live_*`: select, list selection, set style, move, rotate,
  scale, render): drives the **focused** Inkscape window through Inkscape's
  own CLI actions. `live_status` / `server_status` tell which bridge is up
  (`active_window` on W; the native socket bridge needs an ABI-matched
  build and is not shipped). Live edits have no revision-conflict guard —
  inspect, apply a bounded change, inspect again.

Config: `~/.config/mcpinkscape.conf` (JSON; the server does not start
without it — `w-pack setup graphics` re-seeds a missing one). Logs:
`--log-level` in the drop-in, or `~/.local/state/mcpinkscape/`.

### 2. GIMP — MCP bridge `gimpmcp` (3 tools, full Python access)

`execute_gimp_code` runs Python **inside the running GIMP** with `Gimp`,
`GimpUi`, `Gegl`, `Gio`, `GLib`, `pdb` and the active `image`/`drawables` in
scope; `get_gimp_info` lists open images/layers; `get_gimp_viewport_screenshot`
returns the current image as a PNG you can look at. This is the vision loop:
change → screenshot → judge → change.

**It answers only while the bridge is started in GIMP:** Filters →
Development → **MCP D-Bus - Start** (owns `org.gimp.mcp.Bridge` on the
session bus; Stop is next to it). If a tool reports the service is not
running, ask the user to start it — there is no CLI to do it from outside.
GIMP 3 Python API cheat-sheet for `execute_gimp_code`:

```python
img = Gimp.get_images()[0]                      # or the `image` in scope
layer = img.get_selected_layers()[0]
Gimp.context_set_foreground(Gegl.Color.new("#ff0000"))
img.resize(1024, 768, 0, 0); layer.resize_to_image_size()
proc = pdb.lookup_procedure("gimp-image-flatten")   # PDB call, GIMP 3 style:
cfg = proc.create_config(); cfg.set_property("image", img); proc.run(cfg)
Gimp.file_save(Gimp.RunMode.NONINTERACTIVE, img, Gio.File.new_for_path("/tmp/out.png"), None)
```
(`pdb.run_procedure(name, [args])` from GIMP 2.99 is gone in 3.x — use
`lookup_procedure` + `create_config` + `run`; `proc.get_arguments()` lists the
property names.)

### 3. Headless CLIs (no GUI, batch, always available)

- **Inkscape:** `inkscape --export-type=png --export-dpi=300 --export-filename=out.png in.svg`;
  actions chain: `inkscape --actions="select-all;object-to-path;export-filename:out.svg;export-do" in.svg`
  (`inkscape --action-list` — ~1000 actions); `--query-all` for object bounds;
  `--export-id=<id> --export-id-only` for one object; PDF/EPS/PS in, SVG/PNG/PDF out.
  Bitmap → vector: `--actions="select-all;selection-trace:…"` is fiddly — Inkscape's
  Path → Trace Bitmap (potrace) in the GUI is the reliable path.
- **GIMP:** `gimp -i --no-fonts --no-data --batch-interpreter=python-fu-eval -b '<python>' --quit`
  — the same Python API as the bridge (`Gimp.file_load(Gimp.RunMode.NONINTERACTIVE, Gio.File.new_for_path("in.jpg"))`,
  `img.scale(w, h)`, `Gimp.file_save(...)`), ~1 s with `--no-fonts --no-data`
  (drop them only when the script needs fonts or brushes: a cold start is then
  ~1 min). Script-Fu is `--batch-interpreter=plug-in-script-fu-eval -b '(…)'`.
  **Both need an account whose GIMP has run at least once**: on a never-run
  profile the interpreters are not registered yet (no `pluginrc`), `-b` is
  ignored and GIMP just reports "running as a background process" — run
  `gimp -i --quit` once, then retry. For plain conversions/resizes prefer
  `magick` from the base system.
- **Krita:** `krita --export --export-filename out.png in.kra` (convert only).

## Typical operations

| Goal | Do this |
|---|---|
| "Make me a diagram / poster / icon" | mcpinkscape: `create_document` (page size in mm) → draw → `render_snapshot` → look → iterate → `export_document`; tell the user the path under `$(xdg-user-dir PICTURES)/mcpinkscape/` |
| Fix something in the SVG the user has open | `live_status` → `live_list_selection` / `live_set_style` etc. on the focused window; for structural edits ask them to save, then open the file with `open_document` (copy into the document root) |
| Retouch / adjust a photo interactively | GIMP + bridge started → `get_gimp_info` → `execute_gimp_code` with GEGL ops (`layer.apply … `, `pdb.run_procedure("gimp-drawable-levels", …)`) → `get_gimp_viewport_screenshot` to verify |
| Batch convert / resize / strip metadata | `magick` (base) first; GIMP batch only when a GIMP-specific op is needed |
| Apply an artistic filter | G'MIC-Qt inside GIMP (Filters → G'MIC-Qt, ~500 filters) in the GUI; headless the same engine is the `gmic` CLI (`gimp-plugin-gmic` depends on `gmic`): `gmic in.png fx_bokeh 3,8,0,30,8,4,0.3,0.2,210,210,80,160,0.7,30,20,20,1,2,170,130,20,110,0.15,0 -o out.png`; `gmic -h fx_` lists filters |
| Generative fill / inpaint / text-to-image | see "Generative AI" — not available until the `ai-image` bundle; do not promise it |
| The assistant does not see the servers | `w-ai status` → `MCP extra:`; `(missing)` = run `w-pack setup graphics` as that user (rootless); a fresh `w-ai` launch picks them up (flags are computed per launch) |
| GIMP looks stock, not W | account ran GIMP before the pack — Preferences → Interface → Theme **System** + colour scheme **System** (see Theming) |
| Inkscape looks like Adwaita, not W | its Quick Setup ran before the pack seeded the prefs — Preferences → Interface → Theming → **Use system theme (w-gtk)** (one visit; Inkscape keeps it) |
| Krita is not in W colours | Settings → Themes → **W** (the pack sets it only while no theme was chosen); if "W" is missing from the list, `w-style apply qt` as the user re-renders `~/.local/share/color-schemes/W.colors` |
| Reset the seeded configs | `w-reset graphics` (re-seeds `gimprc` / Inkscape `preferences.xml` / `kritarc` / `mcpinkscape.conf` from the bundle's skel copies, with backup — for `preferences.xml` and `kritarc` that means the app's other settings go too, say so) |
| Update | `w-update` — pacman owns the apps; `uv tool upgrade mcpinkscape` for the Inkscape server; the GIMP bridge is version-pinned in the bundle (bump = new W release, then `w-pack refresh graphics`) |
| Check the bundle | `w-pack status graphics` |
| Remove | `w-pack remove graphics` — drop-ins, plug-in, uv tool and its state go; `gimprc`/`preferences.xml`/`kritarc`/`mcpinkscape.conf` (class `user`) and every image stay; the four apps only with `--packages` (python-mcp is the base system's, never on that line) |

## Generative AI — the honest state (2026-09)

- **Krita + krita-ai-diffusion** (inpaint/outpaint/txt2img/live painting;
  Flux 2, Qwen-Image, SDXL; local ComfyUI or the author's cloud) is the mature
  FOSS option and the reason Krita is in this bundle. It is **not installed
  yet**: the plugin's Qt6/Krita 6 port is merged upstream (2026-08-23) but the
  latest release (1.53.0) still targets Krita 5, and its backend belongs to
  the coming `ai-image` bundle (ComfyUI as a W service, GPU variant, model
  store on a nested subvolume — the Ollama pattern). Until then a user can
  install the plugin by hand from its GitHub main branch, at their own risk.
- **GIMP**: no maintained generative plug-in; the ComfyUI clients that exist
  are hobby projects and will be evaluated against the `ai-image` backend.
  Intel's OpenVINO plug-ins want a from-source GIMP — not on W.
- **Inkscape**: "AI" in vector means an LLM writing SVG — that is you, through
  mcpinkscape's typed tools (or writing SVG to a file and opening it).

## Gotchas

- **Two GIMP profiles is one profile:** GIMP 3.2 still uses `~/.config/GIMP/3.0/`
  (the "3.0" is the config-format generation, not the version).
- **A seeded gimprc is ignored wholesale if any key is invalid** (GIMP backs it
  up as `gimprc~` and silently uses defaults) — never add keys from memory;
  `prefer-dark-theme` in particular does not exist despite the system gimprc's
  comment.
- **The GIMP bridge is per running GIMP** and per session: after GIMP restarts,
  Start it again. Two GIMP instances cannot both own the bus name.
- **mcpinkscape's `document_root` is a sandbox**: `open_document` refuses paths
  outside `<Pictures>/mcpinkscape/`; copying is fine (`cp`), then work on the
  copy and tell the user where it is. Never spell the Pictures folder by name —
  resolve it (`xdg-user-dir PICTURES`); it is renamed when the language changes.
- **`live_*` tools act on the focused window** — if the user has several
  Inkscape windows, say which one you are about to touch.
- **Wayland tablets** (Krita/GIMP pen input) are handled by Hyprland/libinput;
  no `xf86-input-wacom`, no `xsetwacom` — pressure/tilt work out of the box
  on supported hardware.
- **Stale VM → 404 on install** — general packs.md gotcha: `w-update` first.
