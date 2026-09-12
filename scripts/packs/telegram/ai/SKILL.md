---
name: telegram
description: >-
  Working with the `telegram` W-Pack on W Linux: Telegram Desktop (tdesktop from
  `extra`) and the W theme axis that renders the active W palette into
  Telegram's own theme format — why a never-started Telegram opens in W's
  colours from the first launch (seeded data), why an account that already ran
  Telegram applies the file ONCE by hand, and why everything after that (theme
  switches, light/dark) is automatic. Load this when the user asks about
  Telegram, its colours or theme, "Telegram does not match the theme",
  messengers on W in general, or `w-pack status telegram` reports installed.
---

# W-Pack: telegram

A single-app bundle, like `bitwarden`: Telegram Desktop from the official
`extra` repo (`telegram-desktop`, Qt6, native Wayland) plus one w-style axis.
W deliberately does not ship a "messengers" bundle — messengers are
alternatives by network (you use the one your contacts use), so bundling
Telegram with Signal or Discord would install what the user did not ask for,
and only Telegram can take W's palette at all (Signal: light/dark only;
Discord: custom themes are client modification, against its ToS).

## What the bundle actually did

1. Installed the `telegram-desktop` package (~136 MiB; the Qt6 stack was
   already there for Quickshell).
2. Deployed the w-style axis `400-telegram` (drop-in root
   `/usr/lib/w/w-style/modules.d/`), which renders the active W theme into
   `~/.local/share/TelegramDesktop/w.tdesktop-theme` — Telegram's own theme
   format (a ZIP: the palette, ~340 keys, plus a flat one-colour chat
   wallpaper), next to its `tdata/`. Rendered for the installing
   account at once (`setup-user.sh`), for every account at each login, into
   `/etc/skel` for future accounts, and on every `w-theme set`.
3. **Seeded Telegram's data for the installing account** — only if Telegram
   had never been started there (`setup-user.sh` → `tdata-seed.py`): a
   `tdata/settingss` naming the W file as the theme for both the day and the
   night slot, plus the theme record itself, in tdesktop's own encrypted
   on-disk format (the settings layer is keyed by a per-account random salt
   and an empty passcode — no secret, so it can be written from outside; the
   real local key `key_datas` is NOT written, tdesktop generates it on first
   start). The same seed turns **"Use Qt window frame" on**, so Telegram
   draws no title bar of its own under Hyprland.

Nothing else: no session env, no window rule, no autostart unit, no manifest
rows. The palette file is the bundle's only artefact in a home outside
`tdata/`, and `tdata/` is touched exactly once, only when it does not exist.

## How it is themed — two states of an account (read this before any look question)

Telegram keeps the theme it uses inside its **encrypted local data**
(`tdata/`) and has no "use this theme file" setting outside the app. Which of
the two states an account is in decides what to tell the user:

- **Telegram had never run when the pack was set up** for this account (the
  normal case: pack chosen at install, or `w-pack setup telegram` before the
  first launch) → the data was seeded and Telegram opens in W's colours **from
  its very first launch, with no click at all**. Nothing to do.
