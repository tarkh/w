---
name: dev
description: >-
  Working with the `dev` W-Pack on W Linux: the Zed editor (GUI, native Wayland), the
  git tooling (delta, lazygit, W's ~/.gitconfig split) and mise (per-project runtime
  versions) — how they are themed, where their config lives, which tool owns which
  language, and how W's own AI (w-mcp tools and the goose agent) is wired into the
  editor. Load this when the user asks about the code editor, IDE, Zed, git colours,
  diffs, lazygit, or about node/go/rust/java versions, nvm, .tool-versions or mise,
  and `w-pack status dev` reports installed.
---

# W-Pack: dev

The development-environment bundle. It installs and integrates **Zed** (a
GPU-accelerated, natively-Wayland code editor from the official `extra` repo), the
**git tooling** — `delta` as the diff pager plus `lazygit` as the TUI, both themed,
and W's ownership split for `~/.gitconfig` — and **mise**, the per-project runtime
version manager. Curated into
`/usr/share/w/ai/skills/dev/` when the bundle is installed; present only if
`w-pack status dev` reports installed. W also ships two terminal editors in the base
system, which this bundle does not replace: **micro** (the default `$EDITOR`) and
**helix**.

`git` itself is NOT installed by this bundle — it is already part of the base system
(`apply.sh --update` and `--ai` both install it). What the bundle adds is the
configuration and theming git never had.

## What the user has — Zed

- **Launch:** `zed` (a symlink the bundle creates) or `zeditor` — Arch names the
  binary `zeditor`, the desktop entry is `dev.zed.Zed.desktop`. If `zed` is missing,
  something else already owned that name; use `zeditor`.
- **Theme:** the W theme, rendered by the w-style axis `400-zed` into
  `~/.config/zed/themes/w.json` (W-owned, regenerated on every `w-theme set`).
  **Live:** Zed watches that file, so a running editor recolours itself on a theme
  switch — no restart. Window translucency follows the active theme's
  `W_FX_APP_BG_OPACITY`, so Zed frosts like the rest of the desktop.
- **Settings:** `~/.config/zed/settings.json` — **the user's file** (seeded once,
  never overwritten). It selects the theme `"W"`, W's fonts, disables telemetry and
  Zed's self-updater (pacman owns the package), turns off inline edit predictions,
  and wires the two AI integrations below.
- **AI inside the editor:**
  - `context_servers.w-mcp` — W's MCP server. Zed's own agent gets the same W
    knowledge (skills as MCP resources) and the same tiered tools as `w-ai`.
  - `agent_servers.goose` (`goose acp`) — W's default assistant host, over the Agent
    Client Protocol, in Zed's agent panel. Needs a configured provider/model/key:
    check with `w-ai status`, fix in W Hub → AI or `w-ai profile`.

## What the user has — git

Ownership is split so W owns the colours and the user owns everything else:

| File | Owner | What is in it |
|---|---|---|
| `~/.config/git/config` | **W** (`managed` — overwritten on every install/update) | `[include]` of the theme file, `delta` as `core.pager`/`interactive.diffFilter`, `[delta] features = w`, plus sane defaults (`merge.conflictStyle = zdiff3`, `diff.algorithm = histogram`, `init.defaultBranch = main`) |
| `~/.gitconfig` | **the user** (stub, seeded once) | nothing by default — the user's own settings go here |
| `~/.config/w/git-theme.conf` | **W** (axis `500-git`) | the `[delta "w"]` feature block + `[color "diff"/"status"/"branch"/"decorate"/"grep"/…]` |
| `~/.config/lazygit/config.yml` | **the user** (seeded once) | behaviour only — `git.paging` pointing at delta |
| `~/.config/w/lazygit-theme.yml` | **W** (axis `500-lazygit`) | `gui.theme` colours |
| `/etc/w/env.d/dev.sh` | **W** (managed) | `LG_CONFIG_FILE` merging the two lazygit files |

