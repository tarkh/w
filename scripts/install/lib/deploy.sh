# deploy.sh — config-ownership deploy SDK (managed vs user layers).
#
# Backbone of update-system.md's ös 3 (config ownership). W splits home config
# into two layers with different deploy semantics:
#   • MANAGED — W-owned, overwritten every apply (w-style renders, QML tree, …).
#     Deployed by the modules themselves as before (install/rsync overwrite).
#   • USER    — user-owned behavioural config, seed-if-absent: written only when
#     the destination doesn't exist, so a user's edits survive re-apply.
#
# Both layers are delivered to EVERY human account of the machine, not just the
# first one — the modules iterate `w_home_users` below. The two semantics do the
# rest: a managed file is refreshed for everyone, a user file appears only where
# it is missing, so nobody's edits are touched.
#
# The USER layer is declared per module in a manifest — the single source of
# truth (deploy iterates it; w-reset and drift-detection will reuse the same
# paths, so no parallel list ever drifts):
#
#   /usr/share/w/update/<module>.manifest   (ships via apply_rootfs)
#
# In apply context the repo IS the truth, so we read the manifest and the
# pristine skel copy straight from $SRC (always fresh, matches what apply_rootfs
# would ship). w-reset (later phase) reads the deployed /usr/share/w copy so it
# works offline on a client without the repo.
#
# Manifest format — TSV, `#` comments and blank lines ignored:
#   <home-relative-path>\t<class>
# class:
#   user     — seed-if-absent (phase 1; the only branch acted on here)
#   managed  — force re-deploy    (reserved for w-reset)
#   override — restore vendor cfg (reserved for w-reset)

# ── Who gets user config ──────────────────────────────────────────────────────
# Every home-deploying module used to resolve ONE "primary user" (first account in
# the uid-1000 range) and write only there. Additional accounts got their config
# from /etc/skel once, at useradd time, and no update ever revisited them — a
# second administrator kept looking at the shell/Hub that shipped the day their
# account was created (update-system.md, phase 4). The fix is not a new ownership
# class: it is applying the existing contract to everyone it was always meant for.
#
# "A W user" = uid 1000..65533 (the login range; 65534 is `nobody`) AND a real
# login shell (nologin/false = a service account that happens to sit in the range)
# AND an existing home of its own — not `/`, and owned by that account. The
# ownership check is the load-bearing one: every caller follows up with
# `install -d -o` / `rsync --chown` into that path, so an account pointing at a
# shared directory would hand it away.
#
# Deliberately NOT part of the rule: group membership (a non-admin needs the
# desktop config just as much as an admin) and "already has ~/.config/quickshell"
# (that is the very thing being delivered — a fresh account would never qualify).
#
# W_PASSWD is a test seam (unit tests point it at a fixture); prod = /etc/passwd.

# _home_owned_by <dir> <user> — own function so unit tests can shadow it: `stat`
# is an external, and a test tmpdir belongs to whoever runs bats, not to "alice".
_home_owned_by() { [[ "$(stat -c %U "$1" 2>/dev/null)" == "$2" ]]; }

# w_home_users — print "<user>\t<home>" per W human account, in /etc/passwd order.
w_home_users() {
  local u uid home shell
  while IFS=: read -r u _ uid _ _ home shell; do
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    (( uid >= 1000 && uid < 65534 )) || continue
    case "$shell" in ''|*/nologin|*/false|*/sync) continue ;; esac
    [[ -n "$home" && "$home" != / && -d "$home" ]] || continue
    _home_owned_by "$home" "$u" || continue
    printf '%s\t%s\n' "$u" "$home"
  done < "${W_PASSWD:-/etc/passwd}"
}

