---
name: localsend
description: >-
  Working with the `localsend` W-Pack on W Linux: LocalSend (an open-source,
  AirDrop-alike file transfer app with official Linux/Windows/macOS/Android/iOS
  clients over one open protocol) — why it needs no bespoke colour axis (it
  reads W's live GTK4 accent once pointed at "system"), the firewalld rule
  letting it through on the LAN, the Nemo "Send with LocalSend" action, and
  why autostart ships off by default. Load for LocalSend, sending files
  between devices, "AirDrop for Linux/Android/iPhone", the Nemo file-transfer
  action, port 53317, or `w-pack status localsend` reports installed.
---

# W-Pack: localsend

A single-app bundle, like `telegram`: LocalSend (`localsend-bin` from AUR — a
repackage of the official prebuilt release, not a from-source build), a
firewalld service, and a Nemo action. W does not ship a "file transfer" bundle
with alternatives inside it: LocalSend is the only option with official apps
on all of the user's actual devices (Linux, Android, **and** iOS)
interoperating over one open protocol — Warpinator has no iOS/Android reach
worth using, KDE Connect's iOS port is comparatively unstable for file
transfer specifically.

## What the bundle actually did

1. Installed `localsend-bin` (~60 MiB, prebuilt — the source AUR package pulls
   a full cargo/clang/cmake/ninja/llvm/fvm toolchain to rebuild the same
   upstream release, no reason to pay that cost).
2. Opened the firewalld service `localsend` (53317/tcp+udp — LocalSend's fixed
   port, used both for UDP-multicast discovery on `224.0.0.167` and the HTTPS
   transfer itself) in the **`home`** zone only. On `public` (`w-firewall
   public`, someone else's Wi-Fi) LocalSend stays unreachable, same as mDNS
   and Samba.
3. Pointed LocalSend at the desktop's own theme (`setup-user.sh` seeds
   `ls_theme`/`ls_color` = `"system"` in its settings) instead of its default
   fixed brand colour — see "How the colour works" below. **No w-style axis
   exists for this pack** — there is nothing to re-render on `w-theme set`.
4. Deployed a Nemo Action, system-wide: right-click any file(s) → **"Send with
   LocalSend"** → opens LocalSend straight on the Send screen with those files
   already selected.
5. Shipped (but did **not** enable) a systemd user unit `localsend.service`
   for running LocalSend hidden in the tray from login — see "Autostart"
   below.

## How the colour works (read this before any "LocalSend doesn't match the theme")

LocalSend has a real dynamic-colour feature (`dynamic_color` Flutter package)
that, when its `ls_color` setting is `"system"`, derives its whole Material 3
palette from the desktop's own accent colour. On Linux that reads GTK4's live
`accent_color` custom CSS property (`~/.config/gtk-4.0/gtk.css`) directly —
**not** the `org.freedesktop.appearance` `accent-color` portal key (confirmed
absent on W: `gdbus call … Settings.Read org.freedesktop.appearance
accent-color` → `NotFound`), and not GNOME's `accent-color` gsetting either
(present but stuck on its schema default `'blue'`, since nothing in W ever
sets it). W already renders that exact GTK4 property from `W_PRIMARY` via the
**core** `200-gtk` w-style module (`@define-color accent_color $W_GTK_ACCENT_BG;`)
— for every GTK4/libadwaita app on the system, not just this one. So this pack
needs **no colour axis of its own**: it only has to flip LocalSend's own
setting from its default (`ls_color: "localsend"`, a fixed brand teal,
confirmed by inspecting a freshly-launched, unconfigured install) to
`"system"`, once, in `setup-user.sh`.

`ls_theme` is the separate light/dark toggle (LocalSend's own name for it
internally is `brightness`) — unrelated to colour, set to `"system"` for
completeness/consistency with the desktop, not because it affects the accent.

Both keys live in the **same JSON file as LocalSend's entire app state**
(Flutter's `shared_preferences` plugin, one flat key/value store):

```
~/.local/share/org.localsend.localsend_app/shared_preferences.json
```

(That path is empirical — confirmed by installing the package and launching it
once on the dev VM. No upstream doc states the Linux path; the app-id
directory name, not the binary name, is what matters if this ever needs
re-verifying against a newer version.)

That same file also holds LocalSend's **self-signed TLS private key and
certificate** (its HTTPS server's identity), receive history, favourites, and
window geometry — none of which W may ever touch. So `setup-user.sh` never
owns this file the way a `write_user_file` w-style axis would own a file: it
reads the existing JSON (if any) and patches exactly the two keys above with
`jq`, once; everything else passes through untouched. If the file does not
exist yet (LocalSend never launched), it seeds just those two keys — LocalSend
fills in its TLS identity and the rest on its own first launch.

**Live, but LocalSend needs a restart to notice.** `200-gtk` re-renders
`gtk.css` on every `w-theme set`/login, so the *signal* updates immediately —
but LocalSend (like most GTK-consuming apps) reads the accent once at start
and caches it. A theme switch while LocalSend is running needs a relaunch to
show the new colour; this is not a bug and not something to chase.

**Do not re-introduce a per-pack colour axis or a `ls_custom_color` seed for
this.** An earlier version of this pack did exactly that (`ls_color: "custom"`
+ a `w-style` axis rendering `W_PRIMARY` into `ls_custom_color` on every theme
switch) — abandoned once `ls_color: "system"` was confirmed to already track
W's live accent with zero bespoke code. The first attempt to verify this
gave a false negative purely from testing methodology: swapping
`~/.config/w/theme/active` without a full `w-style apply`/`w-theme set` left
`gtk.css` stale, so "system" mode appeared to fall back to an unrelated colour
when it was actually just reading last theme's leftover CSS. Always fully
apply a theme switch (not just retarget the symlink) before judging any
GTK-accent-dependent behaviour.

## Autostart — shipped, off by default

`localsend.service` (systemd --user unit, `ExecStart=/usr/bin/localsend
--hidden`) exists on every install but carries no `WantedBy=`, so nothing
enables it automatically — this is a deliberate default, not a bug to fix.
Toggle any time, no reinstall:

```
systemctl --user enable --now localsend.service    # tray at login, always ready to receive
systemctl --user disable --now localsend.service    # back to launch-on-demand
```

Why off by default: `--hidden` start on Linux logged a caught (non-fatal)
`LateInitializationError` from the tray helper on the dev VM (a `Refena` init
ordering race) — the app kept running and serving normally in that test, but
this is exactly the class of upstream rough edge (see also the historical
Linux `--hidden`-breaks-receiving reports in LocalSend's own issue tracker)
that should not be forced on every install without the user asking for the
"always on" behaviour. If a user enables it and reports "receiving randomly
doesn't work", check whether disabling `--hidden` (edit the unit's
`ExecStart=` to drop the flag — LocalSend will then open a normal window at
login instead of staying in the tray) fixes it before assuming something else
is broken.

## What W owns and what it does not

| Path | Owner | Why |
|---|---|---|
| `flutter.ls_theme` / `flutter.ls_color` keys inside `shared_preferences.json` | **W**, `setup-user.sh` (seeded once, not re-rendered — no axis needed) | point at `"system"` instead of LocalSend's own defaults |
| everything else in `shared_preferences.json` (TLS identity, alias, history, favourites, window geometry) | **LocalSend** | its own state — W reads-merges-writes, never replaces |
| `~/.config/gtk-4.0/gtk.css` `accent_color` | **W**, core `200-gtk` w-style module (unrelated to this pack) | the actual live colour signal LocalSend reads |
| `/usr/lib/firewalld/services/localsend.xml`, `/usr/share/nemo/actions/localsend-send.nemo_action`, `/etc/systemd/user/localsend.service` | **W** (manifest, `managed`) | machine-wide, identical for every account |
| whether `localsend.service` is *enabled* | **the user** (never touched by setup-user.sh, only by an explicit `systemctl` the user or this assistant runs on their behalf) | autostart is a real behaviour change, not a config default |

## Typical operations

| Goal | Do this |
|---|---|
| Send a file to a phone/laptop | right-click it in Nemo → "Send with LocalSend" → pick the nearby device (both must be on the same `home`-zone network) |
| Receive on this machine | open LocalSend (or enable the tray unit) → the "Receive" screen is on by default |
| LocalSend's colour doesn't match W | is it running right now? Quit and reopen — it only reads `gtk.css` at start (see above). Still wrong after a restart → check `ls_color` is `"system"`, not reverted to `"localsend"` |
| Check the LAN rule | `firewall-cmd --zone=home --list-services` should list `localsend`; `--zone=public` should NOT |
| Send from a phone to this PC without the home Wi-Fi | not supported by LocalSend (no Bluetooth-triggered ad hoc channel like AirDrop) — both devices must share the same network; if that's ever needed, it is a LocalSend upstream limitation, not something this bundle can work around |
| Update | `w-update` — pacman/AUR owns the package, never suggest the upstream tarball |
| Check the bundle | `w-pack status localsend` |
| Remove | `w-pack remove localsend` — package, firewall rule, Nemo action and unit go; LocalSend's own state directory stays untouched |

## Gotchas

- **The settings file holds a private key.** Never suggest deleting, backing
  up-and-restoring wholesale, or hand-editing
  `shared_preferences.json` outside the `ls_theme`/`ls_color` keys — that file
  is also the server's TLS identity and the account's receive history.
- **The freedesktop `accent-color` portal key is NOT implemented in W** (only
  `color-scheme`, for dark/light, is). Do not assume any other portal-reading
  app will pick up W's accent the way LocalSend does — LocalSend specifically
  reads GTK4's CSS property, which is a different, narrower channel.
- **Nemo Action passes plain paths, not URIs** (`Exec=localsend %F`, not
  `%U`) — confirmed on the dev VM: LocalSend's own argument handling calls
  `Directory.existsSync()` directly on the raw string and throws on a
  `file://` prefix. Do not "fix" this to `%U` to match LocalSend's upstream
  `.desktop` file — that file is wrong for this purpose, tested and reverted.
- **`localsend-bin` renames the binary**: it's `localsend`, not
  `localsend_app` (upstream's own binary name) — the AUR package's `build()`
  step does the `sed` rename. Both the Nemo action and the systemd unit use
  `localsend`.
- **AirDrop-style Bluetooth-then-WiFi-Direct fallback does not exist** in
  LocalSend (nor in any other Linux-compatible tool as of this writing) — it
  is LAN-only. Do not promise "works even off the home network" to the user.
