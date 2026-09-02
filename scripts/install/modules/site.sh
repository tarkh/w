# modules/site.sh — the fleet (site) overlay: /etc/w/site-defaults.d + /etc/w/policy.d.
# apply.sh context: runs on the live system as root, post-boot.
#
# What this delivers (update-system.md, decision 6 + w-conf.md "layers"):
#   site-defaults.d — the fleet's DEFAULTS. Below the local admin, so a machine
#                     that decided otherwise keeps its decision (locality holds).
#   policy.d        — the fleet's MANDATE. Above everything, and it LOCKS the key:
#                     w-conf's setters refuse it, the Hub greys the control out,
#                     the AI tools explain instead of prompting.
#
# Where it comes from: a small git repo of its own, named by SITE_REPO in
# /etc/w/update.conf, holding one directory per profile:
#
#   <profile>/etc/w/site-defaults.d/<subsys>.conf
#   <profile>/etc/w/policy.d/<subsys>.conf
#
# A SEPARATE repo, not a directory inside W: once W is public, the owner of a
# fleet has no write access to it, and forking W to express configuration would
# put a group's settings into the vendor layer — the very "one file, two owners"
# collision the whole layered-config work exists to remove (a fork would then
# conflict on every release that improves a default, which is now by design).
# Profiles cover groups WITHIN one fleet without branching any code.
#
# Deliberately data, never code: the layer only ever carries single-line KEY=value
# files that W's reader parses (no $(…), no sourcing). Whoever runs a site can
# steer the machines' configuration without gaining arbitrary execution on them.
#
# Unset SITE_REPO (the default, and every single-machine install) makes this a
# no-op: no clone, no directories, nothing to learn. Hand-placed files in those
# two directories keep working — they are a legitimate way to pin one machine.

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

SITE_DIR="/var/lib/w/site"

# Subsystems whose effective values are RENDERED into something else, so a new
# policy is inert until they re-render. "Copying a file is not activating it" —
# the same rule sync-map states for the vendor layer. Anything not listed here
# (terminal, crypt, ai) is read at use time and needs nothing.
#
# power and nightlight render into HOMES, so their re-render is per-account
# (_site_render_users below): a mandate that reaches one of three accounts is
# worse than one that reaches none, because it looks applied.
_site_render() { # <subsys>
  case "$1" in
    power) w-power apply  >/dev/null 2>&1 || echo "  WARN: w-power apply failed"
           _site_render_users w-power _render-user ;;
    # No machine-scope half at all: every nightlight key is user scope.
    nightlight) _site_render_users w-nightlight apply ;;
    dns)   w-dns   apply  >/dev/null 2>&1 || echo "  WARN: w-dns apply failed" ;;
    time)  w-time  apply  >/dev/null 2>&1 || echo "  WARN: w-time apply failed" ;;
    logs)  w-logs  apply  >/dev/null 2>&1 || echo "  WARN: w-logs apply failed" ;;
    *)     : ;;
  esac
}

# Re-render a home-rendering subsystem for every account of the machine — the
# same loop mod_power/mod_nightlight run on the ordinary apply path
# (update-system.md phase 5). Without it a fleet policy would land in the files
# but change nothing for anyone except the account the render happened to pick.
_site_render_users() { # <cli> <args...>
  local cli="$1"; shift
  local -a wusers=(); local entry wuser
  mapfile -t wusers < <(w_home_users)
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"
    "$cli" --user "$wuser" "$@" >/dev/null 2>&1 \
      || echo "  WARN: $cli failed for $wuser"
  done
}

# Names of the subsystems currently covered by either overlay directory.
_site_subsys_present() {
  local d f
  for d in /etc/w/site-defaults.d /etc/w/policy.d; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*.conf; do
      [[ -f "$f" ]] && basename "$f" .conf
    done
  done
  return 0
}

# Fetch (or clone) the site repo. Never destructive on failure: an unreachable
# repo must leave the last known policy in force, not silently drop it.
_site_fetch() { # <url> <ref>
  local url="$1" ref="$2" cur
  if [[ -d "$SITE_DIR/.git" ]]; then
    cur="$(git -C "$SITE_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$cur" != "$url" ]]; then
      ui_info "Site repo URL changed — re-cloning."
      rm -rf "$SITE_DIR"
    fi
  fi
  if [[ ! -d "$SITE_DIR/.git" ]]; then
    install -d -m755 "$(dirname "$SITE_DIR")"
    git clone --quiet --branch "$ref" "$url" "$SITE_DIR" || {
      echo "  WARN: cannot clone the site repo ($url) — keeping the current overlay."
      rm -rf "$SITE_DIR"; return 1; }
  else
    # `reset --hard`, unlike the W checkout's `pull --ff-only`: nothing local ever
    # edits this tree, it is a pure mirror of the fleet's policy — so a corrected
    # force-push must land instead of wedging every machine on a diverged branch.
    git -C "$SITE_DIR" fetch --quiet --prune origin "$ref" || {
      echo "  WARN: cannot reach the site repo — keeping the current overlay."; return 1; }
    git -C "$SITE_DIR" reset --quiet --hard FETCH_HEAD || return 1
  fi
  # Credentials may be embedded in the URL, exactly like the edge checkout.
  [[ -f "$SITE_DIR/.git/config" ]] && chmod 600 "$SITE_DIR/.git/config"
  return 0
}