**Why git is split this way — it is the model to reach for elsewhere.** Git reads
both global files, `~/.config/git/config` then `~/.gitconfig`, and the later one
wins. So W keeps its settings in a file it fully owns and can change on any update,
while the user's file overrides W key by key and is never written to by W. Nothing
here needs a manual merge when W ships a new git default. When a tool offers that
kind of layering (lazygit's `LG_CONFIG_FILE` does too), prefer it over seeding into
a file the user owns.

- **git is live.** git re-reads its config on every invocation, so `w-theme set` is
  visible in the very next `git diff` — nothing to restart or re-login.
- **lazygit is not live**, and its colours ride the session env, so they appear at
  the **next login** after the bundle is installed.
- `delta` decides dark-vs-light from the `dark`/`light` key W renders out of the
  theme's `W_APPEARANCE` — never tell the user to add `--dark`/`--light` by hand.

## What the user has — mise (runtime versions)

`mise` replaces nvm / pyenv / rbenv / gvm / sdkman / asdf with one binary, and also
covers per-directory env vars, so **direnv is not installed and is not needed**.

**The ownership line — get this right before answering any version question:**

| Language | Managed by | Never suggest |
|---|---|---|
| **Python** | **`uv`** — venvs, pinned interpreters (`uv python install X.Y`), global CLIs (`uv tool install`) | `mise use python`, pyenv, pipx, or a bare `pip install` outside a venv (Arch marks `python` PEP 668) |
| node, go, rust, java, deno, bun, … | **`mise`** (`mise use -g node@lts`, or `mise use node@22` in a project) | nvm, `pacman -S nodejs` for project work |
| the system itself | **pacman / `w-update`** | `mise` — it manages dev tools, not system packages or libraries |

Go, whichever way it is installed, keeps its caches in `~/.cache/go` and its binaries in
`~/.local/bin` — there is no `~/go` on W (base policy, `/etc/profile.d/w-go.sh`; the
`w-software` skill has the details).

The two cooperate rather than collide: `python.uv_venv_auto = "source"` in
`~/.config/mise/config.toml` makes mise activate the `.venv` that **uv** already
manages when a `uv.lock` is present. Idiomatic version files are off by default, so
mise does not fight uv over `.python-version`.

**Activation is two-channel, and both are deliberate:**

| Channel | File | Covers | Active from |
|---|---|---|---|
| `mise activate zsh` (per-prompt PATH) | `/etc/w/zshrc.d/dev.zsh` | interactive shells | the next new shell |
| shims on `PATH` | `/etc/w/env.d/dev.sh` | GUI apps + non-interactive | the next login |

The shim half is what makes **Zed and its language servers** see the project's
toolchain: Zed starts from the Hyprland launcher and never reads `.zshrc`.

**Two node binaries exist on this machine, by design.** `nodejs` rides in as a
dependency of the `zed` package (system-wide, pacman's), and mise installs its own
per project. Inside a project with a mise-pinned node, `which node` resolves to
mise's; elsewhere it is the system one. That is working as intended — do not
"fix" it by removing either.

## Typical operations

| Goal | Do this |
|---|---|
| Open a project | `zed <path>` (or `zed .`) |
| Re-theme after a theme switch | automatic. Zed and git are live; lazygit shows it on its next start |
| Force a theme re-render | `w-style apply zed` / `apply git` / `apply lazygit` (as the user, no sudo) |
| Restore W's default settings | delete/edit `~/.config/zed/settings.json` (or `~/.gitconfig`, or `~/.config/lazygit/config.yml`), then `sudo w-pack install dev` re-seeds it — a re-install never overwrites an existing file |
| Set the git identity | `git config --global user.name "…"` / `user.email "…"` — W cannot know these and deliberately leaves them unset |
| Pin a runtime for a project | `cd <project> && mise use node@22` (writes `mise.toml`) |
| Set a global default runtime | `mise use -g node@lts` |
| Install what a project declares | `mise install` (reads `mise.toml` / `.tool-versions`) |
| See what is active and why | `mise ls` / `mise current` / `mise doctor` |
| Update mise itself | `w-update` — **not** `mise self-update` (disabled in the Arch build) |
| Check the bundle | `w-pack status dev` |
| Language servers | Zed installs them on demand (nodejs/npm ride in with the package). QML needs `qmlls` from Qt on `$PATH` |

## Gotchas

- **`zed` vs `zeditor`** — see above. Never tell the user to `pacman -S zed-editor`;
  the package is `zed`, provided by `extra`.
- **The theme files are not the user's.** Edits to `~/.config/zed/themes/w.json`,
  `~/.config/w/git-theme.conf` or `~/.config/w/lazygit-theme.yml` are lost on the
  next theme render. Colour changes belong in the active theme's `theme.conf` (see
  the w-theming skill); the per-tool mapping lives in the bundle's axes
  `wstyle/400-zed`, `wstyle/500-git`, `wstyle/500-lazygit`.
- **Seeded files are the user's.** Never suggest rewriting `settings.json`,
  `~/.gitconfig` or lazygit's `config.yml` wholesale — patch the individual key.
- **`~/.config/git/config` is W's, and installing the bundle overwrites it.** A user
  who kept their own git config at that XDG path loses it. Tell them to move such a
  file to `~/.gitconfig` *before* installing `dev` — same semantics as every other
  `managed` file in W, but this one has a plausible pre-existing occupant.
- **Legacy layout (bundles installed before 2026-08-04)** seeded W's git settings
  into `~/.gitconfig` itself. Those machines still work — identical values, and the
  user's file wins — but the stale lines freeze W's settings and block future
  changes. `setup.sh` detects and reports it; the fix is to delete W's old
  `[include]`/`[core]`/`[interactive]`/`[delta]` blocks from `~/.gitconfig` while
  keeping everything the user wrote.
- **Hex colours in a git config must be quoted** — `#` starts a comment otherwise.
  This bites anyone hand-editing diff colours.
- **`LG_CONFIG_FILE` is session env**, so lazygit is unthemed over a bare SSH login
  (or in any shell outside the graphical session). That is expected, not a bug —
  lazygit still reads the user's own config and works normally.
- **mise does nothing until the user asks for a tool.** A fresh install pins
  nothing; `mise ls` being empty is not a fault.
- **mise needs a relogin after the bundle is installed** — both activation channels
  are session/shell scoped. If `mise` works but `node` still resolves to the system
  binary inside a project, the first thing to check is whether the user has logged
  in again since installing, then `mise doctor`.
- **mise's storage lives outside @home snapshots** by design: `~/.cache/mise` and
  `~/.local/share/mise` are nested btrfs subvolumes (snapper's snapshots are
  non-recursive), because toolchains are large and fully re-downloadable with
  `mise install`. A rollback of `@home` therefore does not roll back installed
  toolchains — expected, same as the uv/pip caches and rootless container storage.
- **mise prompts to trust a project's `mise.toml`** the first time it sees one.
  That is upstream's security model, not a W setting; `mise trust` accepts.
- **Wayland/GPU:** Zed needs a working Vulkan driver (`vulkan-intel` /
  `vulkan-radeon` / NVIDIA, installed by `apply.sh --gpu`). Upstream has had
  recurring GPUI-on-Wayland CPU regressions; if the user reports Hyprland or Zed
  burning CPU while typing, check that `show_edit_predictions` is `false` and report
  the Zed version — this is an upstream issue, not a W misconfiguration.
- **No file-type takeover.** W does not make Zed the default handler for text/code
  MIME types; `~/.config/mimeapps.list` stays owned by the base `files` module.
- **Updates** come through `w-update` like any other package; Zed's own updater is
  deliberately disabled.
