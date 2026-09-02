# aurbuild.sh — build AUR packages from source, for both contexts that need it.
#
# Two callers, one seam:
#   • scripts/build-iso.sh  — pre-bakes yay + the encrypted-path limine pair into
#     w-repo, running as the invoking (non-root) user.
#   • modules/limine.sh     — the live fallback when the target has no w-repo to
#     install those prebuilts from (the dev-VM apply path, and any repair run).
#
# They used to be different code — an inline makepkg loop here, `yay` there — so
# an upstream build break had to be found and fixed twice, and the target half
# swallowed the failure entirely (`|| true`). One implementation instead, with
# the Gradle rescue below as the reason it was worth unifying.
#
# Privilege model: makepkg refuses to run as root, so when we ARE root the build
# runs as an unprivileged user — and its dependencies are installed by us, in
# advance, through the w_pac seam. That is why `-s` (let makepkg sudo-install its
# own deps) is used only in the non-root case: as root the build user needs no
# sudoers entry at all, where the `yay` path this replaces had to mint a
# temporary NOPASSWD rule for every build.

# ── Pinned Gradle rescue ──────────────────────────────────────────────────────
# limine-mkinitcpio-hook (which bundles limine-entry-tool) and limine-snapper-sync
# both compile a GraalVM native-image driven by the SYSTEM gradle, hardcoded as
# `/usr/bin/gradle` in their PKGBUILDs. On 2026-08-19 Arch shipped gradle 9.7.0-1,
# whose distribution directory no longer carries the `gradle-public-api-legacy`
# module the graalvm buildtools plugin resolves — every build of both packages
# then died at CONFIGURATION time, one second in:
#     > Cannot find module 'gradle-public-api-legacy' in distribution directory
#       '/usr/share/java/gradle'.
# Upstream's own answer is "use 9.6.1 or 9.7.1" — 9.7.1 restores the jar (verified:
# it reappears as lib/api/gradle-public-api-legacy-9.7.1.jar). Arch will get there
# on its own, so the fix must be a rescue and not a permanent pin: build with the
# system gradle first (zero cost, and it is the version the AUR expects), and only
# when that fails fall back ONCE to the pinned distribution below.
#
# The fallback deliberately comes from services.gradle.org rather than from an Arch
# repo/archive: what broke was Arch's split-jar REPACKAGING of gradle, so a rescue
# that reaches for another Arch gradle is a rescue built on the layer that failed.
# extra-testing is rejected for a second reason — it is a moving target (the fix
# lives there today, an unrelated pre-release will live there tomorrow) and it is
# not reachable from a target machine at all.
#
# Bump this pair only if BOTH the system gradle and the pin fail; that is loud by
# construction, since the build dies instead of falling through.
W_GRADLE_RESCUE_VER="9.7.1"
W_GRADLE_RESCUE_SHA256="acd53f1edaf02f1a8ff99879f8a34b302661a057d9b063ae9e35b552f804d20a"

# Reporting shims resolved at CALL time, not at source time: apply.sh defines
# info() after it sources its modules, and the installer calls it ui_info().
_wa_info() {
  if   declare -F ui_info &>/dev/null; then ui_info "$@"
  elif declare -F info    &>/dev/null; then info "$@"
  else echo -e "\033[1;35m==>\033[0m $*"
  fi
}
_wa_warn() { echo "WARN: $*" >&2; }

# Resolve the first regular account to build as (same convention as the rest of
# the AUR handling in apply.sh).
_wa_build_user() { awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd; }

# Run a command in a package's build dir, as the build user when we are root.
# -H matters: makepkg and gradle both write under $HOME (~/.gradle), and without
# it they would inherit root's and fail unreadably.
_wa_run() {
  local dir="$1" builder="$2"; shift 2
  if [[ -n "$builder" ]]; then
    ( cd "$dir" && sudo -u "$builder" -H "$@" )
  else
    ( cd "$dir" && "$@" )
  fi
}