# seed_user_file <src> <dst> <user> [home]
# Copy <src> to <dst> only if <dst> is absent, owned by <user>, creating and
# re-owning any missing parent dirs up the chain (install -D makes parents
# root-owned, which breaks later user-scope writes — same trap mod_shell guards).
#
# <home> is optional and defaults to the conventional ${W_HOME_BASE:-/home}/<user>.
# Pass it whenever the real home is known (w_home_users reports it, and w-pack
# gets it from getent): the parent-owning loop below has to walk the ACTUAL home,
# and a guess that misses would silently create directories somewhere else while
# leaving the real parents root-owned — i.e. the guard would quietly stop
# guarding, which is worse than not having it.
seed_user_file() {
  local src="$1" dst="$2" user="$3"
  # Separate statement on purpose: bash expands every word of a `local` command
  # before assigning any of them, so a default referring to $user on the same
  # line reads it while it is still the freshly-declared (unset) local — which
  # `set -u` turns into an abort.
  local home="${4:-${W_HOME_BASE:-/home}/$user}"
  [[ -e "$dst" ]] && return 0
  [[ -f "$src" ]] || { echo "  WARN: skel source missing, skipping: $src"; return 0; }

  # Own every parent dir from the home root down (idempotent; also re-owns dirs a
  # previous root-owned deploy left behind). `install -D` alone would create them
  # root-owned, breaking later user-scope writes — the trap mod_shell guards.
  # W_HOME_BASE is a test seam (unit tests point it at a tmpdir); prod = /home.
  local acc part rel="${dst#"$home/"}"
  if [[ "$rel" == "$dst" ]]; then
    # dst is not under home: the caller contradicts itself. Refuse to walk a
    # phantom chain (that is how stray root-owned trees get created) and just
    # place the file.
    echo "  WARN: $dst is outside $user's home ($home) — parent ownership not adjusted"
  elif [[ "$rel" == */* ]]; then        # skip for top-level files (parent = home)
    acc="$home"
    local IFS=/
    for part in ${rel%/*}; do
      acc="$acc/$part"
      install -d -o "$user" -g "$user" "$acc"
    done
    unset IFS
  fi

  install -Dm644 -o "$user" -g "$user" "$src" "$dst"
}

# deploy_user_manifest <module> <user> [home]
# Seed every USER-class path in the module manifest into the user's home.
# Managed/override classes are no-ops here (reserved for w-reset).
deploy_user_manifest() {
  local module="$1" user="$2"
  local manifest="$SRC/rootfs/usr/share/w/update/$module.manifest"
  local skel="$SRC/rootfs/etc/skel"
  local home_dir="${3:-${W_HOME_BASE:-/home}/$user}"

  [[ -f "$manifest" ]] || die "manifest not found: $manifest"

  info "Seeding user-owned $module config (seed-if-absent) from manifest..."
  local path class
  # `|| [[ -n $path ]]` so a final line without trailing newline is still read.
  while read -r path class || [[ -n "$path" ]]; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ "$class" == "user" ]] || continue
    seed_user_file "$skel/$path" "$home_dir/$path" "$user" "$home_dir"
  done < "$manifest"
}

# ── Theme render artifacts (the third layer) ──────────────────────────────────
# Besides MANAGED and USER there is content no deploy may own: the per-user output
# of `w-style` (quickshell/core/*.json, hypr/*.lua, kdeglobals, qt/Kvantum, shell
# colours…). It is not W-owned static content — it is a FUNCTION of the account's
# active theme, so skel's copy is only ever right for whoever runs the baseline
# theme `w`. Copying it into a live home is how an edge update used to reset a
# custom theme to W's default: the shell reverted to the `w` palette while the
# rest of the desktop (rendered elsewhere, untouched by that module) kept the
# user's — visible as "the bar lost my theme". Switching themes fixed it because
# only `w-theme` re-renders; there is no login render.
#
# So the modules stop shipping those paths (see mod_quickshell/mod_hyprland) and
# apply.sh re-renders them here, once, at the end of every run. Central on purpose:
# a per-module hook is a registry to forget, and forgetting is silent — the same
# failure mode sync-map's routing check exists to prevent.
#
# W_STYLE_BIN is a test seam (unit tests point it at a stub); prod = w-style.

# w_render_user_theme <user> [home]
# Re-render every user-scope theme axis AS that user. Root's own `w-style apply
# user` writes to /etc/skel (core.sh), never to a home, so runuser is not an
# optimisation here — it is the only thing that renders a real account.
w_render_user_theme() {
  local user="$1"
  local home_dir="${2:-${W_HOME_BASE:-/home}/$user}"
  local style="${W_STYLE_BIN:-w-style}"
  command -v "$style" >/dev/null 2>&1 || return 0

  # W_RUNTIME_BASE is a test seam (unit tests point it at a tmpdir); prod = /run/user.
  local uid runtime his
  uid="$(id -u "$user" 2>/dev/null)" || return 0
  runtime="${W_RUNTIME_BASE:-/run/user}/$uid"

  # `runuser` keeps the CALLER's environment except HOME/SHELL/USER/LOGNAME — so
  # over a root SSH session the axes would inherit root's XDG_RUNTIME_DIR and
  # DBUS_SESSION_BUS_ADDRESS and push gsettings at the wrong bus. Point both at
  # the target user when they have a runtime dir, drop them when they don't (no
  # session → the live channels are meant to skip, and they test these vars).
  # Hyprland fragments (colors/animations/effects/geometry.lua) only reach the
  # running compositor through `hyprctl reload`, which needs the instance
  # signature. `|| true`: the glob fails when no session is up, and a failing
  # command substitution under pipefail would abort the whole apply.
  his=""
  [[ -d "$runtime" ]] && { his="$(ls -dt "$runtime"/hypr/* 2>/dev/null | head -1)" || true; }

  # Three cases, and the middle one used to be wrong. The signature is UNSET
  # unless this user has a Hyprland session of their own — including when they
  # have a runtime dir but no compositor in it. That branch previously rebuilt the
  # array from scratch and so dropped the `-u`, leaving the CALLER's signature to
  # be inherited: an apply run from a live session handed its own compositor's
  # signature to somebody else's `w-style apply user`, whose hyprctl reload then
  # addressed the wrong instance. Invisible until check.sh first ran on a machine
  # that had a session at all — deploy.bats has always asserted `HIS: <unset>`
  # here, and on a session-less host the assertion passed for the wrong reason.
  # `-u` comes first in every branch: env takes options before assignments.
  local -a sessenv=(-u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS -u HYPRLAND_INSTANCE_SIGNATURE)
  if [[ -d "$runtime" && -n "$his" ]]; then
    sessenv=(XDG_RUNTIME_DIR="$runtime" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
             HYPRLAND_INSTANCE_SIGNATURE="$(basename "$his")")
  elif [[ -d "$runtime" ]]; then
    sessenv=(-u HYPRLAND_INSTANCE_SIGNATURE \
             XDG_RUNTIME_DIR="$runtime" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus")
  fi

  # Non-fatal: a broken render must not abort an update mid-way (set -e), and the
  # WARN is what a later drift/diagnostic run greps for.
  runuser -u "$user" -- env "${sessenv[@]}" HOME="$home_dir" "$style" apply user \
    || echo "  WARN: w-style apply user failed for $user — theme artifacts may be stale."
}

# w_render_user_themes — w_render_user_theme for every human account.
w_render_user_themes() {
  local -a wusers=(); local entry
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || return 0
  info "Re-rendering per-user theme artifacts..."
  for entry in "${wusers[@]}"; do
    w_render_user_theme "${entry%%$'\t'*}" "${entry#*$'\t'}"
  done
}

# ── Per-account state outside @home snapshots ───────────────────────────────
#
# w_home_subvol <dir> <owner> — make <dir> a nested btrfs subvolume owned by
# <owner>, so it rides OUTSIDE @home snapshots: snapper's snapshots are
# non-recursive, so a nested subvolume is excluded natively. For the large,
# ephemeral, network-recoverable state a toolchain keeps per user (uv/pip
# download caches, Go's module + build cache, …) — the profile that has no
# business in a rollback. Acts only while the path is ABSENT: a populated
# directory cannot be converted in place, so an existing one is left as it is
# (WARN — it will ride in @home snapshots). Best-effort: off btrfs, or when the
# create fails, a plain directory is made so the caller's tool still works.
# Which paths — /usr/share/w/defaults/home-subvols (mod_homesubvol); the W-Packs
# per-user layer carves its own (dev → mise) with the same rules.
w_home_subvol() {
  local dir="$1" owner="$2"
  if [[ ! -e "$dir" ]]; then
    if btrfs subvolume create "$dir" >/dev/null 2>&1; then
      chown "$owner:$owner" "$dir"
      info "Created nested subvolume $dir (excluded from @home snapshots)."
    else
      install -d -o "$owner" -g "$owner" "$dir"
      echo "  WARN: $dir not on btrfs (or subvolume create failed) — plain dir, no snapshot exclusion."
    fi
  elif btrfs subvolume show "$dir" >/dev/null 2>&1; then
    info "$dir already a subvolume — nothing to do."
  else
    echo "  WARN: $dir already exists as a regular dir — leaving as-is (will ride in @home snapshots)."
  fi
}

# w_home_subvols_read <registry> — print the home-relative paths a registry
# lists, one per line; `#` comments (whole-line or trailing) and blanks dropped.
w_home_subvols_read() {
  sed 's/#.*//; s/[[:space:]]*$//; /^$/d' "$1"
}
