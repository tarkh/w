# modules/updatesys.sh — W Linux edge update client (apply.sh --updatesys)
# apply.sh context: runs on the live system as root, post-boot. Deploys the w-sync
# script + sync-map + check timer (they ride --rootfs too, but this module installs
# them itself so `--updatesys` alone is sufficient — sync-map routes changes to them
# here) and wires up the update
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
  if [[ -d "$repo/.git" ]]; then
    channel="edge"
    ref="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
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

  # Vendor default for `w-reset updatesys` (drop the override back to stable).
  install -Dm644 /dev/stdin /usr/share/w/vendor/etc-w/update.conf <<EOF
# /etc/w/update.conf — W Linux update channel (read by w-sync). Vendor default.
CHANNEL=stable
REF=main
SITE_REPO=
SITE_REF=main
SITE=default
EOF

  # Seed the live config once (seed-if-absent), reflecting the detected channel.
  if [[ ! -e /etc/w/update.conf ]]; then
    info "Seeding /etc/w/update.conf (channel: $channel, ref: $ref)..."
    install -Dm644 /dev/stdin /etc/w/update.conf <<EOF
# /etc/w/update.conf — W Linux update channel selection (read by w-sync).
#   CHANNEL  edge  → track the git repo in /var/lib/w/src via w-sync.
#            stable→ receive W as the w-system pacman package (default).
#   REF      the branch or tag the edge channel follows.
#   SITE_REPO  optional git URL of a FLEET overlay repo: per-profile
#            /etc/w/site-defaults.d (fleet defaults, below the local admin) and
#            /etc/w/policy.d (fleet mandate, locks the key). Empty = no fleet,
#            and nothing about the site layer exists on this machine.
#   SITE_REF / SITE  the overlay's branch and which profile directory applies.
CHANNEL=$channel
REF=$ref
SITE_REPO=$site_repo
SITE_REF=$site_ref
SITE=$site_profile
EOF
  else
    info "/etc/w/update.conf exists — leaving channel selection untouched."
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
