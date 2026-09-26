---
name: gaming
description: >-
  Operating the `gaming` W-Pack: Steam, Lutris and Heroic launchers, Proton/Wine
  tooling, the MangoHud overlay, gamescope, gamemode and its bridge into
  w-power, and the ntsync kernel module. Load this when the user asks about
  playing games on W, Steam/Proton/Lutris/Heroic, game performance (FPS
  overlay, CPU governor while gaming), a game that won't start, controllers,
  Heroic's colours, or where games are installed and how to put them on a
  second disk — and `w-pack status gaming` reports installed.
---

# W-Pack: gaming

Steam, Lutris and Heroic side by side on one shared Proton/Wine/MangoHud/gamemode
machine layer. A product bundle (`INSTALLER=on`, offered in the TUI checklist and
`w-pack list`), not an advanced/opt-in one like `comfyui`.

## What the user has

- **Three launchers, one machine layer.** Steam covers most of a typical library
  and is installed with `umu-launcher`, the compatibility layer Steam's own
  tooling and both Lutris and Heroic delegate Proton launches through — one
  Proton resolution path, not three divergent ones. Lutris is the official
  catch-all for everything else (GOG/Amazon/native installers/emulation) via
  community install-scripts. Heroic talks to Epic/GOG's native APIs directly
  (Lutris's own Epic script is fragile against Epic's API changes).
- **Proton tooling**: ProtonPlus (GTK4 GUI) installs/manages GE-Proton and other
  compatibility tools on top of the Steam-shipped Proton versions; protontricks
  resolves the right Proton prefix for a Steam AppID and runs winetricks against
  it — the fix for the "one DLL/font a game needs" class of problem GE-Proton
  alone doesn't cover. A system Wine + winetricks + vkd3d is also installed —
  not what games run under (that's Proton, per-title, from Steam) but what
  Lutris's non-Steam installers and winetricks itself need.
- **NTSYNC is on** — `ntsync-autoload` loads the kernel's own NT-synchronization
  module at boot (built into `linux`/`linux-zen`/`linux-lts`; only the autoload
  wiring is the package). This is the single biggest real-world Proton/Wine
  performance win of the last few years — check it landed: `ls /dev/ntsync`.
  If it's missing after a `w-pack install gaming` on an already-booted machine,
  `modprobe ntsync` (setup.sh already tries this once); a genuinely absent
  module means an unsupported kernel.
- **Game library lives outside `@home` snapshots.** `~/.local/share/Steam`
  (library, `compatdata/` Proton prefixes, shader cache), `~/Games` (Lutris +
  Heroic installs) and `~/.local/share/lutris` (Lutris's own Wine/Proton
  runners) are nested btrfs subvolumes, carved out on `w-pack setup gaming` —
  snapper's `@home` timeline is non-recursive, so their contents never ride a
  home snapshot. This only happens while the path is absent: a Steam that
  already ran before the pack's user layer landed keeps its plain directory
  (warned about, not converted). `~/.steam` (symlinks) and `~/.config/heroic`
  (small config) are ordinary and stay inside snapshots.
- **Heroic wears W's colours.** A `w-style` axis (`400-heroic`) renders the
  active theme into `~/.config/heroic/themes/w.css` as a Heroic *custom theme*,
  and the pack's user layer selects it once (`customThemesPath` in
  `~/.config/heroic/config.json`, `theme: "w.css"` in
  `~/.config/heroic/store/config.json`) — so even a Heroic that has never run
  opens in W's palette. **Never edit `w.css` by hand**: it is regenerated on
  every `w-theme set`/`w-style apply`. Heroic reads it only at startup (no file
  watcher), so a theme switch shows up at Heroic's **next launch**, not live.
  The user is free to pick a different theme in Settings → General → Select
  Theme; the pack never overrides a choice already made, and `w.css` simply
  stays in the dropdown.
  Steam and Lutris get no such treatment — Steam paints its UI from a 5 MB
  bundle of hard-coded colours with no design tokens to override (a palette
  swap there means adopting a whole third-party skin), and Lutris is GTK, so it
  already follows W through the `gtk` axis.
- **MangoHud** — FPS/frametime/GPU/CPU/VRAM/RAM overlay. Toggle in-game:
  `Shift_F12`. Its colours come from the active W theme (a `w-style` axis,
  `400-mangohud`) — **never edit `~/.config/MangoHud/MangoHud.conf` by hand**,
  it is regenerated on every `w-theme set`/`w-style apply`; change the theme
  instead. Not live inside a running game — a theme switch mid-session
  recolours the *next* launch.