# Clone an AUR package repo, with retry+backoff — aur.archlinux.org intermittently
# 502s, and a single transient blip must not abort a whole ISO build or firstboot.
w_aur_clone() {
  local pkg="$1" dest="$2" tries=4 n=1
  while true; do
    git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$dest" && return 0
    (( n >= tries )) && return 1
    rm -rf "$dest"                    # a partial clone would block the retry
    _wa_info "clone failed (attempt $n/$tries), retrying in $((n * 5))s: $pkg"
    sleep $((n * 5))
    (( n++ ))
  done
}

# Stage the pinned Gradle distribution under $1 (once per run) and publish its bin
# dir in _WA_GRADLE_BIN. A global rather than an echoed path on purpose: this
# function also reports progress, and capturing it in a command substitution would
# fold those lines into the returned path — which silently yields a bogus PATH
# entry, so the retry falls back to the very system gradle it is rescuing us from.
# bsdtar, not unzip: libarchive is always present (pacman depends on it), unzip is
# not. The exec bit is re-applied by hand — a zip's mode bits are not load-bearing.
_WA_GRADLE_BIN=""
_wa_gradle_rescue() {
  local root="$1"
  local dir="$root/gradle-$W_GRADLE_RESCUE_VER"
  if [[ ! -x "$dir/bin/gradle" ]]; then
    local zip="$root/gradle.zip"
    mkdir -p "$root"
    _wa_info "Fetching pinned Gradle $W_GRADLE_RESCUE_VER (the system gradle cannot build this)..."
    curl -fsSL -o "$zip" \
      "https://services.gradle.org/distributions/gradle-${W_GRADLE_RESCUE_VER}-bin.zip" \
      || { _wa_warn "gradle rescue: download failed"; return 1; }
    echo "$W_GRADLE_RESCUE_SHA256  $zip" | sha256sum -c --status \
      || { _wa_warn "gradle rescue: checksum mismatch — refusing to build with it"; return 1; }
    bsdtar -xf "$zip" -C "$root" || { _wa_warn "gradle rescue: extract failed"; return 1; }
    rm -f "$zip"
    chmod 755 "$dir/bin/gradle" 2>/dev/null || true
    chmod -R a+rX "$dir"
  fi
  [[ -x "$dir/bin/gradle" ]] || { _wa_warn "gradle rescue: no gradle in $dir/bin"; return 1; }
  _WA_GRADLE_BIN="$dir/bin"
}

# Install a package's own depends+makedepends through the w_pac seam (root only).
# `makepkg --printsrcinfo` sources the PKGBUILD — it runs as the BUILD USER here,
# never as root. Version constraints are stripped: pacman takes plain targets.
_wa_install_deps() {
  local dir="$1" builder="$2"
  local -a deps=()
  mapfile -t deps < <(_wa_run "$dir" "$builder" makepkg --printsrcinfo 2>/dev/null \
    | sed -n 's/^[[:space:]]*\(make\)\?depends[^=]*=[[:space:]]*//p' \
    | sed 's/[<>=].*//' | sort -u)
  # base-devel/git are makepkg's own floor, not the package's, so they are not in
  # .SRCINFO — an installed system may well be missing both.
  deps+=(base-devel git)
  _wa_info "Installing build dependencies: ${deps[*]}"
  w_pac -S --needed --noconfirm "${deps[@]}"
}

