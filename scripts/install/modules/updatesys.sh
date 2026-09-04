# modules/updatesys.sh — W Linux edge update client (apply.sh --updatesys)
# apply.sh context: runs on the live system as root, post-boot. Deploys the w-sync
# script + sync-map + release trust anchor + check timer (they ride --rootfs too, but
# this module installs them itself so `--updatesys` alone is sufficient — sync-map
# routes changes to them here) and wires up the update
# channel. update-system.md axis 1+2 (edge / git). The stable channel needs none of
# this — it gets W as the w-system pacman package (phase 6); on stable this module
# just records CHANNEL=stable and leaves the timer off.
#
# Channel detection is structural, not a stored flag: /var/lib/w/src is a real git
# checkout only when the user picked Edge in the installer (modules/firstboot.sh
# clones there). So `.git` present ⇒ edge. /etc/w/update.conf is seeded once
# (seed-if-absent) — NOT shipped via rootfs, because apply_rootfs overwrites every
# apply and would reset the edge channel each time.

mod_updatesys() {
  info "Setting up W update client (w-sync)..."
  w_pac -S --needed --noconfirm git

  # The updater's own artifacts. They ride --rootfs as well, but sync-map routes a
  # change to any of them HERE (first match wins, so the generic `rootfs/* →
  # --rootfs` rule below it is never reached) — without this block w-sync could
  # never deliver a fix to itself, its map or its timer, and the deployed copies
  # silently drift from the checkout. Same self-sufficiency precedent as mod_packs
  # re-installing w-pack so `--packs` alone is enough.
  info "Deploying w-sync + sync-map + check timer..."
  install -Dm755 "$SRC/rootfs/usr/bin/w-sync" /usr/bin/w-sync
  install -Dm644 "$SRC/rootfs/usr/share/w/update/sync-map" /usr/share/w/update/sync-map
  install -Dm644 "$SRC/rootfs/usr/share/w/update/w-release.allowed_signers" \
    /usr/share/w/update/w-release.allowed_signers
  install -Dm644 "$SRC/rootfs/etc/systemd/user/w-sync-check.service" /etc/systemd/user/w-sync-check.service
  install -Dm644 "$SRC/rootfs/etc/systemd/user/w-sync-check.timer" /etc/systemd/user/w-sync-check.timer

  local repo="/var/lib/w/src"
  local channel="stable" ref="main"
  # Fleet overlay, answered once by the installer (unattended presets carry
  # site_repo/site_ref/site_profile; the interactive wizard leaves them empty and
  # an admin fills them in later). Read the same way mod_power reads its own
  # installer answer.
  local site_repo="" site_ref="main" site_profile="default" a
  if [[ -r /var/lib/w/install.conf ]]; then
    a="$(sed -nE 's/^site_repo=(.*)$/\1/p' /var/lib/w/install.conf | tail -1)";    site_repo="${a//\"/}"
    a="$(sed -nE 's/^site_ref=(.*)$/\1/p' /var/lib/w/install.conf | tail -1)";     [[ -n "$a" ]] && site_ref="${a//\"/}"
    a="$(sed -nE 's/^site_profile=(.*)$/\1/p' /var/lib/w/install.conf | tail -1)"; [[ -n "$a" ]] && site_profile="${a//\"/}"
  fi
  # Whether this machine demands a signed release tag before it pulls. Derived ONCE,
  # here, from what the checkout actually tracks, and then written into update.conf as
  # a plain readable line — not re-inferred on every run, so an admin can see it and
  # change it. The official repository publishes signed release snapshots and nothing
  # else, so anything tracking it is strict. Anything else — a fork, or the dev VM
  # tracking the private repo, whose branch is an ordinary history with no tags at all
  # — would have every update refused, so it starts open. w-sync's own default when
  # the key is absent is `yes`: an update.conf predating this becomes strict, which is
  # the right way round for the machines that are on the real repo.
  # It starts at yes and is only ever relaxed, never tightened: a stable install that
  # someone later flips to edge by hand must land on the strict setting, not inherit
  # an "off" that was written when there was no checkout to reason about.
  local verify="yes" origin_url=""
  if [[ -d "$repo/.git" ]]; then
    channel="edge"
    # Both facts are read out of the checkout's FILES, not by running git in it.
    # This module runs as root, the checkout belongs to the primary user (below), and
    # git's ownership guard refuses a root shell there — every `git -C "$repo"` here
    # dies silently and falls back to its default. That was invisible while the only
    # fallback was `main`, which is what the answer usually is anyway; it stopped
    # being invisible when the signature setting started depending on the remote, and
    # a machine on the official repository was seeded as if it were a fork.
    # `git config --file` reads a file, not a repository, so no guard applies.
    ref="$(sed -n 's|^ref: refs/heads/||p' "$repo/.git/HEAD" 2>/dev/null)"; ref="${ref:-main}"
    origin_url="$(git config --file "$repo/.git/config" --get remote.origin.url 2>/dev/null || true)"
    case "${origin_url%.git}" in
      https://github.com/tarkh/w|*@github.com:tarkh/w|ssh://git@github.com/tarkh/w) ;;
      *) verify="no" ;;
    esac
    # Edge = a dev checkout: hand it to the primary user so `w-sync check`/`pull`
    # run without root (apply still escalates via sudo). Creds embedded in the
    # clone URL live in .git/config — lock it down.
    local u; u="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"
    if [[ -n "$u" ]]; then
      chown -R "$u:$u" "$repo" 2>/dev/null || true
      [[ -f "$repo/.git/config" ]] && chmod 600 "$repo/.git/config"
    fi
  fi

  # Machine-wide sync state: ONE status per machine, not one per user (the old
  # ~/.local/state/w/sync.json was written by every user's check timer, including
  # users who cannot read the checkout at all and therefore recorded a false zero).
  # Owned by the checkout's owner — by fact, `stat -c %U`, not by the "first
  # uid>=1000" heuristic, and read AFTER the chown above — so the owner's atomic
  # tmp+mv works; 0755 lets root write it too and every other user read it.
  local sowner; sowner="$(stat -c %U "$repo" 2>/dev/null || echo root)"
  install -d -m755 /var/lib/w/state
  chown "$sowner" /var/lib/w/state 2>/dev/null || true

  # Vendor default for `w-reset updatesys` — the same answers a fresh install of THIS
  # machine would be given, not a fixed line. The channel is not a matter of taste:
  # it is detected from the checkout, so "as on a fresh install" means edge wherever
  # there is one. Hardcoding stable here made `w-reset updatesys` a one-way door off
  # the edge channel — the machine came back answering "not an edge system" and stayed
  # that way until someone edited the file by hand (found live, 2026-09-03).
  install -Dm644 /dev/stdin /usr/share/w/vendor/etc-w/update.conf <<EOF
