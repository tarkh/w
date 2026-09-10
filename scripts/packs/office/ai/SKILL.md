---
name: office
description: >-
  Working with the `office` W-Pack on W Linux: the LibreOffice suite (Writer,
  Calc, Impress, Draw, Math) pinned to the gtk3 backend so it rides W's gtk and
  appearance theme axes, the PDF tools (pdfarranger for page surgery, xournalpp
  for annotation and handwriting) and the Obsidian markdown knowledge base —
  plus the metric-compatible fonts that keep foreign docx/xlsx/pptx layouts
  intact. Load this when the user asks about documents, spreadsheets,
  presentations, editing or merging PDFs, printing, notes, Obsidian, or office
  suites in general, and `w-pack status office` reports installed.
---

# W-Pack: office

The documents/office bundle. Everything here comes from the official `extra`
repo (no AUR), chosen for being the reliable, non-redundant core of office
work — W deliberately does not ship a second office suite (OnlyOffice is
AUR-only and duplicates LibreOffice) or a second PDF viewer (the base system
already has zathura).

## What the user has

| Tool | Role | Notes |
|---|---|---|
| **LibreOffice** (`soffice`) | docx/xlsx/pptx/odf editing — Writer, Calc, Impress, Draw, Math | feature branch (`libreoffice-fresh`), matches W's rolling base; en-US UI built in, other UI languages added per system locale |
| **pdfarranger** | merge / split / reorder / rotate / crop PDF pages | the "change the pages" half; viewing is zathura's job |
| **xournalpp** | PDF annotation, handwriting, stylus notes | the paper-margin companion |
| **Obsidian** | markdown knowledge base over local folders | freeware (own licence) — W ships only the package name, pacman fetches the binary |
| **ttf-liberation + ttf-carlito** | metric-compatible Arial/Times/Courier and Calibri | without them, a docx authored on Windows re-flows and breaks layout |
| **gst-plugins-base-libs** | media embedded in Impress presentations | a LibreOffice optdep nothing else in the base pulls |

PDF *viewing* is not this bundle's job: the base system ships **zathura**
(themed, `application/pdf` default) and Firefox. Printing and scanning are also
base-system territory (driverless CUPS, `simple-scan`) — LibreOffice prints
through that stack out of the box.

## How it is themed (read this before answering any look question)

The GTK side needs **no bundle axis** — that is the design, not an omission.
Obsidian (Electron, no GTK) gets the bundle's own axis:

- **LibreOffice** renders through its **gtk3 VCL backend** (pinned by
  `/etc/w/env.d/office.sh`, `SAL_USE_VCLPLUGIN=gtk3`). Window chrome follows the
  w-style `gtk` axis (adw-gtk3 + the `W_GTK_*` named colours) and dark mode
  follows the `appearance` axis (`gtk-application-prefer-dark-theme`, honoured
  automatically since LO 7.5). The **automatic icon theme** pairs
  `colibre`/`colibre_dark` with light/dark on a generic desktop like Hyprland —
  no user setting is needed and none is seeded.
- **pdfarranger / xournalpp** are plain GTK3 apps — same two axes, zero config.
- **Obsidian** (Electron) is themed by the bundle's own axis `wstyle/400-obsidian`:
  on every theme switch (and login) it renders W's tokens into
  `<vault>/.obsidian/snippets/w.css` for **every vault** registered in
  `~/.config/obsidian/obsidian.json`. The snippet carries the full W palette —
  backgrounds from the surface ramp, text tones, the accent (fill and ink kept
  apart), the ANSI hue wheel for semantic/code colours, graph and scrollbar.
  Both `.theme-dark` and `.theme-light` get the same values (a W theme has one
  appearance; Obsidian's "adaptive" base theme follows the system colour
  scheme). **The snippet is enabled by default**: the axis makes one guarded
  write into the vault's `appearance.json` — a vault with no
  `enabledCssSnippets` key gets `{"enabledCssSnippets":["w"]}` (jq-merge, every
  other key preserved); a key that already exists without "w" is the user's
  own curation (including "had w, turned it off" — Obsidian keeps the key with
  an empty array) and is **never** touched, so the in-app toggle is a real
  opt-out no re-render overrides. The write only happens with Obsidian closed
  (a running app holds the file in memory and would overwrite it); a skipped
  pass self-heals on the next render. Once enabled it is **live** — Obsidian
  hot-reloads the file on every save, so `w-theme set` recolours a running
  Obsidian with no restart.

**Why the gtk3 pin:** unpinned, LO auto-detects its UI backend and may pick the
Qt6 one (qt6-base is installed for Quickshell), which has documented Wayland
scroll-lag and would style the suite through Kvantum instead of the W GTK
theme. Outside a graphical session (bare SSH shell) the env file is not
sourced and LO falls back to auto-detection — a deliberate degradation, not a
bug.

## What W owns and what it does not

