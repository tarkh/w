#!/usr/bin/env bash
# containers bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup containers` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Rootless containers are per-account by their very nature: the engine, the socket,
# the image store and the UID mapping all belong to one user. That is why nearly
# the whole bundle lives here and setup.sh has almost nothing left — and why a
# machine-wide "installed" was such a misleading answer to give a second account.
#
# Works in every context: firstboot (root, the account not logged in), a later
# `sudo w-pack install containers`, and an account catching itself up with no root.
# Idempotent; best-effort. See pack-containers.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"
USER_UID="$(id -u "$USER_NAME")"
RUNDIR="/run/user/$USER_UID"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root when invoked over
# sudo/ssh, or a service dir at firstboot) the target user cannot chdir there and
# tools like `podman` fail with "cannot chdir". Move to the user's own home so every
# as_user call runs from an accessible cwd.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Run a command as the target user with a usable session env (user bus + runtime
# dir), independent of whether they are logged in. When we ARE that user already,
# run directly — their own session env is the right one.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$RUNDIR" "$@"
  else "$@"; fi
}

# ── 1. Linger + user systemd manager ─────────────────────────────────────────
# Linger keeps the user manager (and podman.socket) alive without an active login,
# so quadlet DB services start at boot.
#
# As root this is unconditional. As the account itself it goes through polkit's
# org.freedesktop.login1.set-self-linger, which Arch grants to an ACTIVE session
# without a prompt — so it succeeds from a desktop session and can legitimately
# fail over a bare SSH login. Say which, rather than failing quietly.
info "Enabling linger for $USER_NAME..."
if loginctl enable-linger "$USER_NAME" 2>/dev/null; then
  info "Linger enabled."
elif [[ "$AS_ROOT" == 1 ]]; then
  warn "enable-linger failed"
else
  warn "could not enable linger from this session (polkit grants it to an active"
  warn "  desktop session; over plain SSH it is refused). Containers still work"
  warn "  while you are logged in. To make them start at boot, run once:"
  warn "    sudo loginctl enable-linger $USER_NAME"
fi

# Bring the manager up now so the `systemctl --user` calls below work during
# firstboot, when the account has no session yet. Root-only, and only needed then.
if [[ "$AS_ROOT" == 1 ]]; then
  systemctl start "user@${USER_UID}.service" 2>/dev/null || warn "could not start user@${USER_UID} manager"
fi

# ── 2. Podman API socket (rootless Docker-compat) ────────────────────────────
# One socket serves lazydocker + docker-compose + testcontainers; DOCKER_HOST is
# exported by the env.d drop-in. --now if the manager is reachable, else the
# persistent enable brings it up at next login / linger start.
info "Enabling podman.socket for $USER_NAME..."
if [[ -d "$RUNDIR" ]]; then
  as_user systemctl --user enable --now podman.socket || warn "podman.socket enable --now failed"
else
  as_user systemctl --user enable podman.socket || warn "podman.socket enable failed (starts at next login)"
fi

# ── 3. Rootless storage as a nested btrfs subvolume (snapshot exclusion) ──────
# ~/.local/share/containers must be OUTSIDE @home snapshots: it is large and
# ephemeral, and btrfs snapshots are non-recursive, so a nested subvolume is
# naturally excluded (snapshots.md). Must exist as a subvolume BEFORE podman's
# first run — an existing populated dir cannot be converted, so we only act when
# absent.
STORE="$USER_HOME/.local/share/containers"
info "Ensuring rootless container store is snapshot-excluded..."
if [[ "$AS_ROOT" == 1 ]]; then install -d -o "$USER_NAME" -g "$USER_NAME" "$USER_HOME/.local/share"
else install -d "$USER_HOME/.local/share"; fi
if [[ ! -e "$STORE" ]]; then
  # Subvolume creation is permitted for whoever may write the parent directory, so
  # this works for an account catching itself up, not only for root.
  if as_user btrfs subvolume create "$STORE" >/dev/null 2>&1; then
    [[ "$AS_ROOT" == 1 ]] && chown "$USER_NAME:$USER_NAME" "$STORE"
    info "Created nested subvolume $STORE (excluded from @home snapshots)."
  else
    if [[ "$AS_ROOT" == 1 ]]; then install -d -o "$USER_NAME" -g "$USER_NAME" "$STORE"
    else install -d "$STORE"; fi
    warn "not on btrfs (or subvolume create failed) — plain dir; no snapshot exclusion"
  fi
elif btrfs subvolume show "$STORE" >/dev/null 2>&1; then
  info "$STORE already a subvolume — nothing to do."
else
  warn "$STORE already exists as a regular dir — leaving as-is (will ride in @home snapshots)"
fi

# ── 4. subuid/subgid ranges (rootless user namespaces) ───────────────────────
# Modern useradd (shadow ≥4.11.1-3) assigns these; verify the account got a range.
# Adding one is genuinely root's call (usermod edits /etc/subuid), so when an
# account catches itself up we name the exact command instead of failing — a
# silent skip here would leave rootless podman broken for reasons nobody can see.
info "Verifying subuid/subgid ranges..."
if ! grep -q "^${USER_NAME}:" /etc/subuid || ! grep -q "^${USER_NAME}:" /etc/subgid; then
  if [[ "$AS_ROOT" == 1 ]]; then
    warn "no subuid/subgid range for $USER_NAME — adding 100000-165535"
    usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER_NAME" \
      || warn "usermod failed — rootless containers may not map UIDs"
    as_user podman system migrate >/dev/null 2>&1 || true
  else
    warn "$USER_NAME has no subuid/subgid range — rootless containers cannot map UIDs."
    warn "  Only an administrator can grant one. Ask them to run:"
    warn "    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER_NAME"
    warn "  then re-run: w-pack setup containers"
  fi
fi

# ── 5. Offline verification (no network pull during firstboot) ───────────────
# `docker run hello-world` is a manual check documented in ai/SKILL.md — pulling an
# image at firstboot would add latency and fail without network. Here we only
# confirm the engine initialises for the account.
info "Verifying podman for $USER_NAME (offline)..."
if as_user podman info >/dev/null 2>&1; then
  info "podman OK. Docker-compat: 'docker ps' (DOCKER_HOST set at next login)."
else
  warn "podman info did not succeed yet — will initialise on first user login"
fi

info "containers user setup complete for $USER_NAME."
exit 0
