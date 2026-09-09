---
name: flatpak
description: >-
  Sandboxed third-party GUI apps on W Linux with the `flatpak` W-Pack: Flathub, the
  Bazaar store, Flatseal permissions, and how W's theme reaches inside the sandbox.
  Load this when the user installs, runs, themes or debugs a Flatpak app, or asks how
  to get software that is not in the Arch repos, and `w-pack status flatpak` reports
  installed.
---

# W-Pack: flatpak

Sandboxed third-party GUI applications. This bundle installs **Flatpak** with the
**Flathub** remote, the **Bazaar** store (native GTK4 app, not a Flatpak), **Flatseal**
(per-app permissions), and wires W's theme into the sandbox. Curated into
`/usr/share/w/ai/skills/flatpak/` when the bundle is installed. Present only if
`w-pack status flatpak` reports installed.

Not installed? `sudo w-pack install flatpak`. Until then the machine has no Flatpak at
all — suggest a repo/AUR package (see the `w-software` skill) or offer to install this
bundle.

## Where Flatpak fits

W's rule of thumb: **pacman/yay for the base system, W's components and trusted CLI
tools; Flatpak for untrusted or third-party GUI apps**, which run sandboxed
(bubblewrap + xdg-desktop-portals). Snap and AppImage are deliberately not used.

## Common operations

| Task | Command |
|---|---|
| Browse / install with a GUI | **Bazaar** (the store) |
| Install from the CLI | `flatpak install flathub <app-id>` |
| List / run / remove | `flatpak list`, `flatpak run <app-id>`, `flatpak uninstall <app-id>` |
| Update the apps | `flatpak update` (own channel — `w-update` does not touch it) |
| Per-app permissions | **Flatseal**, or `flatpak override --user …` |
| Re-apply W's sandbox wiring | `sudo w-pack refresh flatpak` |
| Set the bundle up for another account | `w-pack setup flatpak` (that account, no root) |

## Theming inside the sandbox

W applies its theme to sandboxed apps automatically — colors, icons and fonts for
GTK3/GTK4/Qt. Two facts to state when asked:

- **A theme switch reaches a running app only after restarting it** — Flatpak reads
  theme extensions at app launch and cannot live-reload them.
- **The account matters.** The icon mirror and the GTK3 theme extensions live in a
  home directory, so a second account sees stock icons until it runs
  `w-pack setup flatpak` once.

## Gotchas

- **A per-app USER override shadows W's system one.** If one app's colors, icons or
  font look wrong while others are fine, that is almost always it (Flatseal writes
  these). Diagnose with `flatpak override --user --show <app>`; fix with
  `flatpak override --user --reset <app>`. W only manages `--system` and never
  rewrites a user's per-app choices.
- **A newly installed Qt app may look unstyled.** It can pull a KDE runtime branch
  newer than any installed Kvantum engine extension. `sudo w-pack refresh flatpak`
  fetches the matching one.
- **New apps appear in the launcher after the next login** — Flatpak's exported
  `.desktop` entries arrive via `XDG_DATA_DIRS`, which the session reads at login.
- **`GTK_THEME` must never be set for Flatpak** (even empty — it breaks GTK3/GTK4
  styling). The portal already reports the theme name. Do not add it to an override.

## Reset / remove

- Sandbox wiring back to W's default: `sudo w-pack refresh flatpak` — it resets and
  re-applies the system override declaratively. The bundle owns no config file in a
  home, so `w-reset` has nothing to restore for it.
- Bundle removal is a later phase; `flatpak uninstall <app-id>` removes individual
  apps, and `flatpak uninstall --unused` reclaims orphaned runtimes.