# /etc/w/update.conf — W Linux update channel (read by w-sync). Vendor default.
CHANNEL=$channel
REF=$ref
VERIFY_SIGNATURE=$verify
SITE_REPO=$site_repo
SITE_REF=$site_ref
SITE=$site_profile
EOF

  # Seed the live config once (seed-if-absent), reflecting the detected channel.
  if [[ ! -e /etc/w/update.conf ]]; then
    info "Seeding /etc/w/update.conf (channel: $channel, ref: $ref, verify: $verify)..."
    install -Dm644 /dev/stdin /etc/w/update.conf <<EOF
# /etc/w/update.conf — W Linux update channel selection (read by w-sync).
#   CHANNEL  edge  → track the git repo in /var/lib/w/src via w-sync.
#            stable→ receive W as the w-system pacman package (default).
#   REF      the branch or tag the edge channel follows.
#   VERIFY_SIGNATURE  yes → w-sync pulls only a tip carrying a release tag signed by
#            a key in /usr/share/w/update/w-release.allowed_signers, and refuses
#            outright otherwise. Set to 'no' only for a checkout that tracks
#            something other than the official W repository (a fork, or a
#            development branch), where there are no signed release tags to find.
#            Turning it off on a machine that tracks the real repo means an update
#            is trusted because it arrived, which is not a reason.
#   SITE_REPO  optional git URL of a FLEET overlay repo: per-profile
#            /etc/w/site-defaults.d (fleet defaults, below the local admin) and
#            /etc/w/policy.d (fleet mandate, locks the key). Empty = no fleet,
#            and nothing about the site layer exists on this machine.
#   SITE_REF / SITE  the overlay's branch and which profile directory applies.
CHANNEL=$channel
REF=$ref
VERIFY_SIGNATURE=$verify
SITE_REPO=$site_repo
SITE_REF=$site_ref
SITE=$site_profile
EOF
  else
    info "/etc/w/update.conf exists — leaving channel selection untouched."
    # …with one exception, and only for a key that is ABSENT: a value already in the
    # file is admin state and is never touched. Machines installed before signing
    # existed have no VERIFY_SIGNATURE line, so they inherit w-sync's default (yes).
    # That is the right answer on the official repository and the wrong one on a
    # checkout that tracks anything else — a fork, or the dev repo, whose branch is an
    # ordinary history with no release tags at all: every update there would be
    # refused, and the update delivering the new w-sync is the last one that could
    # still have fixed it. So the same derivation the seed uses is written once here.
    # It cannot weaken a machine: what it writes is exactly what a fresh install of
    # the same checkout would have been given, and on the official repo it equals the
    # default it replaces.
    if ! grep -qE '^[[:space:]]*VERIFY_SIGNATURE=' /etc/w/update.conf; then
      info "Recording VERIFY_SIGNATURE=$verify (absent — this install predates release signing)."
      cat >> /etc/w/update.conf <<EOF

# Added by mod_updatesys: this install predates release signing. 'yes' = w-sync
# pulls only a tip whose vX.Y.Z tag is signed by a key in
# /usr/share/w/update/w-release.allowed_signers. Derived from the tracked remote.
VERIFY_SIGNATURE=$verify
EOF
    fi
  fi

  # Periodic edge check (per-user timer, like w-update-check). Only meaningful on
  # edge, so only enable it there; the units ride --rootfs. Guard on presence so a
  # standalone --updatesys before --rootfs warns instead of failing silently.
  if [[ "$channel" == edge ]]; then
    if [[ -f /etc/systemd/user/w-sync-check.timer ]]; then
      systemctl --global enable w-sync-check.timer
      # Seed the machine-wide state now, as root on the owner's behalf. Without this
      # the Hub shows "unknown" until the first timer tick 6h later — on a fresh
      # install, and on a machine migrating off the old per-user file (the update that
      # brings this change still has the OLD w-sync in memory, so its own closing
      # check writes the dead path). Never fatal: a state file that admits it does not
      # know is exactly what phase 1 built.
      w-sync check || true
      info "Edge channel active. Sync: w-sync; check timer every 6h. See 'w-sync status'."
    else
      echo "  WARN: w-sync-check.timer not found — run 'apply.sh --rootfs' first."
    fi
  else
    info "Stable channel — w-sync inert (W arrives via the w-system package)."
  fi
}
