---
name: hyprland
description: >-
  Precise Hyprland configuration (the Lua protocol from 0.55+) via a local copy of
  the official hyprland-wiki. A navigator (MAP.md) finds the one page you need
  without loading the whole wiki into context. Use for any task on Hyprland config,
  hyprctl/IPC, binds, window rules, animations, layouts, and the hypr* ecosystem.
---

# Hyprland Wiki Navigator

## Purpose

This skill gives precise access to the **official hyprland-wiki** through a local copy,
without loading the whole wiki into context. Instead of reading dozens of pages, use the
map (`MAP.md`) to find the one page you need and read only that.

The source of truth is `hyprland-wiki/content/`, **not** model memory: Hyprland changes
fast, and since **0.55 hyprlang is deprecated in favor of a Lua config**
(`hl.config({...})`). Do not rely on old syntax from memory — verify against the wiki.

W's compositor config is Lua (see the `w-desktop` skill), which is exactly the format this
wiki copy documents.

## How the wiki copy is kept fresh

On a W machine this skill's local wiki checkout (`hyprland-wiki/`) and its generated
`MAP.md` are **deployed and periodically refreshed by the system** (the W AI module runs
this skill's `install.sh` — clone/`git pull` + regenerate `MAP.md`). You normally do
**not** run `install.sh` yourself; just read `MAP.md` and pages.

If `MAP.md` or `hyprland-wiki/content/` is missing (the AI module has not run yet, or the
machine has been offline since install), say so rather than guessing syntax from memory.

## Algorithm

### Step 1 — Find the page via the map

Read `MAP.md`. It has two navigation layers:

1. **Page tree** — the tree of all `content/` pages (filenames are self-describing).
2. **Annotated index** — a one-line summary of each section (from its `_index.md`).

Match the task to a section by its summary, then pick the specific page from the tree.
Paths in the map are relative to `hyprland-wiki/content/`.

Quick pointers for common topics:

| Task | Page |
|---|---|
| Config options (`general`, `decoration`, `input`…) | `Configuring/Basics/Variables.md` |
| Key binds | `Configuring/Basics/Binds.md` |
| Dispatchers (actions for binds) | `Configuring/Basics/Dispatchers.md` |
| Window rules | `Configuring/Basics/Window-Rules.md` |
| Workspace rules | `Configuring/Basics/Workspace-Rules.md` |
| Monitors | `Configuring/Basics/Monitors.md` |
| Animations | `Configuring/Advanced and Cool/Animations.md` |
| Environment variables | `Configuring/Advanced and Cool/Environment-variables.md` |
| `hyprctl` | `Configuring/Advanced and Cool/Using-hyprctl.md` |
| Layouts (dwindle/master/…) | `Configuring/Layouts/` |
| IPC / sockets | `IPC/_index.md` |
| Nvidia | `Nvidia/_index.md` |
| hypr* utilities (hypridle, hyprlock, hyprpaper…) | `Hypr Ecosystem/` |
| Plugins | `Plugins/` |

### Step 2 — Read only the chosen page

Open exactly the page you found:

```
hyprland-wiki/content/<path from MAP.md>
```

Read additional pages only if the task truly involves them. Do **not** load a whole
section, let alone the whole wiki.

### Step 3 — Apply with version and W conventions in mind

- **Lua, not hyprlang.** Give config examples in current Lua syntax. Flag old hyprlang
  (`.conf`) syntax as deprecated where it appears.
- **Wiki versioning.** The local copy tracks Hyprland `git latest`. If the user runs a
  tagged release (`hyprctl version`), an option's behavior may differ — note it when
  unsure.
- **W conventions.** Before changing Hyprland config on a W machine, respect how W already
  structures it (the `w-desktop` skill): themed values live in generated `*.lua` fragments,
  autostart uses `hl.on("hyprland.start")` under uwsm, and the dispatch syntax is the new
  Lua form.

## Principles

- **The wiki is the source, not memory.** Verify any claim about Hyprland behavior against
  the local copy.
- **Minimal context.** Map first, then one page. Never load the whole wiki.
- **`MAP.md` is generated.** Do not edit it by hand — the system regenerates it.
