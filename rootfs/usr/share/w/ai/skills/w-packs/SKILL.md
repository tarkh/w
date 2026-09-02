---
name: w-packs
description: >-
  Optional software bundles (W-Packs) — opt-in add-ons by direction (containers,
  dev, gaming, …) installed on top of the base system with `w-pack`. Load this when
  the user wants to see, install, or reason about optional bundles. Operating an
  already-installed bundle is covered by that bundle's own skill (skills/<bundle>).
sources:
  - path: .claude/library/packs.md
    sha256: 4b3bcff0bbd9c57d0dee82df23a841c214ba4b8a91fbf690f29e48a571e90347
tools:
  - w_pack_list
  - w_pack_status
  - w_pack_install
---

# W-Packs

W installs in two layers. The **base** (`apply.sh`) is must-have — the session,
theme, shell, security — and is always present. **W-Packs** are the second layer:
**opt-in bundles by direction** that not everyone needs.

- A bundle is named by *direction*, not by tool: `containers` (not `podman`),
  `gaming` (not `steam`). The user picks a capability; the engine is an
  implementation detail.
- A bundle is **self-contained**: one directory under `/usr/share/w/packs/<bundle>/`
  carries everything it needs — packages, config, its w-style theme axis, its AI
  knowledge, and a setup step. Installing it wires all of that up; the base system
  carries zero references to bundle software.

## The `w-pack` command

```
w-pack list                  # available bundles + state (add --porcelain to parse)
w-pack status [<bundle>]     # what is installed (all, or one bundle)
sudo w-pack install <bundle> # install: packages + config + w-style + setup
w-pack setup <bundle>        # set an installed bundle up for MY account (no sudo)
sudo w-pack refresh [<b>]    # re-apply INSTALLED bundles, no package operations
```

- **`install` needs root** (it installs packages and touches system paths) and is
  **idempotent** — re-running re-applies safely. Heavy bundles (AUR builds) take a
  while. Dependencies between bundles are resolved automatically.
- There is **no `remove`** yet — it is a later, deliberately conservative phase
  (shared pacman deps make automatic removal risky). To revert a bundle's *config*
  to the W default, use `w-reset <bundle>` — it restores from the bundle's own
  staged tree, backing up the current copies first, and needs no root for your own
  home.
- Bundles are also offered at install time (the TUI bundle checklist) and installed
  on first boot — so a fresh machine can arrive with the chosen bundles ready.
  **Exception:** a bundle can set `INSTALLER=off` in its `meta.conf` to hide itself
  from that TUI checklist only — everywhere else (`w-pack list/install/status`,
  this skill, the Hub) it is a normal bundle. Used for bundles that only make sense
  from an already-running system (e.g. `ai-extra`, an advanced local-AI stack) —
  never suggest installing one of these during the OS install flow itself.

## Two layers: the machine's and yours

A bundle is installed **once per machine** but used **per account**, so it has two
halves and each has its own state:

| Layer | What | State | Who |
|---|---|---|---|
| Machine | packages, system config, services, theme axes | `/var/lib/w/packs.json` | root, once |
| Per-user | the bundle's tools and config in a home (e.g. `ddgs` in `~/.local/bin`) | `~/.local/state/w/packs.json` | that account, rootless |

So on a machine with several accounts there are **three** states, not two, and
`w-pack list` names them:

```
[installed]  ready for you
[machine  ]  on this machine, but NOT set up for your account  ->  w-pack setup <b>
[         ]  not on this machine                               ->  sudo w-pack install <b>
```

`w-pack list --porcelain` gives the same thing as
`<name> TAB <machine:yes|no> TAB <user:yes|no|n/a> TAB <description>`; `n/a` means
the bundle has no per-user layer at all, so nothing needs setting up for anyone.

**This matters when answering "is X installed?"** — machine-wide "yes" does not mean
the person asking has the bundle's user-side tools. Read the per-user column before
answering, and if it says no, the fix is one un-privileged command:

```
w-pack setup <bundle>      # no sudo, no polkit — it writes only your own home
```

A bundle someone else installed is deliberately **not** set up for everyone
automatically: that would spend a person's disk and network on a choice they never
made. Nothing is broken when you see `[machine]` — it is an honest "not yet".

If the bundle is not on the machine at all, its machine half needs an administrator
(`sudo w-pack install <bundle>`). Say so plainly rather than suggesting workarounds;
a non-admin cannot install packages, and `w-pack` will tell them the same thing.

## Operating an installed bundle

When a bundle is installed, its knowledge is **curated into this knowledge base as
its own skill** (`skills/<bundle>/SKILL.md`) — for example `skills/containers`. That
skill is the single source of truth for how to *use* the bundle (its CLIs, common
operations, gotchas, reset).

There are **no dedicated per-bundle MCP tools** by design. Operate a bundle with its
documented commands through your normal shell — rootless, user-scope operations
(e.g. `docker ps`, `podman logs`, `systemctl --user start …`) need no privilege and
no special tool. Reach for a privileged W tool only when the operation genuinely
needs root.

## MCP tools

When `w-mcp` is connected:

- `w_pack_list` — bundles available on this machine, each with its machine state
  **and** whether it is set up for the invoking account. *Read.*
- `w_pack_status` — install state (all, or one bundle), including the per-account
  line. *Read.*
- `w_pack_install` — install a bundle. **Privileged** — goes through W's polkit
  prompt and is audited, like every Tier-2 action. It can be switched off in
  `ai.conf` (`W_AI_TOOL_PACKS`); if disabled, tell the user which switch to flip
  rather than working around it.

There is deliberately **no MCP tool for `w-pack setup`**: it is rootless and touches
only the caller's own home, so it needs no OS-enforced privilege — run it through
your normal shell, the same way you would any other user-scope command.

**`refresh` vs `install` vs `setup`.** `refresh` re-applies what an already-installed
bundle owns — its config files, w-style axis, AI skill and its idempotent setup —
from the currently staged tree, and deliberately does **not** touch packages, so it
works offline and finishes in seconds. It also replays the per-user layer for every
account that already has it, and only those. An edge update runs it automatically
when the pull changed the bundle tree (`w-sync update` → `w-pack refresh`), which is
how a fix to a bundle's setup reaches machines that installed it months ago. Use
`refresh` when a bundle's config or theme looks stale for people who already have it;
use `setup` to bring **a new account** onto an installed bundle; use `install` only to
add a bundle to the machine or to deliberately re-pull its packages.

Prefer the read tools (or `w-pack list`/`status`) to ground answers in what is
actually installed before suggesting anything.

## Rules

- **Confirm before installing.** `w_pack_install` pulls packages and changes the
  system — state what the bundle adds and why, then let the user approve the polkit
  prompt. Never try to bypass that prompt.
- **Bundle first, not tool.** If the user wants a capability W packages as a bundle,
  install the bundle rather than hand-picking individual packages — the bundle
  carries W's curated config and theming for that direction.
- **Check the per-account column before saying "it's installed".** A bundle can be
  on the machine and absent from the asking user's home; that is a real, expected
  state with a one-command fix (`w-pack setup <bundle>`), not a fault to debug.
- **Never suggest `sudo` for `setup`.** It writes only the caller's own home; running
  it as root would target the wrong account.
- **Load the bundle's own skill** for operating details; keep this skill for the
  framework (list/install/setup/status) only.
