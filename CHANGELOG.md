# Changelog

Every entry here is one published release — one commit on the public branch, one
tag. `scripts/publish.sh` reads the section matching the version being released and
uses it verbatim as the release commit message and the GitHub release notes, so a
missing or empty section fails the release.

Written for the people running W, not for the people writing it: say what changed
for them and what they have to do about it, not which files moved.

## v0.13.1

- **Nothing changes on an installed machine.** This release only fixes the
  project's own nightly build: the check that runs before the ISO is assembled
  needed ImageMagick (v0.13.0's theme-tinted boot logo is verified with it) and
  the build container did not have it, so the first nightly after v0.13.0 stopped
  before building anything. The tool is now installed there. `w-sync` will pick
  this up as a version bump and nothing else.

## v0.13.0

- **Fixed: DNS lookups timing out for 10+ seconds on some networks** — since
  v0.1.0, and until now only on certain Wi-Fi/router combinations (seen on a
  MacBook's Broadcom Wi-Fi behind a home router). W's resolver reaches its
  DNS-over-TLS servers with TCP Fast Open, and on such paths those streams
  complete the handshake and then silently drop every byte; about one in five
  still worked, so the resolver never fell back to plain DNS and every lookup
  simply hung — `pacman` reported *Resolving timed out* on every mirror, and
  app bundles failed to install during first boot. TCP Fast Open is now off
  system-wide (`/etc/sysctl.d/80-w-dns.conf`; nothing else on a W desktop uses
  it client-side, and `w-kernel harden off` leaves it alone). Arrives with
  `w-sync` and takes effect immediately, no reboot. The DNS step now also runs
  a resolve probe after applying the policy and logs a warning if it fails.
  The network guide and the on-box assistant describe the change.
  **New installs additionally:** a failing app bundle at first boot no longer
  cancels the ones after it — the failed ones are listed in the log and retried
  on the next boot as before.

- **The boot logo follows the theme's colour.** A theme without a `logo/` of
  its own inherits W's brand mark and now gets it painted in the theme's accent
  on both the Plymouth splash and the GRUB menu (the primary container colour
  on dark themes, the primary colour itself on light ones, where the container
  is too pale to read on the canvas). The built-in `w` theme renders
  byte-for-byte as before. Themes generated with `w-theme new` from now on
  carry the two new keys (`W_PLYMOUTH_LOGO`, `W_GRUB_LOGO`); a theme you
  generated earlier keeps the plain mark until you rebuild its palette with
  `w-theme edit <name>`. A theme that ships its own `logo/` is untouched. The
  theming guide and the on-box assistant know about it.

## v0.12.0

- **The scratchpad has a button in the bar.** The workspaces block now shows
  Hyprland's special workspace as a glyph button (nf-md-layers, 󰌨) after the
  numbered ones: it lights up while the scratchpad is shown on the focused
  monitor, and a click toggles it — the same as `Super+S`. Until now the
  scratchpad, once anything was sent to it (`Super+Shift+S`), appeared in the
  bar as a raw `special:scratchpad` text button sorted *before* workspace 1,
  and clicking it did nothing useful — since v0.1.0. The glyph is overridable
  like every other block icon: `"icon"` in the `workspaces` block of
  `~/.config/quickshell/w/config/bar.json` (an empty string or a missing key
  keeps the built-in one, so a `bar.json` you already edited needs no change).
  w-session's own parking workspace never shows up there. Arrives with
  `w-sync`; the bar restarts on its own.

## v0.11.0

- **Codex is a full assistant host.** OpenAI's Codex CLI now gets W's layers the
  way Claude Code does — actions (`w-mcp`), identity, and W's knowledge through
  `w-mcp` — as launch flags, so nothing is written into `~/.codex` and a `codex`
  you start yourself in a project of your own stays a plain Codex. Until now
  `w-ai host install codex` only pointed at a README and the W layers had to be
  pasted into `~/.codex/config.toml` by hand. Now:
  ```
  w-ai host install codex     # OpenAI's standalone installer, per-user (~/.local/bin)
  w-ai host login codex       # browser sign-in with your ChatGPT account
  w-ai profile use codex      # or: Hub -> AI -> the codex profile
  ```
  From then on `w-ai`, `w-ai ask` and the `Super+W` palette open Codex. The
  shipped `codex` profile runs on the ChatGPT login and W exports no key; set
  `PROVIDER=openai` in the profile to pay per token against an API key instead
  (`w-ai key set openai`). Codex picks its own model in the session (`/model`);
  a `MODEL=` in the profile pins one. If you had pasted the old
  `[mcp_servers.w-mcp]` block into `~/.codex/config.toml`, it is redundant now
  and harmless either way. The AI guide and the on-box assistant know the new
  commands; `/usr/share/w/ai/hosts/codex/README.md` has the details.

- **Fixed: the installer broke on disks whose model name contains spaces** —
  since v0.1.0. The disk step split its list on whitespace, so a
  `Samsung SSD 970 EVO Plus` either left the wizard spinning behind the previous
  message (it looked like a hang at *Cloning the repository…*) or produced
  shifted, nonsensical entries. The list is built properly now, and empty card
  readers and the live USB you booted from are no longer offered as install
  targets. **New ISO only** — installed systems are not affected by this line.

## v0.10.0

- **New bundle: telegram.** Telegram Desktop from Arch's own repository, with
  the active W theme rendered into Telegram's palette — colours, and a plain
  chat background in the theme's tone — and kept in step when you switch
  themes. On an account that has never launched Telegram the theme is in place
  from the very first start; an account with history applies it once from
  *Chat settings* and Telegram re-reads it on its own after that. A checkbox in
  the installer, or `sudo w-pack install telegram`.

- **Per-app window rules are drop-in files.** W's own live in
  `/usr/share/w/hypr/rules.d/<app>.lua` (the screenshot annotator's rule moved
  there from `hyprland.lua`); yours go in `~/.config/hypr/rules.d/<app>.lua`
  and win over W's for the same app. A broken drop-in shows up in
  `hyprctl configerrors` without taking the others down. Bundles ship rules
  this way and `w-pack` reloads running sessions on install and remove, so a
  rule works at once, not after the next login. **Machines installed before
  this release need one step**: the loader lives in your own `hyprland.lua`,
  which updates do not touch. Once, after `w-sync update`:
  ```
  w-reset hyprland .config/hypr/hyprland.lua && hyprctl reload
  ```
  (a backup is taken automatically). Without it the Bitwarden and
  screenshot-annotator rules below stay inert.

- **Bitwarden pops out as a dialog.** The window the SSH agent raises from the
  tray for every signing request — unlock, approve — now floats centred at
  dialog size instead of wedging itself into the tiling layout. Turn on
  *Close to tray* in its preferences: with the upstream default, `Super+Q`
  quits the app and the SSH agent inside it.

- **Fixed: `~/Pictures` belonged to root.** Since v0.1.0 the install created it
  on the way to `Pictures/Screenshots` as root, so anything else wanting to
  write there — a browser download, a file manager — was refused. The next
  update hands the directory back to you.

- **Fixed: installing or removing `bitwarden` over a root SSH session** ended
  in «could not switch the SSH agent» (it worked from the Hub and `sudo`). The
  bundle's per-account steps now run with the account's own runtime.

- **New ISO:** the installer checklist offers the telegram bundle. Installed
  systems are not affected by this line.

## v0.9.0

- **W speaks Russian.** Choose Russian as the system language and everything W
  draws itself follows: the desktop shell and the login screen, the Hub, every
  notification the W tools send, the W entries in the launcher (searchable in
  Cyrillic), the built-in help of all 36 `w-*` commands, the `w-info` catalog and
  the offline reference in **Hub → System → Documentation** — 36 reference pages
  now exist in Russian next to the guides translated in v0.8.0. What the commands
  print to the terminal stays English, and so do third-party programs that ship
  no translation. Any other language, or `LANG=C`, falls back to English.

- **A language is more than `LANG`: new `w-langpack`.** It knows what a locale
  needs beyond the setting itself — Firefox in that language, a spell-check
  dictionary, translated man pages, a console font that can draw it — and
  installs what is missing (`w-langpack plan`, `sudo w-langpack apply`).
  Switching language with `w-locale set` or in **Hub → Input** sets the font at
  once and offers the packages. The profile also runs on every update, so the
  next `w-sync update` fills in what your current locale is missing.

- **No more empty boxes.** The Noto font family (about 415 MiB: all scripts,
  CJK, colour emoji) is now part of the base system, so a Japanese web page, a
  Telegram emoji or a Hindi filename renders instead of showing tofu — and
  Japanese renders with Japanese glyphs, not Korean ones. Installed machines
  get the fonts on the next update.

- **Fixed: an update could reset the text-console keymap to US.** The keymap
  chosen at install lives in `/etc/vconsole.conf`, and since v0.1.0 every
  update that touched the system files overwrote it with the stock `us`. The
  file is now yours; updates leave it alone. Check with `cat /etc/vconsole.conf`
  and, if it says `us` and you chose something else, set it back with
  `localectl set-keymap <map>`.

- **Bundles can be removed.** `sudo w-pack remove <bundle>` is the declared
  reverse of `install`: it takes W's own wiring out — services, managed config
  (backed up first), theming, AI skill — and leaves the packages unless you add
  `--packages`. Your data is never deleted, and paths that hold any are listed.
  `w-pack unsetup <bundle>` does the same for your own account. Until now
  removing a bundle's packages by hand did not stick: the next `w-sync update`
  put the bundle back — for `ai-extra` that meant the service and a 635 MB
  model. The **Packs** panel in the Hub has a **Remove** button for both; the
  irreversible package half is deliberately terminal-only.

- **New bundle: office.** LibreOffice (with the metric-compatible fonts that
  keep Windows-authored documents laid out as intended), pdfarranger and
  xournalpp for cutting up and annotating PDFs, and Obsidian for notes — the
  first freeware pick in a bundle, fetched by your own pacman from Arch's
  servers, never shipped in the ISO. Obsidian gets the W colour theme as a
  snippet in each of your vaults, switched on unless you have chosen your own
  snippets. A checkbox in the installer, or `sudo w-pack install office`.

- **The Hub asks before it deletes anything.** One confirmation dialog for every
  destructive action — a theme, a layout, a hotkey or profile, an AI profile, a
  bundle — that tells you what actually happens (which theme takes over, that
  keys stay in the keyring) and starts on *Cancel*, so a stray Enter cannot
  confirm. The notification history is grouped by day.

- **`w-term --hold -e <command>`** keeps the terminal window open after the
  command finishes and asks before closing — for commands whose output is the
  point. `w-locale list --names` prints each language's own name and country;
  the Hub language picker shows them.

- **Fixed: reference pages.** Every page's subtitle ended in a double full stop
  since the reference appeared; the `w-session` summary was cut off at a comma
  in the catalog and the docs; the `w-style` page was missing the second half
  of its help, examples included.

- **`ll` and `la` no longer print a header row.** In `eza` that `-h` is
  `--header`, not human-readable sizes, and the header was the one English line
  left in a listing on a translated system. Existing `~/.zshrc` files are
  untouched; the change reaches you on a new install or with `w-reset shell`.

- **New ISO:** the language menu shows names in their own script («Русский»,
  not «Russkiy»). Installed systems are not affected.

## v0.8.0

- **The documentation now covers every Hub panel — and speaks Russian.** Six new
  guides join the four already shipped: displays, input, network, power, AI and
  packs, ten in total. The **?** in a Hub tab header opens the matching page from
  twelve places now instead of two, including tabs that had no way in at all —
  **System → Security**, and **System → Rollback**, which opens the recovery page.
  The whole tree — start page, FAQ and all ten guides — is translated into Russian
  and appears on its own when the system language is Russian. The per-command
  reference stays English: it is generated from the commands' own help text. The
  project README links into the tree too, so the docs are readable on GitHub
  without installing W.

- **Fixed: on a Russian system the documentation would not open at all.** Every
  page is looked up in your language first and falls back to English. Since
  v0.7.0, where that fallback arrived, a race in the file loader killed the retry,
  so a non-English system got an empty viewer and nothing else. It falls back
  correctly now — and there is a Russian tree for it to find.

- **The documentation reads better.** Rewritten renderer: real spacing between
  paragraphs and lists, themed links, commands set off from the prose, and code
  shown on its own block with shell highlighting. You can select the text with the
  mouse and copy it with Ctrl+C, and scroll a page from the keyboard.
  **Documentation** in **Hub → System** is no longer stepped over when you move
  through the Hub with the arrow keys.

- **Flatpak is no longer installed with the base system.** It is a second software
  ecosystem with its own runtimes and store, and a machine that takes its software
  from the repositories never needs it — so it is now an optional bundle:
  Flatpak + Flathub, the Bazaar store, Flatseal, and the W theme carried into the
  sandbox. New installs get it as an unchecked box in the installer, or later with
  `sudo w-pack install flatpak`.

  **On machines already running W nothing is removed** — Flatpak stays installed
  and keeps working. If you use it, run `sudo w-pack install flatpak` once to put
  it under bundle management; after that `sudo w-pack refresh flatpak` tops up the
  sandbox theming that a system update used to do on its own.

- **Fixed: four reference pages showed escaping the commands never print.** The
  pages for `w-ai`, `w-mirrors`, `w-pack` and `w-theme` carried stray backslashes
  in front of quoted command names.

- **Fixed: the FAQ named a command that does not exist.** Recovering from a black
  screen is `w-monitor reset --all`, not `w-monitor reset all`.

- **Fixed: a selective update could run its steps out of order.** The module list
  `w-sync` used had drifted from the one the system applies: eight modules were
  missing from it and got appended at the end, so time settings, power, mirrors
  and five others ran after package installation rather than in their place. It
  never produced a failure. Both lists are now generated from one registry, and a
  check proves they agree.

## v0.7.0

- **W's documentation now ships with the system and opens on the desktop.** Press
  `SUPER + F1`, or pick **Documentation** in **Hub → System**, for a start page, an
  FAQ, four guides (desktop, updates, theming, security) and a reference page for
  every `w-*` command. It lives on disk at `/usr/share/doc/w/`, so it works with no
  network — including the times you need it most. Some Hub tabs now carry a **?** in
  their header that opens straight to the matching page. The reference pages are
  generated from each command's own help text, so they cannot drift from what the
  commands actually do.

- **Rollback has a place in the Hub.** **Hub → System → Rollback** lists your
  snapshots — which one you are running, when each was taken and what it was taken
  for — with a **Restore** button on each. It drives the same `w-rollback` the
  terminal does, so nothing can happen here that could not happen there. Opening the
  tab asks for your password every time: reading the snapshot list is a privileged
  call, and W does not hold that grant open between uses.

- **Fixed: a rollback could fail halfway through on an encrypted install.** `snapper`
  always creates its `.snapshots` as a btrfs subvolume; W keeps its snapshots
  elsewhere and mounts them over that path, so the empty leftover sat nested inside
  the system root. On a rollback, Limine's restore tool moves every subvolume nested
  in the outgoing root — and that one is a live mount point, which the kernel refuses
  to move. The restore stopped at "Moving child subvolumes", left `/var/lib/machines`
  and `/var/lib/portables` in the old system, and the system it kept could not be
  removed afterwards with `snapper delete`. Every encrypted install made so far
  carries the leftover; this update clears it, on existing machines as well as new
  ones. If W reports that it left a non-empty `.snapshots` alone, nothing is wrong —
  it found files there and will not touch them. Unencrypted (GRUB) installs were
  never affected.

- **A rollback no longer finishes on a red error line.** "kernel.default: Read-only
  file system" appeared right after "Restore complete". A rollback registers the
  system it replaces as a snapshot, which makes the running system read-only on the
  spot, so a small bookkeeping write failed — by design, harmlessly, and it was never
  meant to be shown.

- **RECOVERY explains the read-only system after a rollback.** The recovery page that
  ships to disk now says why the machine you are on becomes read-only the moment a
  rollback runs, and that the answer is simply to reboot. Its cleanup instructions
  also no longer list `/.snapshots` among the nested subvolumes — after the fix above,
  it is not one.

## v0.6.1

- **Nothing on your machine changes in this one.** It repairs W's own nightly
  install test, not the system that test installs. The check used to start asking
  questions the moment the freshly installed machine answered on the network — which
  is a second or two before the machine has finished starting up. So it called the
  lock screen "not running" a fraction of a second before it started, and turned a
  perfectly good build red; on another night, with the same code, it would have
  reported a clean system without ever having looked at the end of the boot. It now
  waits for startup to finish before it asserts anything. No file that runs on an
  installed machine was touched, so this update costs you nothing but the version
  number.

## v0.6.0

- **Fingerprints can be enrolled from the desktop.** Until now the authentication
  card and the lock screen could only use a finger enrolled by typing
  `fprintd-enroll` into a terminal. **Hub → Input → Fingerprint** now lists all ten
  slots and adds or removes any of them. There is a CLI behind it — `w-fingerprint`
  (`status`, `enroll <finger>`, `delete <finger>`, `fingers`) — and it is the only
  supported way to talk to the reader; the Hub calls nothing else. Neither needs root
  or a password prompt: fprintd lets you manage your own prints. The tab appears only
  on a machine that has a reader. One thing that surprises people: fprintd answers an
  active desktop session only, so `w-fingerprint status` over SSH reports the reader
  as unavailable (`reason=unauthorized`) while it sits right there — run it from your
  session. The on-box assistant knows the command too.

- **Two 12-hour clock formats in the bar.** The clock cycles through its formats when
  clicked; `hh:mm A` and `hh:mm:ss A` now sit beside `HH:mm` and `HH:mm:ss`. This is a
  default, and `bar.json` is yours once it exists, so the new presets reach new
  installs and newly created accounts only. To take them on a machine you already run
  — this discards your own bar settings:

  ```
  w-reset quickshell config/bar.json
  ```

- **Russian documentation.** README, SECURITY, CONTRIBUTING and RECOVERY now have
  Russian versions under `docs/ru/`, with a language line under the heading of every
  page. English stays the default. RECOVERY is the page that also ships to disk —
  whoever reads it is offline by definition — so an installed machine now carries
  both `/usr/share/doc/w/RECOVERY.md` and `/usr/share/doc/w/RECOVERY.ru.md`, and the
  on-box assistant points a Russian-speaking user at the second one.

## v0.5.1

- **Cancelling an authentication prompt no longer counts against you.** Dismissing the
  auth card — or pressing "Use password" — was recorded by `pam_faillock` as a failed
  login. Three cancels and the password prompt refused you for ten minutes
  ("Authentication token manipulation error"), while a fingerprint still let you
  straight in. On current polkit the PAM helper is a socket-activated system unit, so
  cancelling only closes the socket: the helper lives on, reaches `pam_unix` with a
  dead conversation, and every abandoned window was tallied. `/etc/pam.d/polkit-1` now
  carries its own copy of the password chain, in which a dead conversation fails on the
  spot without touching the counter. Wrong passwords are still counted and the lockout
  still works — only cancelling stopped being an attempt. If a machine is locked out
  right now, it clears by itself after ten minutes, or at once with:

  ```
  sudo faillock --user "$USER" --reset
  ```

- **"Use password" during a fingerprint prompt now actually switches to the password.**
  v0.5.0 announced this, but it never worked on any machine: the button dropped its
  flag into `$XDG_RUNTIME_DIR`, while the stack that reads it runs inside a unit with
  `ProtectHome=yes`, where `/run/user` does not exist. The flag was invisible, so the
  password you typed simply sat in the queue until the reader's 30-second timeout —
  exactly the behaviour that release said was gone. The channel moved to `/run/w/fp/`,
  and the button takes effect immediately.

- **Cancelling a fingerprint prompt frees the reader instead of holding it for half a
  minute.** The rough edge named in v0.5.0 — the reader staying busy for the rest of
  its 30 seconds after you switch to the password — is gone, and on readers with a lamp
  it no longer stays lit. W now ends an abandoned verification the only way
  `pam_fprintd` accepts, by restarting `fprintd` through a rule scoped to that one
  unit, that one verb and your own active session: 83 ms to the password prompt,
  against 27 seconds before. The card also stops offering the finger while the reader
  is still busy, rather than asking you to touch a device that cannot answer.

- **The card no longer says whose password it wants when there is nobody else it could
  be.** "Password for user X" is shown only when the account is not the one you are
  logged in as, or when there is a choice to make.

  Updating deploys all of the above, but the running session keeps the auth agent it
  started with. Restart it — or just log out and back in:

  ```
  systemctl --user restart w-authd
  ```

- **Under the hood.** The nightly image build now initialises pacman's keyring before
  upgrading it, so a build can no longer finish green while the image quietly distrusts
  the new master keys. The issues the nightly canary opens are prefixed `[canary]` and
  name the stage that actually failed, instead of reading "Edge image fails to install"
  over a run in which the image installed, booted and passed every check.

## v0.5.0

- **Choosing a kernel and switching hardening on now work on encrypted installs, where
  both were silently doing nothing.** `w-kernel` and the hardening step wrote
  `/etc/default/grub` and ran `grub-mkconfig` unconditionally. An encrypted install
  boots through Limine, which reads `/etc/kernel/cmdline` and never looks at GRUB's
  config — but GRUB is installed there all the same, so the write succeeded, the
  regeneration reported success, and nothing anywhere said otherwise. On every
  encrypted machine the result was that `w-kernel set` did not change which kernel
  booted, and the hardening boot parameters never reached the kernel: `w-kernel harden
  status` answered `mixed` — sysctl drop-ins on, not one cmdline token. `w-kernel` now
  detects the bootloader and writes what that bootloader actually reads.

  Updating fixes this for you — the hardening profile is applied again through the
  corrected path — but **boot parameters only take effect at the next reboot**. To see
  where a machine stands:

  ```
  w-kernel harden status
  cat /proc/cmdline
  ```

- **The kernel is now selectable from the Hub, and `linux-lts` is offered as a third
  choice.** W Hub → System → General lists zen (W's default), vanilla and lts, marking
  which is installed, which is the default and which is running; picking one opens a
  terminal, because installing a kernel is a long download plus a DKMS rebuild.
  Hardening became a switch in W Hub → System → Security. That Security tab used to be
  hidden on machines without Limine — that is, on every unencrypted install, which is
  exactly where bootloader-independent hardening was least reachable. It is now always
  shown, and the Secure Boot rows inside it are what depends on Limine.

  From a terminal:

  ```
  w-kernel list
  sudo w-kernel set lts
  sudo w-kernel remove vanilla
  sudo w-kernel harden off
  ```

  `set` never uninstalls anything, so switching back to a kernel you already have is
  offline and instant, and `remove` refuses to take away the running or the default
  kernel. A kernel change now also raises the "reboot needed" badge in the bar.

- **Your SSH agent is now something you choose: `w-ssh`.** W still ships
  gcr-ssh-agent and still defaults to it, so nothing changes unless you ask. What
  changed is that the session no longer hardcodes that one agent's socket:
  `SSH_AUTH_SOCK` is a fixed path — `$XDG_RUNTIME_DIR/w/ssh-agent.sock` — with a
  symlink behind it pointing at whichever agent is active. A password manager that
  carries SSH keys takes the slot in one command:

  ```
  w-ssh list
  w-ssh use bitwarden
  w-ssh status
  ```

  Bitwarden, 1Password, a plain `ssh-agent` on a fixed path and gcr are known out of
  the box; any other agent is one `SOCKET_<name>=` line in `~/.config/w/ssh.conf` (or
  `/etc/w/ssh.conf` for the whole machine) and it appears in `w-ssh list` with no code
  change — `w-conf cat ssh` shows the catalogue. `w-ssh use none` leaves the session
  with no agent at all. The stable path is exported by the session, so it is in place
  after your next login.

  One thing to know before switching: an agent holding a full vault offers every key
  it has, and sshd gives up after five (`MaxAuthTries`), so a large vault can fail to
  log in anywhere. `w-ssh sync` fixes that by generating per-host
  `IdentityFile`/`IdentitiesOnly` selectors from the keys in the agent, reading each
  key's name in the vault as the list of hosts it belongs to. They live in a generated
  file included from `~/.ssh/config`; `w-ssh include` adds that include line, which
  has to sit at the very top of the file to apply to more than one host — `w-ssh
  status` says so if it does not.

- **A Bitwarden bundle, installed only if you ask for it.** `w-pack install bitwarden`
  — it is not offered during installation and nothing is pulled in by default. W ships
  no password manager and takes no position on which one you should use; what it ships
  are the slots one plugs into — the polkit prompt that biometric unlock speaks to,
  the Secret Service that stores the unlock key, the clipboard filter that keeps
  copied passwords out of history, and now the SSH agent above. The bundle is just the
  wiring: the app from the Arch repository (that package ships the polkit action, so
  biometric unlock works without the app's own setup step), its SSH agent socket
  agreed with `w-ssh`, and tray autostart.

- **A fingerprint prompt now looks like one.** While the reader is being waited on,
  the authentication card shows a fingerprint glyph and no password field — there was
  nothing you could usefully type into it — and turns itself into the password card
  the moment fprintd gives up. "Use password" is now immediate, where previously
  pam_fprintd held the conversation for its full 30-second timeout and a password
  typed in the meantime simply sat in a queue. This needs a reader with an enrolled
  finger (`fprintd-enroll`); a machine without one sees exactly what it saw before.
  One rough edge remains: after you switch to the password, the reader itself stays
  busy for the rest of its 30 seconds. It no longer holds anything up.

- **The W mark is the same size in the boot splash, on the login screen and on the
  desktop.** On a HiDPI panel it was three different sizes: Plymouth drew it at double
  size and blurry (it applied GNOME's device-scale heuristic and then bilinearly
  upscaled every sprite), the greeter at a fractional scale such as 1.5 picked a 4K
  wallpaper master for a 2K screen, and only the desktop had it right. All three now
  derive it from the panel they are actually drawing on, and the splash logo is
  rasterised from the theme's vector at the exact pixel size (this adds `librsvg`).
  Ordinary 1x monitors were already consistent and look unchanged. A side effect worth
  having: on a multi-monitor setup, a head with a different DPI is no longer forced to
  share another head's scale.

- **`sudo w-reset` no longer breaks the thing it restores.** Two defects, both present
  in released versions, both invisible to any static check because they only happen at
  runtime. Restoring a single file lost its executable bit — the real damage being
  `w-reset updatesys`, which left `/usr/bin/w-sync` unable to run, so the update client
  could no longer deliver its own fix. And the vendor copy of `/etc/w/update.conf` had
  `CHANNEL=stable` hardcoded even though the channel is detected from the checkout, so
  restoring it quietly took the machine off edge. The mode now comes from the pristine
  copy, and the vendor copy is built from the same detection a fresh install uses.

  If you ran `sudo w-reset updatesys` on a machine before this release, it needs one
  command by hand before it can update at all, and a look at the channel afterwards:

  ```
  sudo chmod 755 /usr/bin/w-sync
  w-sync status
  ```

- **The assistant's desktop knowledge is split into three skills.** `w-desktop` had
  grown to carry five subsystems and fourteen tools and sat one byte under the size
  limit skills are held to, which meant new knowledge about one subsystem was being
  paid for by dropping knowledge about another. It now covers the compositor, windows,
  key bindings, the shell UI and screenshots; `w-displays` covers monitors, the
  greeter's screen and night light; `w-session` covers session memory and named
  layouts. Every tool is still there under the same name. Asking what your resolution
  is no longer drags layouts and compositor configuration into the answer.

- Smaller things. A first boot no longer logs `Failed to start Ghostty`: the vendor
  unit was the only one under the graphical session target without a "needs a display"
  condition, and W has a path on which that target comes up without one — the terminal
  warm-up itself was never affected. Limine's snapshot manager now says when it evicts
  old snapshot boot entries to stay inside the EFI partition, instead of doing it
  silently — which matters more now that a machine may carry three kernels.

## v0.4.0

- **W now refuses an update it cannot verify.** Until this release, trusting an update
  meant trusting the transport: HTTPS, plus the assumption that the address in
  `/var/lib/w/src/.git/config` still pointed at the real W. Everything `w-sync` does
  after a pull runs as root, so that assumption was worth root on your machine. Every
  release is now published as an annotated tag signed with the W release key, and
  `w-sync update` verifies that signature against the key shipped on the machine
  (`/usr/share/w/update/w-release.allowed_signers`) **before** it takes a snapshot and
  before it pulls. A tip that carries no release tag, or one not signed by a trusted
  key, stops the update dead and leaves the machine bit-for-bit as it was. `w-sync
  status` gained a `Signed:` line saying which way this is set.

  Verification is on by default, including on machines installed before this release.
  If your checkout tracks something other than the official repository — a fork, or a
  branch of your own — there are no signed release tags to find, so this update
  records `VERIFY_SIGNATURE=no` in `/etc/w/update.conf` for you. A value already in
  that file is never overwritten.

- **If `w-sync update` has been dying on what looked like a credentials problem, this
  release is the fix — and the fix has to arrive by hand once.** The install image is
  tagged `edge`, and the nightly build moves that tag. `git fetch --tags` refuses to
  move a tag it already has and fails the entire fetch, so on a machine that had once
  seen that tag the *next* `w-sync update` died before it could do anything, and
  reported it as though the repository could not be reached. The fetch now passes
  `--force --prune-tags`. Since the broken code is the code that would have to run to
  deliver its own fix, a machine already in this state needs one command first, run as
  the user who owns the checkout:

  ```
  git -C /var/lib/w/src fetch --tags --force --prune-tags origin
  w-sync update
  ```

- **The status bar is now composed by you, screen by screen.** W Hub -> Appearance ->
  Bar is a new tab listing every block the bar can show, once per connected monitor,
  with the whole bar switchable off per screen as well. The same thing from a terminal
  — or through the assistant, which knows these commands:

  ```
  w-bar status
  w-bar block HDMI-A-1 tray off
  w-bar monitor eDP-1 off
  ```

  Choices live alongside the rest of your bar settings in
  `~/.config/quickshell/w/config/bar.json`. Switching a bar off keeps them, so
  switching it back on restores the same composition. Bar position moved out of
  Appearance -> Settings into this new tab; `w-appearance bar-position` is unchanged.

  Two things follow for a machine that already exists. A new install now ships four
  blocks switched off — system monitors (CPU/RAM/temperature/disk), network,
  brightness and keyboard backlight: they are readouts rather than everyday controls,
  and each is two clicks away in the Hub. **Your own bar is left exactly as it is** —
  that file is yours and updates do not touch it. But blocks are addressed by an `id`
  that your `bar.json` predates, so the new tab and `w-bar` will list nothing on your
  machine until the file has them. Taking the new default — which replaces your bar
  customizations, after backing the current file up — is:

  ```
  w-reset quickshell config/bar.json
  ```

  Adding `"id": "<name>"` by hand to the blocks you want addressable works just as
  well; the bar reloads as you save.

- **The Hub menu was reorganised.** It had grown into a list in the order things were
  added: twenty tiles in which a settings section and a one-shot command looked alike.
  It is now an even 4x4 — ten sections (appearance -> devices -> connectivity -> power
  -> system -> extensions) followed by six quick actions. Security and Date & time
  were each a section holding two or three controls; both are now tabs of System,
  where the boot-options tab appears only on a machine that has them. Calendar and
  Screenshot are no longer tiles: they are launcher entries now, the calendar still
  opens from the clock, and the screenshot entry takes a region (the other modes
  capture instantly and would photograph the launcher closing). The Power tile is
  called Power menu, so it no longer reads as a synonym of the Power section next to
  it. Separately: a highlighted row is no longer clipped at the edge of a scrolling
  list, and a dropdown in a bottom row now opens upwards instead of drawing past the
  card — which also fixes the NumLock dropdown under Input, wrong since it shipped.

- **Three launcher entries never worked, and a fourth is new.** Power menu, Volume
  control and Assistant have been in the launcher since they shipped and did nothing
  when clicked: their `Exec=` line was quoted in a way the desktop-entry specification
  does not recognise, so what reached the shell was a syntax error. Each had another
  door — a hotkey, the logo's right-click menu, a bar block — which is why it went
  unnoticed until Calendar, which now has an entry of its own and no other door. All
  four work.

## v0.3.0

- **W has moved to its permanent home — https://github.com/tarkh/w.** Every release
  up to and including v0.2.0 was published from a scratch repository used to shake the
  release machinery out, and that repository is being deleted. The address is baked
  into the install image and into `/etc/os-release`, so this release *is* the move:
  a new install points at the new repository on its own. A machine installed from an
  older image keeps pulling from the old address and stops updating the moment it
  disappears — point it at the new one once and it resumes:

  ```
  git -C /var/lib/w/src remote set-url origin https://github.com/tarkh/w
  sudo w-sync update
  ```

  The entries below this one describe releases of that earlier repository, so their
  tags and release pages no longer exist. Everything they describe is present in the
  system you are running; the changelog moved across intact on purpose.

- **Switching off your last display no longer strands the desktop.** With every
  connected output disabled, the machine came up with a session that runs, answers on
  the network and draws nothing — a black screen with no way back that does not
  involve a second computer. The Hub never offered the switch on a single-screen
  machine, but two ways around that existed, and both are now closed:

  - `w-monitor disable` run from a text console skipped the "not the last active
    output" check completely, because the check asked the running compositor and there
    is none on a console. It has been skippable that way in every release so far. The
    check now answers from the kernel's list of connected outputs when there is no
    compositor to ask, so it holds on a console too.
  - The dangerous case is not one command, it is time passing. Switching off the
    laptop panel while an external monitor is plugged in is a perfectly good thing to
    want, and the machine only breaks later, when the external one is unplugged —
    a moment at which nothing was checking anything. The display layout is now judged
    once more immediately **before** the compositor reads it, separately for your
    session and for the login screen, and if it would leave every screen off, exactly
    one is switched back on. Every other choice you made is left alone, and on a
    healthy configuration this does nothing whatsoever.

  Should you still land on a black screen, `RECOVERY.md` now has a section written for
  that symptom — Ctrl+Alt+F2, `w-monitor reset --all`, `sudo w-monitor greeter reset`,
  reboot — and it ships on the machine too, at `/usr/share/doc/w/RECOVERY.md`, which is
  where you will need it.

- **The install image is rebuilt nightly, and no longer right after each release.**
  The ISO the README links to is one rolling image built from the current tree.
  Publishing a version no longer forces a rebuild on the spot, so for a day or so
  after a release the download can still be the previous night's image. It makes no
  difference to what you end up with: an image here is a bootstrap medium, and the
  first update pulls the machine up to the current tree regardless.

## v0.2.0

- **`w-rollback` — one command that puts an older system back.** W has taken a
  filesystem snapshot before every package transaction and every `w-sync update`
  since the beginning, but nothing turned one back into the running system.
  `sudo w-rollback run` now does: it lists the snapshots, asks which one to go back
  to, and asks you to confirm before it changes anything. **The system it replaces
  is kept, not deleted**, so a rollback can itself be rolled back. It works on both
  kinds of install — encrypted (Limine) and plain (GRUB) — and both paths were
  walked on real machines rather than reasoned about. `w-rollback status` tells you
  where you stand without changing anything.
- **The rollback W did have never worked.** The assistant's `w_snapshot_rollback`
  action — present in every release up to and including v0.1.7 — called `snapper
  rollback`, which repoints the btrfs default subvolume, while W boots an explicit
  `subvol=@`. It reported success and changed nothing, every single time. If you
  ever asked the assistant to roll back and it told you it had, it had not — and
  your system was not damaged either, because nothing happened at all. The
  assistant can now only *start* a rollback: it opens `w-rollback`, and the
  password and the confirmation are yours.
- **RECOVERY.md — what to do when the machine will not boot.** A page written by
  symptom: won't boot, boots wrong, an update made things worse. It ships on the
  machine as well, at `/usr/share/doc/w/RECOVERY.md`, which is where you will need
  it — a machine that will not boot has no browser.
- **You are now told when you are running from a snapshot.** Booting a snapshot
  from the boot menu is the recovery path, its root is read-only, and the desktop
  looked completely normal — so anything saved outside `/home` vanished at the next
  reboot without a word ever being said. A notice at login now says so, on both
  bootloaders.
- **The installer no longer asks about Secure Boot.** The checkbox was cosmetic:
  the answer was read three times and reached nothing — no keys, no signing,
  whichever way you answered it. Turning Secure Boot on for real needs the firmware
  in Setup Mode and a UEFI toggle, neither of which an installer can do for you, so
  the option is gone and the encrypted install's final screen now points at **Hub →
  Security**: it enables Secure Boot in two steps and then seals TPM2, after which
  the passphrase stops being asked at every boot. This affects new installs only;
  nothing changes on an installed system.
- The on-box assistant now knows the upgrade order for laptops with Broadcom Wi-Fi:
  the driver goes in **before** the system upgrade. The other way round, DKMS
  rebuilds the old driver against the new kernel, the build fails, and the machine
  comes back with no Wi-Fi — which on a laptop with no Ethernet port is also the
  channel you would have fixed it through.

## v0.1.7

- **The install image builds again.** Arch removed the `broadcom-wl` package from
  its repositories on 1 September, and the image's package list still asked for
  it, so every build since — including the one for v0.1.6 — failed before
  producing anything. The list now follows upstream, which dropped the same
  package the same day. If you are updating an installed system, nothing here
  changes it; this restores the download.
- **Broadcom Wi-Fi on old chips, and what changed.** That package was what let
  the *live* session drive a handful of older Broadcom chips — BCM43142,
  BCM4360, the ones in machines like the 2013–2015 MacBook Pro. Arch ships only
  a source version now, so the default image no longer covers them in the
  installer, exactly as the official Arch image no longer does. **Installed
  systems are unaffected**: the installer still detects such a chip and installs
  the driver for it. What is affected is installing on a laptop that has one of
  those chips *and* no Ethernet port — there the installer can no longer bring
  the network up. For that case you can build yourself an image that does:
  `./scripts/build-iso.sh --broadcom-wl`, see "Building your own ISO" in the
  README.
- The README now has a section on building your own image, instead of a note
  buried in the install steps.

## v0.1.6

- **Folders in the file manager are the theme's colour again.** W recolours the
  Papirus folder icons to the tone of the active theme, and that had quietly
  stopped working in v0.1.2 — the release that moved W's internals out of
  `/usr/local`. The recolouring step looked for its helper on `PATH`, where it
  no longer is, found nothing, and skipped without reporting anything, so
  nothing in the logs said so. If you installed or updated since v0.1.2 your
  folders have been stock Papirus blue; updating fixes them, and already-open
  windows pick up the new icons when you restart them.
- A new default wallpaper for the `w` theme, in all four resolutions. The colours
  of the theme are unchanged — the picture was drawn to fit the palette, not the
  other way round — so nothing else about your desktop moves. If you are using
  your own theme or your own wallpaper, this does not touch it.
- Nothing else changes on an installed system.

## v0.1.5

- The unencrypted install path is now tested as well. Every published image was
  already installed onto an encrypted disk and checked before this; now the
  plain btrfs + GRUB layout — what you get by answering "no" to encryption — is
  installed and checked alongside it, on the same image. The two use different
  boot loaders, so passing one said nothing about the other.
- Your assistant now answers update questions correctly. It knows that this
  repository publishes one commit per release (so "one behind" means one
  version, not one commit), that pinning `REF` in `/etc/w/update.conf` holds a
  machine in place, and that `w-update` and `w-sync` are two different updates —
  packages from Arch, and W's own configuration.
- Nothing else changes on an installed system.

## v0.1.4

- Every published image is now installed, not just built. After each build a
  runner boots the very file on the download page, installs it unattended onto
  an encrypted LUKS2 + Limine + TPM2 disk — the stack a default install
  produces — reboots into the result and checks it: no failed services, no
  crashes, the login manager up, the boot loader correctly staged. If an image
  would not install, that is now known the same day instead of on your machine.
- Nothing on an installed system changes in this release; updating one only
  restamps its version.

## v0.1.3

- The install image on the releases page is now rebuilt every night from this
  repository, instead of whenever one happened to be built by hand. W is a thin
  layer over a distribution that moves daily, so an image that sits still only
  gets further from Arch — and an upstream package that stops building now turns
  into a failed build the same night, rather than into a failed install on your
  machine weeks later. Same page, same link, still exactly one image.
- Nothing else changes. No tool, no default and no configuration is different in
  this release; updating an installed system only restamps its version.

## v0.1.2

- W's own commands now live in `/usr/bin` and its internal helpers in
  `/usr/lib/w/`, instead of `/usr/local`. `/usr/local` is yours: nothing W
  installs will appear there any more, so what you put in it is once again the
  only thing in it.
- **If you are upgrading an existing install, remove the old copies by hand and
  reboot** — `w-sync` does not delete files, and `/usr/local/bin` comes before
  `/usr/bin` in `PATH`, so anything left behind keeps shadowing the updated
  tool, `w-sync` itself included:

  ```
  sudo rm -f  /usr/local/bin/w-* /usr/local/bin/papirus-folders
  sudo rm -rf /usr/local/lib/w
  sudo rm -f  /usr/local/src/w-windowblind.c
  sudo reboot
  ```

  Leave `/usr/local/bin/sudo` alone — that is W's `sudo-rs` shim and it works by
  being found first. A fresh install needs none of this.

## v0.1.1

- The README now says where the first-boot logs live, so a failed install is one
  `ls /var/log/w/` away from an explanation instead of a guess.
  Thanks to @tarkh (#1).

## v0.1.0

First public release.

- Beta of the W desktop: Hyprland under uwsm with the Quickshell UI (bar, launcher,
  notification centre, calendar, clipboard, volume and brightness, power menu,
  network and Bluetooth tray, lock screen with fingerprint support), a session that
  remembers open windows and named layouts, and a unified authentication dialog.
- Theming across GTK, Qt/Kvantum, icons, terminal, shell prompt, Firefox chrome,
  bootloader and boot splash from one palette. `w-theme new <image>` builds a full
  theme from any wallpaper.
- TUI installer in English and Russian — disk, LUKS encryption with Secure Boot,
  locale, keyboard, timezone, users, update channel, optional software bundles —
  plus an unattended `--preset` mode.
- btrfs layout with snapper timelines for root and home, zram in place of swap.
- Updates over the `edge` channel: `w-sync` takes a home snapshot, pulls, and
  applies only the modules a change actually touches. `w-reset` restores any module
  to its W default.
- The `w-*` tool set: updates, themes, wallpaper, power, monitors, keyboard,
  pointer, night light, keyboard backlight, DNS, firewall, logs, time, screenshots,
  package bundles. `w-info` lists them all.
- An on-box AI layer, opt-in and off by default, with every state-changing action
  behind polkit.
