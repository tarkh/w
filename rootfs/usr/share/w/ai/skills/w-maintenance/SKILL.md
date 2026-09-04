---
name: w-maintenance
description: >-
  Recover and maintain a W install: reset any subsystem's config back to the W
  default with w-reset (config recovery after a manual edit broke something), keep
  an edge machine in sync with w-sync (the git-checkout update channel), and roll
  back via btrfs/snapper snapshots. Load this for "I broke my config", "restore
  defaults", "reset a theme/module", edge-channel updates, snapshot rollback, or
  "my setting is not what the config file says" (W's config is layered — this skill
  explains how to read the layers with w-conf).
sources:
  - path: .claude/library/w-conf.md
    sha256: 002069840e569db3a750c268458c12fc7ef2396539f4438e3f7068bb43ec729f
  - path: .claude/library/w-reset.md
    sha256: 75390ab0872e4a11dd2794a2a859a04d6a9f4ff6c90f80c7e0f9e2488a106ddb
  - path: .claude/library/update-system.md
    sha256: abcb62f7c888b819407672b86f94795cbd1b716c26ca6c25998d7db240399a50
  - path: .claude/library/w-rollback.md
    sha256: 95fe918c6339f5e6aa423b77857f702c0ceb21783b059c4c4bbf78bdebd7ab73
tools:
  - w_snapshot_list
  - w_snapshot_rollback_plan
  - w_snapshot_rollback_start
  - w_sync_update
---

# W Maintenance & Recovery

When a hand-edited config misbehaves, or an edge machine needs updating, W has
first-party recovery paths that never require reinstalling. Three tools:
**`w-reset`** (config → default), **`w-sync`** (edge update channel), and
**snapper** (filesystem snapshots).

## Layered config — why a value may differ from the file you edited

W reads each subsystem's settings from an ordered stack, not a single file:

    W defaults (/usr/share/w/defaults)  →  site defaults (/etc/w/site-defaults.d)
      →  admin (/etc/w)  →  user (~/.config/w)  →  site POLICY (/etc/w/policy.d)

A higher layer wins **per key**, so the admin file holds only what deviates from
W's defaults, and an update can improve a default without touching a machine's
decisions. Two consequences worth knowing before you answer a config question:

- **`w-conf cat <subsys>`** prints every effective key with the layer it came from,
  plus any line the reader ignored. `w-conf origin <subsys> <KEY>` answers "which
  file wins" for one key; add `--path` for the file itself. Run it as root to see
  the layers the system tools actually read.
- **Not every key may be set by a user.** Each split subsystem ships a schema
  declaring which keys are system-scope; a system-scope key placed in a user file is
  ignored on purpose, and the setter refuses to write it there in the first place.
  `w-conf scope <subsys> [KEY]` prints the declaration. Check before advising someone
  to edit `~/.config/w/<subsys>.conf`.
- **A key may be taken out of this machine's hands entirely.** On a machine that
  belongs to a fleet, `/etc/w/policy.d/<subsys>.conf` pins values as site POLICY:
  `w-conf origin` reports layer `policy`, every setter refuses with the file name, and
  the Hub shows the control with a padlock. This is not a bug and not something to
  work around locally — say so plainly and point at whoever manages the site policy.
  Site *defaults* (`site-defaults.d`) are the opposite: mere advice, below the local
  admin, so a local decision still wins. Both arrive via `apply.sh --site` from the
  fleet's own small git repo (`SITE_REPO` in `/etc/w/update.conf`); deleting a file
  there revokes the policy on the next update.

Every W subsystem with a KEY=value config is converted (power, dns, time, logs,
terminal, crypt, ai, nightlight, kbdlight, mirrors, appearance). Two deliberately are not:
the update channel (`update.conf`, read only by the updater itself) and the non-KV
artifacts (the active-theme symlink, the greeter monitor files), which are replaced
whole rather than merged per key.

## `w-reset` — restore a config to the W default

`w-reset` force-restores the config of *any* W subsystem to the shipped default.
It is **recovery, not update**: use it when someone edited a config, broke it, and
wants the known-good W version back — independent of the update channel.