- **gamemode, bridged into `w-power`.** `gamemoded` bumps process priority
  (renice/ioprio — only for accounts in the `gamemode` group, added by the
  pack's user layer, effective at the next login) while a game runs. Its
  `[custom]` start/end hooks call `/usr/lib/w/w-gamemode-hook`, which saves the
  current `w-power` profile and auto-switch state, forces `performance` with
  auto-switch suspended for the duration, and restores exactly what it saved
  when the game exits. Runs as the user (gamemoded is a per-session daemon),
  so no polkit prompt appears. `gamemode.ini`'s `inhibit_screensaver=1` and
  `disable_splitlock=1` are the upstream defaults, kept explicit on purpose —
  this is why W does not also ship the `vm.max_map_count`/
  `kernel.split_lock_mitigate` sysctl tweaks some guides recommend (Arch's
  `vm.max_map_count` default is already high enough; the kernel's
  `disable_splitlock=1` default already matches, and gamemode's own knob covers
  the rest).
- **gamescope, installed, not forced.** Valve's micro-compositor — a nested
  Wayland session for games that specifically need it: HDR, FSR/upscaling,
  a hard frame-rate limit, or input isolation. Set as a Steam launch option per
  game, e.g. `gamescope -W 2560 -H 1440 -r 144 -- %command%`; not a default for
  every game.
- **`scx_lavd` installed but NOT enabled** — a game-tuned `sched_ext` CPU
  scheduler (package `scx-scheds`). W does not switch the machine's scheduler
  on install; a global, session-wide change isn't something a pack should force
  on everyone. Try it: `sudo systemctl start scx_lavd`; stop:
  `sudo systemctl stop scx_lavd`.
- **multilib is enabled by this pack's `pre.sh`** (before packages — Steam and
  the 32-bit driver stack live in that repository, off by default on Arch) and
  **stays enabled on `w-pack remove`** — other software or the user's own
  32-bit packages may depend on it; the pack only ever adds, never removes a
  shared system-wide repository. The GPU-vendor lib32 packages (mesa/vulkan/
  nvidia-utils, matched to the machine via `w-gpu-lib.sh`) are also installed
  by `pre.sh`, marked `--asdeps` so they get swept up automatically if the pack
  is later removed with `--packages`.
- **Firewall**: `pre.sh`'s sibling `setup.sh` opens Steam Remote Play
  (`steam-streaming`) and local peer-to-peer game transfer
  (`steam-lan-transfer`) in the firewalld `home` zone only — never `public`.

## Games on a second disk

A dedicated games SSD is common, and W deliberately has **no single knob** for
it: each launcher owns a first-class, discoverable setting for exactly this, and
a W-level override would still have to send the user into Steam's own dialog for
the one case it cannot express. Point each launcher you actually use at the
drive — once, and it stays:

- **Steam** — Settings → Storage → the drive dropdown → **+** → pick the mount
  point. Steam creates its own `steamapps/` there and from then on offers the
  drive at install time; the selected drive is also the default for new
  installs. Moving games already installed: right-click the game → Properties →
  Installed Files → **Move install folder**.
- **Heroic** — Settings → General → **Default Installation Path**, and the
  setting right below it, **Set Folder for new Wine Prefixes**. Move both or
  prefixes keep landing in `~/Games/Heroic/Prefixes` while the games move away.
- **Lutris** — Preferences → Global options → **Default installation folder**
  (stored as `game_path` in `~/.config/lutris/system.yml`).

Two things to tell the user up front:

- **The filesystem matters.** Proton needs POSIX permissions, symlinks and
  case-sensitive paths: ext4/btrfs/xfs are fine, **NTFS and exFAT are not** and
  produce exactly the "disk write failure"/game-won't-launch class of bug below.
  A drive shared with Windows is the usual trap.
- **Snapshot exclusion doesn't follow.** The nested-subvolume carve-out above
  only concerns `@home`; a second disk is outside it to begin with, so there is
  nothing to exclude and nothing to worry about. The paths in `$HOME` stay as
  they are — Steam's client, Heroic's config and Lutris's runners are small and
  belong there.

## Anti-cheat reality — set expectations up front

