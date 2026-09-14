---
name: office
description: >-
  The `office` W-Pack: LibreOffice (gtk3 backend, follows W's theme axes), the
  PDF tools (pdfarranger for page surgery, xournalpp for annotation), the
  Obsidian markdown knowledge base and the metric-compatible fonts that keep
  docx/xlsx/pptx layouts intact. Load this for documents, spreadsheets,
  presentations, editing/merging PDFs, notes, Obsidian, office suites in general
  — and whenever you convert, generate or edit a docx/xlsx/pptx/odt/pdf yourself
  (headless `soffice`, python-uno recipes inside) — when `w-pack status office`
  reports installed.
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
  opt-out no re-render overrides. The write is safe with Obsidian running too
  (it never re-reads the file, only writes its own in-memory state — at worst
  the vault returns to "fresh" and the next render heals it). Once enabled it
  is **live** — Obsidian hot-reloads the file on every save, so `w-theme set`
  recolours a running Obsidian with no restart.
- **Vault-registry watcher** (`w-obsidian-vaults.path`, a per-account systemd
  user path unit enabled by the bundle's user setup): the axis can only theme
  vaults it can find, and the only place that knows vault paths is Obsidian's
  own `~/.config/obsidian/obsidian.json`, rewritten on every vault create/open.
  The watcher re-runs `w-style apply obsidian` on each change, so a vault
  created **after** the last render (a fresh install: the first vault appears
  well after the login render) is themed the moment it is registered — in
  practice before Obsidian even finishes creating it, so the new vault opens
  in the W theme straight away. Vaults outside `$HOME` are covered too — the
  registry holds absolute paths.

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
| `<vault>/.obsidian/appearance.json` | **Obsidian** — W touches it with ONE guarded write: adds `enabledCssSnippets:["w"]` only to a vault that has no such key, jq-merging everything else | the enable-by-default; a key that exists without "w" is the user's curation and is never overridden — the in-app toggle is a real opt-out |
| `/etc/systemd/user/w-obsidian-vaults.{path,service}` + the account's `graphical-session.target.wants/` symlink | **W** (managed; symlink by setup-user/teardown-user) | the vault-registry watcher — new vaults themed on creation |
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

## Working on documents as the assistant

You need nothing beyond this bundle to convert, build or edit documents: Arch's
LibreOffice puts `uno.py`/`unohelper.py` into the system `site-packages`, so
`python3 -c 'import uno'` works, and `soffice --headless` is a full converter.
Do the work yourself with the shell — do not tell the user to click through
menus for something a one-liner does. Both recipes below were verified on
LibreOffice 26.2.

**Always pass a private profile** (`-env:UserInstallation=file:///tmp/lo-$USER`)
to a headless `soffice`. Without it, a LibreOffice window the user has open
swallows the command (single-instance IPC) and the headless run silently does
nothing.

**Convert / export** (any Writer/Calc/Impress format in either direction —
pdf, docx, odt, xlsx, csv, pptx, html, txt):

```
soffice -env:UserInstallation=file:///tmp/lo-$USER --headless \
  --convert-to pdf --outdir "$DIR" "$FILE"          # docx/odt/xlsx/pptx → pdf
soffice … --headless --convert-to docx report.md    # md/txt → docx (Writer import)
soffice … --headless --convert-to csv sheet.xlsx    # first sheet → csv
```

**Edit a document in place (python-uno):** start a headless listener, connect,
work through the UNO API, save, terminate. Pattern (Writer find/replace → save
as DOCX + export PDF):

```bash
soffice -env:UserInstallation=file:///tmp/lo-$USER --headless --invisible \
  --norestore --accept='socket,host=127.0.0.1,port=2002;urp;' &
```
```python
import time, uno
from com.sun.star.beans import PropertyValue
def pv(n, v): p = PropertyValue(); p.Name = n; p.Value = v; return p
local = uno.getComponentContext()
resolver = local.ServiceManager.createInstanceWithContext("com.sun.star.bridge.UnoUrlResolver", local)
for _ in range(30):                       # the listener needs a few seconds to come up
    try: ctx = resolver.resolve("uno:socket,host=127.0.0.1,port=2002;urp;StarOffice.ComponentContext"); break
    except Exception: time.sleep(1)
desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
doc = desktop.loadComponentFromURL(uno.systemPathToFileUrl(SRC), "_blank", 0, (pv("Hidden", True),))
rd = doc.createReplaceDescriptor(); rd.SearchString = "NAME"; rd.ReplaceString = "World"
doc.replaceAll(rd)
doc.storeToURL(uno.systemPathToFileUrl(OUT_PDF), (pv("FilterName", "writer_pdf_Export"),))
doc.storeAsURL(uno.systemPathToFileUrl(OUT_DOCX), ())
doc.close(True); desktop.terminate()
```

Same bridge for Calc (`doc.Sheets[0].getCellRangeByName("A1").String = …`,
`getCellByPosition(col,row)`, formulas via `.Formula`) and Impress
(`doc.DrawPages`). Filter names: `writer_pdf_Export`, `calc_pdf_Export`,
`impress_pdf_Export`, `MS Word 2007 XML`, `Calc MS Excel 2007 XML`,
`Impress MS PowerPoint 2007 XML`. Prefer `find_and_replace`/UNO over
regenerating a file from scratch — the user's formatting survives.

**Generate a new document from data** (no LibreOffice involved until export):
write Markdown or HTML and `--convert-to docx|odt|pdf`. For fine layout
control, `python-docx`/`openpyxl` are ordinary pip/uv packages — but the UNO
route above is already installed and handles every format LibreOffice does.

**Obsidian vaults are plain Markdown folders.** The registry
`~/.config/obsidian/obsidian.json` lists every vault path (`vaults.<id>.path`);
read/write notes with your normal file tools, keep `<vault>/.obsidian/` alone.
No plugin or API is needed to add or edit a note.

**PDF page surgery, scripted:** pdfarranger pulls in `python-pikepdf` (and
`qpdf`), so merge/split/rotate is a few lines of `import pikepdf` —
`pikepdf.Pdf.open(a).pages.extend(pikepdf.Pdf.open(b).pages)`, `pages[i].rotate(90, relative=True)`,
`del pdf.pages[3:]`, `save(out)` — or `qpdf --empty --pages a.pdf b.pdf -- out.pdf`.
Open pdfarranger/xournalpp only when the user wants to do it by hand.

## AI inside LibreOffice — the honest state (2026-09)

- **LibreOffice has no built-in AI.** Release notes 25.8 / 26.2 / 26.8 carry no
  assistant, no LLM feature; there is nothing to enable. Do not suggest one
  "in the menu".
- **Third-party sidebar extensions** (WriterAgent, localwriter, LibreThinker)
  bring a chat panel into Writer, but each carries its own endpoint/API-key
  settings **outside** W's assistant profile (`w-ai`) — a second, unmanaged
  key. W does not install them; if the user asks, say so plainly and let them
  install the `.oxt` themselves (Tools → Extension Manager). An Ollama profile
  is the one case that lines up (`http://localhost:11434`, no key).
- **You are the AI layer of this bundle:** the recipes above are how W's
  assistant works on documents — through the shell and UNO, with the model the
  user's `w-ai` profile names. An MCP server that drives a live LibreOffice
  window (visible edits, 100+ typed tools) is tracked as a future candidate;
  it is not installed today.

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
- **A new vault created later** gets its `w.css` AND its default enable the
  moment Obsidian registers it (the registry watcher) — no clicks, unless its
  snippet list is already curated. Normally it opens themed at once; if the
  render loses the race with the vault window, the theme shows after an app
  restart (Obsidian reads appearance.json only at vault load) — or toggle "w"
  on, it is already in the snippet list. Watcher status:
  `systemctl --user status w-obsidian-vaults.path` (as the user).
- **`w-pack remove office` while Obsidian is running** leaves "w" in that
  vault's `appearance.json` (the app would rewrite it anyway): a snippet name
  without its file is invisible and harmless — upstream keeps such names on
  purpose.
- **`w-pack remove office` keeps every document, vault and profile** — user
  data is never deleted; the W wiring goes away: env drop-in, the obsidian
  snippet and its enable entry, the language pack with `--packages`.
- **Do not suggest OnlyOffice/Calligra/Gnumeric** as "the real office suite" —
  they are deliberately not packed (AUR-only or redundant). Users who want them
  can install them manually; W does not oppose them, it just does not curate
  them.
- **zathura already views PDFs** — do not suggest evince, and do not reinstall
  a viewer when the user asks about "opening PDFs".