```
w-reset <module>          # whole module → W default (makes a pre-backup first)
w-reset <module> <file>   # one path (full home-relative path OR trailing suffix)
w-reset <bundle>          # an INSTALLED W-Pack bundle, same syntax
w-reset --all             # every module and every installed bundle
w-reset list              # modules and bundles that have a reset manifest
w-reset check             # AUDIT: what drifted from the W default (changes nothing)
w-reset status            # availability of the pristine sources
w-reset --user <name> …   # another user's home / system scope (root only)
```

- **Your own home needs no sudo** (you own your files). Any system or `override`
  path (`/etc`, `/usr`, `/etc/w`) needs root; `w-reset` prints one "N paths need
  root, re-run with sudo" summary rather than spamming per file.
- **Nothing is lost silently.** Every reset makes a pre-backup first: home paths go
  to `~/.local/state/w/reset-backups/<timestamp>/`, system paths to
  `/var/lib/w/reset-backups/<timestamp>/`. Both paths are printed at the end.
- **Stray files survive.** Directories are restored with rsync *without* `--delete`,
  so W files come back but unrelated files you added in the same folder stay.
- **Pristine sources:** home files come from `/etc/skel` (always offline); system
  files from the edge repo `/var/lib/w/src/rootfs` (or the `w-system` package on
  stable); `/etc/w/*` overrides from the vendor copy under `/usr/share/w/vendor/etc-w`.
  **Exception — a subsystem already split into layers** (it has
  `/usr/share/w/defaults/<name>.conf` or `.schema`; today: `power`, `dns`, `time`,
  `logs`, `terminal`, `crypt`, `ai`, `nightlight`, `kbdlight`, `mirrors`, `appearance`): there is
  no file to copy back, so the reset simply *strips the admin file's settings* and the
  values fall through to the vendor layer — genuinely "as on a fresh install". Anything
  the subsystem needs to keep (e.g. the machine `MODE`) is re-seeded by that
  subsystem's own next `apply`, not by `w-reset`.
- **The user's OWN wconf settings are wiped too, not just the admin file.** Any key
  scoped `user`/`both` in a split subsystem's schema is written to
  `~/.config/w/<subsys>.conf` by the setter (Hub and CLI write the same file — there
  is no GUI-vs-CLI distinction here), and `w-reset <module>` deletes that file too
  (class `user-conf` in the manifest — backed up first, like everything else). This
  closed a real bug (2026-08-09): Night Light set from the Hub used to survive
  `w-reset --all` because nothing reset that layer. `ai` has two such files
  (`ai.conf` + `ai-features.conf`); both are wiped together. Not touched: the AI
  profile *catalog* (`~/.config/w/ai/profiles/`, authored content) and
  `~/.config/hypr/monitors.lua` (generated monitor layout, a `w-monitor` concept, not
  wconf) — neither is a "setting" in this sense.
- **`power` and `nightlight` also re-render on reset.** Their manifests hold the
  *config*, but what the machine actually obeys is rendered from it (the hypridle
  config, the logind drop-in, the hyprsunset config), and none of those is a manifest
  path. `w-reset` therefore calls the subsystem's own `apply` afterwards, so the reset
  is visible immediately instead of waiting for the next `apply.sh`. You do not need to
  tell the user to run anything extra — **except that this re-render step needs root**
  (it only runs when `w-reset` itself ran as root/sudo). A non-root
  `w-reset nightlight`/`power` on your own home still deletes the user config, but the
  rendered file (`hyprsunset.conf`/`hypridle.conf`) only catches up on the next `sudo`
  run — tell the user to use `sudo w-reset <module>` (or `--all`) if they want the
  effect immediately. `style` has no such gap: it always re-renders live via
  `w-style apply user`, sudo or not.