**Kernel-level anti-cheat (Riot Vanguard, BattlEye/EAC in their kernel-driver
mode) does not work on Linux and this pack cannot change that.** Don't promise
a workaround. Games using *user-space* EAC/BattlEye (most single-player and many
multiplayer titles) generally work fine through Proton — check
[ProtonDB](https://www.protondb.com/) for the specific title before assuming
either way.

## Common operations

- Check what launched: `w-pack status gaming`.
- Proton version for a specific game: Steam → game Properties → Compatibility.
  Proton Experimental is Steam's own rolling default; for a game that needs a
  specific GE-Proton build, install it with ProtonPlus first, then select it
  the same way. Launch options go in the same Properties dialog
  (`LAUNCH_OPTIONS %command%`).
- Force the FPS overlay if it isn't showing: confirm the launch options include
  `mangohud %command%` (Steam does this automatically once MangoHud is
  installed, but a non-Steam/Lutris/Heroic launch needs it explicit).
- Re-render Heroic's palette without waiting for a theme switch:
  `w-style apply heroic` (as the user, no sudo), then restart Heroic.
- Take Heroic off W's palette without removing the pack: Settings → General →
  Select Theme → any other entry. The pack will not put it back — it only ever
  seeds a choice that has not been made.
- Xbox controller over Bluetooth with rumble: **not in this pack's core** —
  needs `xpadneo-dkms` from the AUR, a deliberate omission (see rejected list
  below). Wired/2.4 GHz controllers and `steam-devices` (Steam's own hard-dep,
  ships with the client) already work.

## Troubleshooting

- **A game won't start** — check in this order: `journalctl` for the launcher
  itself (`journalctl --user -u gamemoded` if it's a priority/renice issue);
  ProtonDB for the title's known Proton version and launch-option
  workarounds; whether the title needs a component protontricks/winetricks
  can install (`.NET`, `VC++ redist`); whether it's a kernel-anti-cheat title
  (see above — no fix exists).
- **No sound in a game** — almost always a PipeWire/Proton audio backend
  mismatch, not this pack; see the `w-audio` skill for the general audio
  troubleshooting path first.
- **Heroic opens in its stock colours** — check in this order:
  `ls ~/.config/heroic/themes/w.css` (missing → `w-style apply heroic`);
  `theme` in `~/.config/heroic/store/config.json` (must be `"w.css"`);
  `customThemesPath` in `~/.config/heroic/config.json` (must be the `themes`
  directory above). `w-pack setup gaming` fixes all three, but **only while
  Heroic is closed** — it refuses to touch a running instance, because Heroic
  rewrites its config on every settings change. If the user picked another
  theme themselves, that is respected on purpose and nothing is wrong.
- **Heroic did not change colour after `w-theme set`** — expected: it reads the
  stylesheet only at startup. Restart Heroic.
- **Steam's file picker can't see a disk/drive** — that's the portal file
  chooser (`xdg-desktop-portal`), not Steam; the drive needs to be mounted and
  visible to the portal, not just to a file manager run as another user.
- **"Disk write failure" installing to a library on a drive shared with
  Windows** — almost always an NTFS/exFAT permissions or free-space issue on
  that filesystem, not a W/Steam bug; check the mount options and free space
  on that specific volume.

## Reset / remove

- `sudo w-pack remove gaming` closes the firewalld services, removes the
  gamemode bridge/window rules/MangoHud and Heroic axes, puts Heroic back on
  its own default theme (the `theme` key is deleted, not overwritten — and only
  if it is still W's) and deletes the rendered `w.css`, and removes the account
  from the `gamemode` group for every account that had the pack set up.
  Reverting Heroic is not cosmetic tidiness: its `<body>` class comes from the
  selected file name, so leaving `w.css` selected with the file gone would
  leave a half-painted window. **multilib
  stays enabled** and **ntsync stays loaded** — printed explicitly, since
  turning either off could break something the pack never touched. **The game
  library, Proton prefixes and Lutris/Heroic installs are never deleted** —
  `w-pack remove` prints their paths and sizes; delete them yourself
  (`btrfs subvolume delete <path>`) if truly unwanted. `--packages` removes
  the pack's own package list plus the vendor lib32 stack `pre.sh` installed
  (swept up automatically, `--asdeps`).
- `w-reset gaming` restores `gamemode.ini`, the gamemode↔w-power bridge script
  and the Hyprland window rules from the pack's shipped copies — does not touch
  MangoHud's or Heroic's rendered config (that's `w-style`'s territory: change
  the theme, or `w-style apply` to re-render them).