# Mirror ONE overlay directory. --delete is the point, not an optimisation:
# a policy that cannot be revoked by deleting its file would leave every machine
# permanently locked, and the two directories are W's alone, so mirroring them is
# safe. An absent source directory means "the profile carries none" → empty it.
_site_mirror() { # <src dir|""> <dst dir>
  local src="$1" dst="$2" empty=""
  install -d -m755 "$dst"
  if [[ -z "$src" || ! -d "$src" ]]; then
    empty="$(mktemp -d)"; src="$empty"
  fi
  # `.git*` is the repo's own bookkeeping, not configuration — a `.gitkeep` placed to
  # keep an emptied profile trackable has no business landing in /etc/w.
  # `--delete-excluded`, not plain `--delete`: an excluded name is otherwise PROTECTED
  # on the receiving side, so a `.gitkeep` that arrived before the exclude existed
  # would sit in /etc/w forever.
  rsync -a --delete --delete-excluded --exclude='.git*' \
    --chmod=F644,D755 --chown=root:root "$src/" "$dst/"
  [[ -n "$empty" ]] && rmdir "$empty"
  return 0
}

mod_site() {
  local lib=/usr/lib/w/w-conf-lib.sh
  if [[ ! -r "$lib" ]]; then
    echo "  WARN: $lib missing — run apply.sh --rootfs first; skipping the site overlay."
    return 0
  fi
  # shellcheck source=../../../rootfs/usr/lib/w/w-conf-lib.sh
  source "$lib"

  # `update` is the one subsystem deliberately NOT split (only w-sync reads it),
  # so its keys are read from the system layer, per the rule in w-conf.md.
  local url ref profile
  url="$(wconf_layer_get update system SITE_REPO)"
  ref="$(wconf_layer_get update system SITE_REF)";   ref="${ref:-main}"
  profile="$(wconf_layer_get update system SITE)";   profile="${profile:-default}"

  if [[ -z "$url" ]]; then
    ui_info "No site overlay configured (SITE_REPO unset in /etc/w/update.conf) — nothing to do."
    return 0
  fi
  command -v git >/dev/null || { echo "  WARN: git missing — skipping the site overlay."; return 0; }

  ui_info "Syncing site overlay (profile '$profile' from $url)..."
  _site_fetch "$url" "$ref" || return 0

  # Existence is judged on the PROFILE directory, not on its etc/w: git cannot track
  # an empty directory, so deleting a profile's last policy file also deletes
  # `<profile>/etc/w`. Judging by that path would turn "revoke everything" into
  # "leave the mandate in force forever" — the one outcome this layer must never
  # produce. A profile that exists but carries nothing therefore mirrors EMPTY.
  local src="$SITE_DIR/$profile/etc/w"
  if [[ ! -d "$SITE_DIR/$profile" ]]; then
    # A mistyped SITE= must not silently strip a fleet's policy either, so this
    # case leaves the deployment alone — and says how to revoke on purpose.
    echo "  WARN: profile '$profile' is not in the site repo — overlay left untouched."
    echo "        (Typo protection. To REVOKE a profile's policy, keep its directory in the"
    echo "         repo — e.g. an empty '$profile/etc/w/policy.d/.gitkeep' — so it can be"
    echo "         mirrored as empty.)"
    return 0
  fi

  # Re-render the union of what the overlay covered BEFORE and AFTER: a revoked
  # policy changes the effective value just as much as a new one does.
  local before after subs
  before="$(_site_subsys_present)"
  _site_mirror "$src/site-defaults.d" /etc/w/site-defaults.d
  _site_mirror "$src/policy.d"        /etc/w/policy.d
  after="$(_site_subsys_present)"

  subs="$(printf '%s\n%s\n' "$before" "$after" | sort -u | sed '/^$/d')"
  if [[ -n "$subs" ]]; then
    ui_info "  overlay covers: $(tr '\n' ' ' <<<"$subs")— re-rendering"
    local s
    while IFS= read -r s; do [[ -n "$s" ]] && _site_render "$s"; done <<<"$subs"
  fi
  ui_info "Site overlay applied. Inspect a value: w-conf cat <subsys> (layer 'site-default' / 'policy')."
}