- **W-Pack bundles reset the same way, by bundle name** (`w-reset dev`,
  `w-reset containers`). A bundle carries its own pristine copies inside its staged
  tree under `/usr/share/w/packs/<bundle>/`, which makes it *more* reliable offline
  than a module: no edge checkout is needed. Only INSTALLED bundles can be reset —
  restoring the config of software that is not on the machine would be meaningless,
  and `w-reset` says so. Module and bundle names share one namespace and cannot
  collide, so no prefix is ever needed. Resetting a bundle's home config needs no
  root, exactly like a module's.
  After any home reset, `w-reset` re-runs `w-style apply user` so themed files
  (GTK/Qt/shell colors, Hyprland `*.lua`) return to the **active** theme, not baseline.
- **`w-reset style`** is special: the per-user "setting" is the theme choice, so it
  delegates to `w-theme reset` (drops the active-theme pin and re-renders).
- **An update runs on a LIVE machine.** Applying happens while the user's session and
  apps are running, so a step that walks someone's home can race with them. If an
  update reports a failure, check whether it stopped part-way (`/var/log/w/apply.log`):
  the git checkout has already moved forward at that point, so the machine can sit
  ahead in source and behind in applied state — re-running the update is the fix.
- **A pack's own setup is replayed on update.** When a pull touches the bundle tree,
  `w-sync update` runs `w-pack refresh` — it re-applies the *installed* bundles' config,
  theme axis, AI skill and idempotent `setup.sh` **without touching packages**. So a fix
  to a bundle's setup reaches machines that installed it long ago; it is not a reinstall
  and never goes to the network.
- **Admin config under `/etc/w` survives an update.** Those files are ownership class
  `override`, and `w-sync update` deliberately skips them, so the machine mode, the
  active theme, the NTP server selection, the AI switches and the rest stay put across
  an edge update. Only a *reset* returns them to the vendor default. If a user reports
  such a setting reverting on its own, that is a bug worth reporting, not expected
  behaviour — check the file's mtime against the last `w-sync` run.
  For a **split** subsystem the admin file holds only the deviations from W's own
  defaults, so an update can improve a default *and* leave the machine's decisions
  intact. `w-conf cat <subsys>` shows every value with the layer it came from — that
  is the tool to answer "why is this setting not what the file says".

- **"What on this machine differs from stock W?" → `w-reset check`.** Read-only, and
  the four categories are not interchangeable: `[drifted]` = a W-managed file edited
  by hand, **the next update overwrites it** (the only category to act on — save a copy
  or `w-reset <module>` deliberately); `[customised]` = a class-`user` file, the user's
  own copy, updates leave it alone (perfectly normal, not a problem); `[deviation]` =
  admin state under `/etc/w`, preserved by design; `[personal]` = the user's own wconf
  settings (`~/.config/w/<subsys>.conf`) — not at risk from an *update*, but a heads-up
  that `w-reset <module>` **will** erase them. `w-sync update` warns about the
  `[drifted]` category by itself, right before it overwrites anything.

**Recipe — "my bar/theme/hyprland config is broken, restore the W default":**
`w-reset quickshell` (or `w-reset hyprland`, `w-reset style`, …). Run `w-reset list`
to see resettable modules. Reversible: the pre-backup path is printed if you need
your edits back.

## `w-sync` — the edge update channel

Machines installed in **Edge** mode carry a real git checkout at `/var/lib/w/src`
(detected structurally by `/var/lib/w/src/.git`). `w-sync` pulls new W commits and
selectively re-applies only the changed modules. On a **Stable** install `w-sync`
is a no-op (stable updates arrive as the signed `w-system` package via `w-update`).

```
w-sync check     # fetch + behind-count + incoming commits → /var/lib/w/state/sync.json
w-sync log       # the pending commits
w-sync status    # channel + current state (incl. whether signatures are required)
w-sync update    # fetch → VERIFY SIGNATURE → pre-snapshot home → pull --ff-only → selective apply
```

**An update is verified before anything on the machine changes.** Every W release is
one commit tagged `vX.Y.Z`, and the tag is signed. `w-sync update` refuses to pull a
tip whose tag is not signed by a key in
`/usr/share/w/update/w-release.allowed_signers` — the check runs before the
pre-update snapshot, so a refused update leaves the machine byte-for-byte as it was.
`w-sync status` prints a `Signed :` line saying whether this is armed.