| Path | Owner | Why |
|---|---|---|
| `/etc/w/env.d/office.sh` | **W** (managed, re-applied on update) | the gtk3 VCL pin |
| `<vault>/.obsidian/snippets/w.css` | **W**, axis `400-obsidian` (re-rendered on every theme switch/login; deliberately NOT a manifest row) | the Obsidian palette |
| `~/.config/libreoffice/4/user/registrymodifications.xcu` | **LibreOffice itself** | LO rewrites it on every exit — seeding or owning it would mean two writers on one file, and the defaults already do the right thing (see above) |
| `<vault>/.obsidian/appearance.json` | **Obsidian** — W touches it with ONE guarded write: adds `enabledCssSnippets:["w"]` only to a vault that has no such key, only with the app closed, jq-merging everything else | the enable-by-default; a key that exists without "w" is the user's curation and is never overridden — the in-app toggle is a real opt-out |
| `<vault>/.obsidian/**` (the rest) | **the user** | per-vault settings, unknown paths |
| `~/.config/mimeapps.list` | the base `files` module | the bundle does NOT hijack the .docx→Writer default; Nemo offers it in "Open with" |

## Localization

- **UI language:** setup.sh installs `libreoffice-fresh-<lang>` for the system
  locale (region-specific first, probed against pacman's sync db). `en_*`
  locales need nothing — the en-US UI is built in.
- **Spell-check is NOT this bundle's job:** `w-langpack` already owns
  `hunspell-<lang>` for the system locale, and LibreOffice reads
  `/usr/share/hunspell` natively. Never suggest a LibreOffice dictionary
  package.
- **Java is deliberately absent** (a LibreOffice optdep): Writer/Calc/Impress
  work fully without it; only niche filters/macros want it. If the user hits
  one, `sudo pacman -S jre-openjdk` — but ask first, it is ~200 MiB.

## Typical operations

| Goal | Do this |
|---|---|
| Write/edit a document | `soffice --writer <file>` or launch from the launcher (LibreOffice Writer) |
| Merge or reorder PDF pages | `pdfarranger <file.pdf>` (drag pages, export) |
| Annotate a PDF / hand-write notes | `xournalpp <file.pdf>` |
| Take notes | `obsidian` — create a vault wherever the user wants their markdown to live |
| Change light/dark | normal W appearance toggle — every app here follows it (LO/pdfarranger/xournalpp on next launch, Obsidian live once its snippet is enabled) |
| Theme Obsidian | nothing to run: `w-theme set` re-renders the snippet into every vault; force a re-render with `w-style apply obsidian` (as the user, no sudo) |
| Another UI language | change the system locale (`w-locale set`), then `sudo w-pack refresh office` re-runs the language-pack step |
| Update the software | `w-update` — pacman owns every package here; LibreOffice has no self-updater to disable, nothing to do |
| Check the bundle | `w-pack status office` |
| Reset W's config for the bundle | `w-reset office` — restores the env drop-in from the manifest and re-renders the Obsidian snippet via its axis |

## Gotchas

- **The gtk3 pin activates at the next login** (session env). Until then, or
  when a pack was installed mid-session, LibreOffice may start with the
  auto-detected backend once — harmless, next launch is pinned.
- **`.docx` may not open in Writer by default** — the mimeapps list belongs to
  the base `files` module and this bundle does not touch it. First
  "Open with → LibreOffice Writer" from Nemo, or set the default once.
- **A docx opened without the metric fonts would break layout** — the fonts are
  part of the bundle, so this only bites for files opened in *other* software.
  Substituting Arial→Liberation Sans is metric-exact; it is not a rendering
  bug when the glyph shapes differ slightly.
- **Toggled the snippet off in Obsidian? W respects it forever.** The vault's
  `appearance.json` now has `enabledCssSnippets` without "w" — that reads as
  "user-curated" and no render re-adds it. Re-enable by hand: Settings →
  Appearance → CSS snippets → "w". The reverse also holds: a vault where the
  user had other snippets before W's first pass is "curated" too — its "w"
  toggle is the user's, W never adds to a curated list.
- **Obsidian running during install/theme switch?** The enable pass skips (the
  app holds appearance.json in memory and would overwrite the write) and
  self-heals at the next render with the app closed — next login or theme
  switch. The CSS file itself is always refreshed, and an already-enabled
  snippet still recolours live.
- **A new vault created later** gets its `w.css` AND its default enable at the
  next login or `w-style apply obsidian` — no clicks, unless its snippet list
  is already curated.
- **`w-pack remove office` keeps every document, vault and profile** — user
  data is never deleted; the W wiring goes away: env drop-in, the obsidian
  snippet and its enable entry, the language pack with `--packages`.
- **Do not suggest OnlyOffice/Calligra/Gnumeric** as "the real office suite" —
  they are deliberately not packed (AUR-only or redundant). Users who want them
  can install them manually; W does not oppose them, it just does not curate
  them.
- **zathura already views PDFs** — do not suggest evince, and do not reinstall
  a viewer when the user asks about "opening PDFs".