# Build one package into $outdir. Attempt 1 uses whatever gradle the system has;
# on failure, attempt 2 retries with the pinned rescue. Neutralising the PKGBUILD's
# hardcoded `/usr/bin/gradle` is the whole patch — one substitution that stays
# valid across upstream PKGBUILD churn, because it only removes an absolute path
# and lets PATH decide. Packages with no gradle in them are unaffected by it.
_wa_one() {
  local pkg="$1" work="$2" outdir="$3" builder="$4"
  local dir="$work/$pkg"

  w_aur_clone "$pkg" "$dir" || { _wa_warn "$pkg: clone failed"; return 1; }
  # `if`, not `[[ … ]] && …`: the && list returns 1 when there is no build user,
  # and callers run under `set -e` (that shape has aborted apply.sh mid-module before).
  if [[ -n "$builder" ]]; then chown -R "$builder:$builder" "$dir"; fi

  # BUILDDIR/PKGDEST are pinned into this run's ephemeral tree. A user makepkg.conf
  # may hard-set either: a shared, persistent BUILDDIR lets a previous interrupted
  # build leave a stale VCS working copy whose git `alternates` point at a
  # since-deleted temp dir ("unable to normalize alternate object path", aborting
  # the extract of git sources), and a redirected PKGDEST would drop the built
  # packages somewhere we never look. Config wins over env, so these have to be
  # makepkg CLI args (applied after config load) rather than exported variables.
  local -a opts=(--noconfirm --needed)
  local -a envs=("BUILDDIR=$dir/build" "PKGDEST=$dir")
  if [[ -n "$builder" ]]; then
    _wa_install_deps "$dir" "$builder" || { _wa_warn "$pkg: dependency install failed"; return 1; }
  else
    opts+=(-s)
  fi

  if ! _wa_run "$dir" "$builder" makepkg "${opts[@]}" "${envs[@]}"; then
    grep -q '/usr/bin/gradle' "$dir/PKGBUILD" || {
      _wa_warn "$pkg: build failed and it does not use the system gradle — not a rescuable failure"
      return 1
    }
    _wa_gradle_rescue "$work/.gradle-rescue" || return 1
    _wa_info "Retrying $pkg with pinned Gradle $W_GRADLE_RESCUE_VER..."
    sed -i 's#/usr/bin/gradle#gradle#g' "$dir/PKGBUILD"
    # makepkg exports leftover VAR=value argv AFTER loading makepkg.conf, so this is
    # the one channel that reliably wins over both the config and the environment.
    _wa_run "$dir" "$builder" makepkg -f "${opts[@]}" "${envs[@]}" \
      "PATH=$_WA_GRADLE_BIN:$PATH" \
      || { _wa_warn "$pkg: build failed with the pinned Gradle too"; return 1; }
  fi

  local -a built=()
  mapfile -t built < <(ls "$dir"/*.pkg.tar.* 2>/dev/null)
  (( ${#built[@]} )) || { _wa_warn "$pkg: build reported success but produced no package"; return 1; }
  cp "${built[@]}" "$outdir/"
}

# w_aur_build <outdir> <pkgbase>… — clone, build, and drop the resulting package
# files into <outdir>. Every requested package is attempted; the return is non-zero
# if ANY of them failed, so <outdir> may legitimately hold a partial result. How
# loud that is stays the caller's call (build-iso.sh dies on it, mod_limine installs
# what it got and raises a CRITICAL only for the boot-path half).
w_aur_build() {
  local outdir="$1"; shift
  [[ -n "$outdir" && $# -gt 0 ]] || { _wa_warn "w_aur_build: usage: <outdir> <pkgbase>…"; return 2; }
  mkdir -p "$outdir"

  local builder=""
  if [[ $EUID -eq 0 ]]; then
    builder="$(_wa_build_user)"
    [[ -n "$builder" ]] || { _wa_warn "no unprivileged user to build AUR packages as"; return 1; }
  fi

  # /var/tmp, not /tmp: /tmp is tmpfs (RAM) on any systemd machine, and these builds
  # are enormous — each package unpacks its own ~1.2 GB GraalVM next to the rescue
  # Gradle. On an 8 GB VM the second package died mid-extract with "Disk quota
  # exceeded" against a 3.9 GB /tmp. /var/tmp is disk-backed by definition.
  local work rc=0 pkg
  work="$(mktemp -d -p /var/tmp)"
  chmod 755 "$work"   # mktemp -d is 0700; the build user has to get in here
  for pkg in "$@"; do
    _wa_info "Building $pkg from AUR..."
    # Keep going after a failure instead of breaking: these are independent packages
    # of unequal importance (on the Limine path one is the boot path and the other is
    # a snapshot feature), so a caller that can use a partial result must be given one.
    _wa_one "$pkg" "$work" "$outdir" "$builder" || rc=1
  done
  rm -rf "$work"
  return $rc
}