If it refuses ("REFUSING TO UPDATE"), that is a fact to report, not an obstacle to
route around. Do not suggest `VERIFY_SIGNATURE=no` in `/etc/w/update.conf` as a fix:
it is there for machines tracking a fork rather than the official repository, where
no signed release tags exist. A missing trust anchor is repaired with
`sudo w-reset updatesys w-release.allowed_signers`, which restores that one file from
the checkout. Use the per-file form, not the bare module: `w-reset updatesys` resets
everything the module owns, `/etc/w/update.conf` included.

**The checkout belongs to the primary user by design** (yay/makepkg refuse to run as
root, and `.git/config` is `chmod 600` because the clone URL carries credentials), so
git would normally refuse to touch it for anyone else. `w-sync` handles that itself:
**git always runs as the owner** (resolved with `stat -c %U /var/lib/w/src`), so the
same commands work run as that user, run from a root shell, or run through the AI
actuation path. Only the `apply.sh` step escalates, which `w-sync` does for itself.
A user who owns neither the checkout nor root gets a named refusal from `update`
("owned by 'x' — run as that user, or via sudo"), never a git ownership error.

**The sync status is machine-wide: `/var/lib/w/state/sync.json`.** One checkout = one
answer for everyone on the machine, so there is no per-user copy to reconcile (the old
`~/.local/state/w/sync.json` is dead — do not read it). Who does what:

- **the checkout's owner, and root** — `w-sync check` fetches and rewrites the file
  (`behind`, `err`, `ts`, and `commits[]`: the incoming subjects, capped at 30);
  `w-sync log` fetches live.