- **Telegram had already run** (a `tdata/` existed — the pack never touches an
  existing one, that is the user's sessions) → applying W's palette is a
  **one-time click**:

  > Settings → Chat settings → Chat background → **Choose from file** →
  > `~/.local/share/TelegramDesktop/w.tdesktop-theme` → **Keep changes**

  This needs a signed-in account: Chat settings (and with it "Choose from
  file") only exist once logged in — the sign-in screen's Settings offers only
  language, scale, the window-frame and system-accent toggles. Do NOT tell the
  user to send the file into a chat and open it (the matugen recipe) —
  "Choose from file" applies a local theme directly.

`w-pack setup telegram` (rootless, or Hub → Packs) prints which state it found.
A user who wants the zero-click path on an account that already ran Telegram
can quit Telegram, move `~/.local/share/TelegramDesktop/tdata` away (that
deletes the signed-in sessions — say so) and run `w-pack setup telegram` again.

After either path everything is automatic (verified in the tdesktop source):

- **Live.** tdesktop keeps a file watcher on the applied theme file and
  re-applies it silently on every change. `w-theme set` recolours a running
  Telegram — no restart, no prompt. The axis writes the file in place (same
  inode) precisely so this watcher stays armed.
- **At start.** tdesktop re-reads the file when it launches and drops its
  cached copy if the content changed — a theme switched while Telegram was
  closed shows up at the next launch.

Until the click (second state only), Telegram still follows W's light/dark
setting through the desktop portal (its "auto-night mode: system" default) on
its own built-in theme — dark, but not W's colours.

### Day/night slots

tdesktop stores the applied theme **per mode** (a day slot and a night slot)
and picks the slot by the system colour scheme. The seed points **both slots**
at the W file, so a seeded account follows W in either mode. A hand-applied
file lands only in the slot active at the time (the night slot on W's dark
themes): should that user run a *light* W theme, the portal flips Telegram to
its day slot — which holds Telegram's built-in Day theme until the same file
is applied once in that mode too. Both slots then point at the same path and
follow every W theme switch.

## Mapping (what the user sees)

| Telegram element | W token |
|---|---|
| window, chat list, compose area | `W_APP_BG`; hover `W_SURFACE_DIM`, menus `W_SURFACE`, raised `W_SURFACE_VARIANT` |
| text / names & bold / secondary | `W_ON_SURFACE` / `W_ON_SURFACE_BRIGHT` / `W_ON_SURFACE_VARIANT` |
| buttons, unread badges, active line, tray counter | `W_PRIMARY` (fill) with `W_ON_PRIMARY` |
| links, service lines, active labels, online status | `W_ON_SURFACE_ACCENT` (accent as ink) |
| **outgoing bubbles** | `W_PRIMARY_CONTAINER` + `W_ON_PRIMARY_CONTAINER` — the W selection pair (active tab, launcher row, terminal selection), not the raw accent |
| incoming bubbles | `W_SURFACE_VARIANT` |
| selected chat row | `W_PRIMARY_CONTAINER` |
| peer names / userpics in groups (8 colours), file thumbnails | the ANSI hue wheel `W_TERM_ANSI_*` — the same roles the terminal and editors use |
| errors, drafts, destructive, close button | `W_DANGER*` |

**Chat wallpaper** is part of the theme: the archive carries a flat tile in
`W_SURFACE_DIM` (one step above the window background), so the chat canvas is a
plain W surface instead of tdesktop's stock pattern — none of Telegram's bundled
wallpapers suit a dark palette and a local theme has no "plain colour" option.
A theme that carries a wallpaper applies it on every Apply, including the live
reload: a wallpaper picked by hand in Chat settings lasts only until the next
theme render (login or `w-theme set`). That is by design — while the pack is
on, W owns Telegram's look; a user who wants their own picture keeps it by
choosing it after the last render, or by removing the pack.

## What W owns and what it does not

| Path | Owner | Why |
|---|---|---|
| `~/.local/share/TelegramDesktop/w.tdesktop-theme` | **W**, axis `400-telegram` (re-rendered on every theme switch/login; deliberately NOT a manifest row) | the palette |
| `~/.local/share/TelegramDesktop/tdata/` | **Telegram** | encrypted sessions, settings, the theme in use — W writes it exactly once, as a seed, and only if it does not exist yet; an existing one is never read or written |
| `~/.config/autostart/telegramdesktop.desktop` | Telegram (its "Launch at startup" toggle) | **dead on W** — there is no XDG-autostart runner; W does not add a unit for a chat client (unlike bitwarden, whose SSH agent must be up) |

## Typical operations

| Goal | Do this |
|---|---|
| Telegram looks like stock Telegram, not W | this account's Telegram ran before the pack was set up, so its data was not seeded — the one-time click above |
| Theme switched, Telegram did not follow | does Telegram use the file? (`ls ~/.local/share/TelegramDesktop/w.tdesktop-theme` exists ≠ in use). Hand-applied on a dark theme and now a light W theme: it moved to the day slot — apply once there too (a seeded account has both slots and is immune) |
| "Use Qt window frame" is off on a fresh account | the seed sets it on; off means the account was not seeded (Telegram had run before) — one toggle in Settings, available on the sign-in screen |
| Force a re-render | `w-style apply telegram` (as the user, no sudo) — normally never needed, `w-theme set` and login do it |
| Back to Telegram's own look | Settings → Chat settings → pick a built-in theme; W's file stays and can be re-applied any time |
| Notifications | native — Telegram sends them over D-Bus to W's notification server; DND via `w-notify` applies |
| Spell-check | dictionaries come from `w-langpack` (`hunspell-<lang>` in `/usr/share/hunspell`); Telegram reads them directly |
| Start with the session | Telegram's own toggle does nothing on W (see above); a user who wants it: `systemd-run --user`-style unit of their own, or open it from the launcher |
| Update | `w-update` — pacman owns the package; never suggest the upstream tarball or the in-app update path |
| Check the bundle | `w-pack status telegram` |
| Remove | `w-pack remove telegram` — the palette file goes; sessions and cache stay; Telegram keeps showing the last applied colours from its cache until a built-in theme is picked |

## Gotchas

- **An existing `tdata/` is never edited.** The seed exists only for a data
  dir that does not exist yet; do not suggest editing, patching or re-seeding
  a live `tdata/` (sessions, MTProto keys) or CLI flags — none of that exists.
  For an account with history the click is the design.
- **A stale palette after remove is not a bug**: with the file gone Telegram
  falls back to its cached copy of the last content. One click in Chat
  settings restores a built-in theme.
- **Two accounts, one machine**: the second account gets the file at its next
  login, and `w-pack setup telegram` (Hub → Packs) seeds its data if it has
  not launched Telegram yet — otherwise its own one-time click.
- **"My chat wallpaper keeps resetting"** — expected: the W theme carries its
  own flat wallpaper and re-applies it at every render. Not a bug; see above.
- **Other messengers**: not curated. Signal (`signal-desktop`), Element
  (`element-desktop`) and Discord (`discord`) are in `extra` and install fine
  with pacman — W does not oppose them, it just has no theme layer for them
  (Signal/Discord follow light/dark only).
