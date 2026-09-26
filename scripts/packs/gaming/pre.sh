#!/usr/bin/env bash
# gaming bundle — PREPARE step. Run by `w-pack install` BEFORE pkgs.txt, always
# as root with:
#   BUNDLE_NAME  BUNDLE_DIR
#
# Three things have to happen before the package layer even resolves:
#   1. multilib enabled in pacman.conf — steam/umu-launcher/lib32-* live there,
#      and it is off by default on Arch.
#   2. `pacman -Sy` — w-pack's package layer never syncs on its own (a stale db
#      merely 404s later); a brand-new repo needs an explicit sync or it is
#      empty to every subsequent pacman/yay call in this bundle.
#   3. The GPU-vendor lib32 stack (mesa/vulkan-*/nvidia-utils, picked by
#      w-gpu-lib.sh) — installed HERE, before pkgs.txt, because steam depends
#      on the virtual provider `lib32-vulkan-driver` and a non-interactive
#      resolver picks the alphabetically-first provider (lib32-nvidia-utils)
#      when more than one is installed — broken Vulkan on AMD/Intel. See
#      package-gpu.md / w-gpu-lib.sh / gaming-plan.md §pre.sh.
#
# Not run by `w-pack refresh` (packs.md: refresh is not a network operation) —
# w-pack's run_prepare already enforces that, nothing to do here.
#
# Idempotent; best-effort EXCEPT the lib32 vendor packages once multilib is
# live: those are the one step this bundle cannot silently skip (see §3
# above), so an official-repo install failure there is fatal. The AUR legacy
# branch (old NVIDIA cards only) stays best-effort like every other network
# step — a transient AUR miss should not brick the whole bundle forever.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

# ── 1. multilib repository ────────────────────────────────────────────────
PACMAN_CONF="/etc/pacman.conf"
if grep -qE '^\[multilib\]' "$PACMAN_CONF"; then
  info "multilib already enabled in $PACMAN_CONF."
elif grep -qE '^#\[multilib\]' "$PACMAN_CONF"; then
  info "Enabling multilib (uncommenting the stock section)..."
  # shellcheck source=/dev/null
  source /usr/lib/w/w-backup-lib.sh
  w_backup_init "" ""
  w_backup_path "$PACMAN_CONF"
  w_backup_summary
  # The stock file ships '#[multilib]' immediately followed by its own
  # '#Include = ...' line — uncomment exactly that pair, nothing else that
  # happens to start with '#'.
  sed -i -e '/^#\[multilib\]/{ s/^#//; n; s/^#// }' "$PACMAN_CONF"
  if ! grep -qE '^\[multilib\]' "$PACMAN_CONF"; then
    warn "uncommenting multilib did not take — check $PACMAN_CONF by hand."
  fi
else
  info "No multilib section found at all — appending one..."
  # shellcheck source=/dev/null
  source /usr/lib/w/w-backup-lib.sh
  w_backup_init "" ""
  w_backup_path "$PACMAN_CONF"
  w_backup_summary
  {
    echo ""
    echo "[multilib]"
    echo "Include = /etc/pacman.d/mirrorlist"
  } >> "$PACMAN_CONF"
fi

# ── 2. Sync — a brand-new repo is empty until this runs ──────────────────
info "Syncing package databases (new repo just enabled)..."
pacman -Sy || { warn "pacman -Sy failed — package resolution below may 404."; }

# ── 3. Vendor lib32 stack, matched to this machine's GPU ─────────────────
GPU_LIB="${W_GPU_LIB:-/usr/lib/w/w-gpu-lib.sh}"
# --asdeps on every install below is deliberate, not cosmetic: these packages
# are pulled in FOR steam/wine (pkgs.txt), not asked for by name. Marking them
# as dependencies means pacman's own -Rns on pkgs.txt's list (w-pack's
# `remove --packages`, which runs AFTER this script) automatically sweeps the
# whole vendor lib32 chain up as orphaned once its last consumer is gone — one
# atomic transaction, no separate removal code needed here. Verified live: as
# explicit installs, lib32-mesa's own dependency chain (lib32-libglvnd ->
# lib32-libva -> ... -> lib32-curl -> lib32-libngtcp2 -> lib32-gnutls) blocked
# pkgs.txt's lib32-gnutls removal with "breaks dependency" — a transaction
# pacman can only resolve if BOTH sides go together, which --asdeps gets for
# free instead of reimplementing pkgs.txt's own neighbour-subtraction here.
if [[ ! -r "$GPU_LIB" ]]; then
  warn "w-gpu-lib.sh missing — cannot detect GPU, installing generic lib32 only."
  pacman -S --needed --asdeps --noconfirm lib32-mesa lib32-vulkan-icd-loader \
    || { warn "generic lib32 install failed."; exit 1; }
else
  # shellcheck source=/dev/null
  source "$GPU_LIB"
  tokens="$(w_gpu_lib32_packages)"
  official=() aur=()
  for t in $tokens; do
    case "$t" in
      official:*) official+=("${t#official:}") ;;
      aur:*)      aur+=("${t#aur:}") ;;
    esac
  done

  if (( ${#official[@]} )); then
    info "Installing official lib32 packages: ${official[*]}..."
    pacman -S --needed --asdeps --noconfirm "${official[@]}" \
      || { warn "official lib32 install failed — Steam/Wine graphics will be broken."; exit 1; }
  fi

  if (( ${#aur[@]} )); then
    info "Installing AUR lib32 packages (legacy NVIDIA): ${aur[*]}..."
    build_user() { awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd; }
    if ! command -v yay >/dev/null 2>&1; then
      warn "yay not found — cannot install ${aur[*]} (legacy NVIDIA lib32 Vulkan will be missing). Retry: w-pack refresh gaming"
    else
      bu="$(build_user)"
      if [[ -z "$bu" ]]; then
        warn "no unprivileged build user — cannot install ${aur[*]}."
      else
        sudoers="/etc/sudoers.d/zzzz-w-gaming-pre-build"
        echo "$bu ALL=(ALL) NOPASSWD: ALL" > "$sudoers"
        chmod 440 "$sudoers"
        if visudo -cf "$sudoers" >/dev/null; then
          sudo -u "$bu" -H yay -S --needed --asdeps --noconfirm --removemake \
            --answerdiff None --answerclean None "${aur[@]}" \
            || warn "AUR lib32 install failed for: ${aur[*]} (legacy NVIDIA Vulkan will be missing). Retry: w-pack refresh gaming"
        else
          warn "generated build sudoers invalid — skipping AUR lib32 install."
        fi
        rm -f "$sudoers"
      fi
    fi
  fi
fi

info "gaming prepare step complete."
exit 0