- **every other user** (a second admin included) — `check` is a deliberate no-op, and
  `log`/`status` report the recorded state instead, saying how old it is ("as of the
  last check, 2h ago") and flagging it stale past a day. They exit 0: not owning the
  checkout is not an error, and `w_sync_update('plan')` stays usable. The no-op says so
  when a person runs it in a terminal, and stays silent otherwise (the 6-hourly check
  timer is enabled for every user, and its journal is not the place for it) — so
  through you it produces no output at all. If a user reports that `check` "did
  nothing", that is the expected answer for them: the number they see in `status` is
  the owner's last check, and only the owner or root can refresh it.

⚠️ **`behind` can be `-1` — that means "unknown", not "up to date".** `w-sync check`
records a real count only when it actually reached the remote; any refusal writes
`-1` plus an `err` token:

| `err`     | meaning |
|-----------|---------|
| `network` | the remote was unreachable — check connectivity |
| `fetch`   | the remote answered and refused — check credentials in `.git/config` |
| `git`     | a local git failure inside the checkout |

`w-sync status` prints `unknown (<err>)` for it and the Hub's System panel shows it
as a warning, so a stale-but-honest state is never presented as "up to date". If you
need certainty, `w-sync log` fetches and fails loudly — when run by the owner or root.

`update` takes a **home snapshot first** (`snapper -c home`), fast-forwards, then
runs `apply.sh` only for the modules whose files changed (mapped via
`/usr/share/w/update/sync-map`; unmatched changes fall back to a full apply). A
background `w-sync-check` timer (6h) refreshes the shared state — it is enabled for
every user's session, but only the owner's run actually rewrites it. If `release.conf`
marks the update `REQUIRES_REBOOT`, reboot after it finishes.

An update never changes anyone's theme: `apply.sh` finishes by re-rendering the themed
files for every account, so a user reporting "the bar/lock screen came back in the
default theme after updating" is reporting a **failed render**, not a normal reset — see
the **w-theming** skill for where to look.

### What the remote actually is, and four things not to get wrong

- **One commit per release, not a stream of commits.** The public repository carries a
  single snapshot commit per released version, so `behind: 1` means **one release is
  available**, not "you are one commit behind", and `w-sync log` shows release notes
  rather than working-commit subjects. Say "a new version of W is available", and
  summarise the note — never "you are N commits behind".
- **`REF` in `/etc/w/update.conf` decides what the machine follows.** `REF=main` follows
  every release (the default); `REF=vX.Y.Z` pins the machine to one version and it will
  keep reporting up to date forever. If a user says updates stopped arriving, read
  `w-sync status` and check `REF` before suspecting anything else.
- **"The local checkout has diverged" is never normal.** The public branch is
  append-only and `w-sync update` pulls `--ff-only`, so a release cannot cause this: it
  means someone edited `/var/lib/w/src` by hand. Show the user what diverged and ask.
  **Never force, reset or re-clone the checkout** — you would destroy local changes they
  may not remember making.
- **`w-update` and `w-sync` are two different "update", and users conflate them.**
  `w-update` upgrades **Arch packages**; `w-sync` updates **W's own configuration**.
  Same split in `/etc/os-release`: `IMAGE_VERSION` is which version of W's configuration
  this is (moved by `w-sync`), `W_BUILD_DATE` is the day the image's packages came from
  Arch (moved only by installing from a newer image, never by an update). Asked "what
  version am I on", give both and say which is which.

The AI's curated MCP equivalent is `w_sync_update(action)`, two-step like
`w_system_update`: `'plan'` (read-only — fetch + show incoming commits and
status; a clear no-op on a stable-channel machine) then `'apply'` (Tier 2,
polkit prompt — runs the same fetch/snapshot/pull/selective-apply, but never
auto-reboots even if `REQUIRES_REBOOT` — only reports it). Gated by
`W_AI_TOOL_SYNC`.

**Updating needs an administrator.** Applying an update touches system paths, so
`w-sync update` (and `w-update`, and `w-pack install`) is for members of the
`wheel` group — this machine's administrators, the same definition sudo and polkit
use. A non-admin gets a one-line explanation instead of a password prompt, from
both the CLI and `w_sync_update(action='apply')`; `plan`, `check`, `log` and
`status` stay open to everyone. There is no workaround to offer from the CLI: say that
an administrator of the machine has to run it.

**The Hub's "Sync now" button is the one exception, and it is deliberate.** It does not
run `w-sync` as whoever is sitting at the session (that only ever worked for the
checkout's owner); it opens a terminal on `pkexec /usr/lib/w/w-hub-actuate
sync-update interactive`. So every administrator can use it, and on a **non-admin's**
session it raises the ordinary admin password prompt — an administrator standing there
can unlock it without switching users. If a user asks why the button now asks for a
password, that is the answer. The confirmation of the incoming commit list and the
reboot question still appear in that terminal; the AI path (`w_sync_update('apply')`)
is the one that skips them, because it has no terminal to answer from.

### After an update: "the new W feature did not appear"

A sync can succeed and still leave a new feature invisible, and it is almost never
a bug. Work down this list before suspecting the update:

1. **The file belongs to the user.** W splits home config in two: files W owns
   (overwritten every apply) and files the *user* owns, which are written **once**
   and never again. If a W improvement lands inside a user-owned file — `~/.zshrc`,
   an editor's `settings.json` — an update cannot deliver it, by design. Restore
   that one file to the current W default with `w-reset <module> <file>` (it makes
   a pre-backup first; personal edits to that file are lost, so read the diff or
   merge by hand if they matter).
   ⚠️ `w-reset` only knows base-system modules (`w-reset list`). Config seeded by a
   **W-Pack bundle** is not covered — there, restoring means editing the file by
   hand, or deleting it and re-running `sudo w-pack install <bundle>`, which
   re-seeds only what is missing.
2. **It needs a new session.** Session env (`/etc/w/env.d/*.sh`) applies from the
   next **login**; interactive-shell hooks (`/etc/w/zshrc.d/*.zsh`) from the next
   **new shell**. Nothing to fix — log out and back in.
3. **A bundle needs re-installing.** `w-sync` restages the bundle *tree* but never
   installs or re-runs a bundle's `setup.sh`. After an update that changed a
   bundle, run `sudo w-pack install <bundle>` (idempotent) to pick it up.
4. **An optional bundle is on the machine but not set up for this account.** A
   W-Pack has two layers: the *machine* part (packages, services — installed once,
   by an administrator) and the *per-user* part (its tools in `~/.local/bin`, its
   seeded config). The second is deliberately **not** rolled out to everyone on
   install — that would spend a person's disk and network on a choice they never
   made — so a bundle can be genuinely present machine-wide and genuinely absent
   from the asking user's home.

   This is reported honestly, not guessed at: `w-pack list` shows `[machine]` for
   exactly this state, and `w-pack status <bundle>` names the account. The fix is
   one un-privileged command run **as that user** — no sudo, no polkit, because it
   writes only their own home:

   ```
   w-pack setup <bundle>
   ```

   Nothing is broken here. `[machine]` is an honest "not yet", so say that rather
   than proposing a reinstall.

Base-system config is NOT one of these cases: every human account of the machine is
updated on every apply, so a second administrator seeing an older Hub or bar is a
real bug worth reporting, not expected behaviour.

When advising, name which of the four applies rather than suggesting a reinstall.

## Snapshot rollback (snapper / btrfs)

W keeps btrfs snapshots (`snapper -c root` and `-c home`) so a bad change can be
rolled back at the filesystem level. Pre-transaction snapshots are taken around
`pacman` (snap-pac) and around `w-sync update`. To boot an older system state, pick
a snapshot from the boot menu — **grub-btrfs** submenu on GRUB installs, the
`//Snapshots` entries on Limine (encrypted) installs. For the snapshot policy and
retention, see the **w-updates** / **w-diagnostics** skills.

**Rolling back is the user's own command, not yours.** `w-rollback` is W's single
verb for it and it routes per boot path: on Limine it hands over to
`limine-snapper-restore`, which also restores the kernel/initramfs pair the snapshot
was taken with (on that path `/boot/efi` sits outside the snapshot, so a root
restored without its kernel would boot new modules against an old tree); on GRUB it
replaces the `@` subvolume directly, `/boot` travelling inside it. Either way the
outgoing system is kept, so a rollback can itself be undone.

### How you help with a rollback

Three tools, and the split between them is deliberate:

- `w_snapshot_list(config)` — 'root' or 'home'. Read-only.
- `w_snapshot_rollback_plan()` — read-only: which boot path this machine has, and
  whether it is *currently running from a snapshot*.
- `w_snapshot_rollback_start(number)` — **opens** the rollback. A terminal appears in
  the session, W's password window asks the user to authenticate, and `w-rollback`
  shows what it will do and waits for them to type 'yes'. Omit `number` when the
  machine is booted from a snapshot and that is the one to restore.

The order matters: **list, let the user choose, then start.** Never choose the snapshot
yourself and never present a rollback as something you have done — a rollback takes the
whole system back, `/home` excepted, and only the user knows what since then still
matters. Say plainly what will happen: a password prompt, a summary, a confirmation,
and nothing changed until they give it.

There is no tool that performs a rollback outright, and that is on purpose. The older
`w_snapshot_rollback` tried, by calling `snapper rollback` — which on W's layout only
repoints the btrfs *default* subvolume while the system boots an explicit
`rootflags=subvol=@`. It reported success and changed nothing, for as long as it
existed. Starting a conversation the user finishes is the honest shape here.

If the machine no longer boots at all, none of this reaches it: the snapshot is chosen
in the boot menu first, and the whole procedure — including the live-USB case — is in
`/usr/share/doc/w/RECOVERY.md`.

## Rules of engagement

- Prefer the **narrowest** recovery: reset one file/module before `--all`; reach for
  a snapshot rollback only when config-level reset isn't enough — it takes the whole
  system back, including changes the user wanted to keep.
- `w-reset` and `w-sync update` both touch system paths → they go through W's
  polkit/sudo prompt and are audited. Explain what you're restoring before doing it.
- These are reversible by design (pre-backups, snapshots) — but say where the backup
  landed so the user can recover their edits.
