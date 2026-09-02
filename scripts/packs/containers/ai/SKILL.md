---
name: containers
description: >-
  Operating containers on W Linux with the `containers` W-Pack: Podman rootless, a
  Docker-compatible CLI + API socket, and lazydocker. Load this when the user works
  with containers and `w-pack status containers` reports installed.
---

# W-Pack: containers

Operating containers on W Linux. This bundle installs **Podman rootless** with a
**Docker-compatible** CLI and API socket, plus **lazydocker** (TUI). Curated into
`/usr/share/w/ai/skills/containers/` when the bundle is installed. Present only if
`w-pack status containers` reports installed.

## What the user has

- **Engine:** Podman, rootless + daemonless. No `docker` daemon, no `docker` group.
- **Docker compat:** `podman-docker` provides a real `docker` command; the Docker API
  is served by the per-user `podman.socket`. `DOCKER_HOST` is exported in the session
  (via `/etc/w/env.d/containers.sh`), so `docker`, `docker compose`, lazydocker and
  testcontainers all work against Podman. `DOCKER_BUILDKIT=0` is set (required for
  compose↔Podman).
- **TUI:** `lazydocker` (themed by w-style axis `500-lazydocker`).
- **Storage:** native overlay driver under `~/.local/share/containers`, a nested
  btrfs subvolume excluded from `@home` snapshots.
- **DNS:** aardvark-dns forwards to systemd-resolved on port **20053**
  (`/etc/containers/containers.conf.d/10-w.conf`) so the DoT/Quad9 stub on `:53` is
  untouched — do not change this without understanding security.md.

## Common operations

- Status / smoke test: `podman info`; `docker run --rm hello-world` (needs network).
- List / inspect: `docker ps -a`, `podman ps -a`, or launch `lazydocker`.
- Run a service: prefer a **quadlet** over `docker run` for anything long-lived.

## Running a database (quadlet pattern — recommended)

Declarative systemd user units, started at boot via linger (already enabled):

```
mkdir -p ~/.config/containers/systemd
cp /usr/share/w/packs/containers/quadlet/postgres.container ~/.config/containers/systemd/
# edit POSTGRES_PASSWORD, then:
systemctl --user daemon-reload
systemctl --user start postgres        # unit = <file stem>.service
```

Ports ≥1024 (5432/3306/6379) bind rootless without extra privilege. For `:80/:443`
the user must opt in via `net.ipv4.ip_unprivileged_port_start`.

## Gotchas

- **First socket:** if `docker ps` errors right after install, the user hasn't logged
  in since — `DOCKER_HOST` applies at next login, or start it now:
  `systemctl --user start podman.socket`.
- **compose:** BuildKit must stay off (`DOCKER_BUILDKIT=0`), already handled.
- **No rootful Docker:** there is no `docker` daemon or socket in `/var/run` — that is
  intentional. Do not suggest adding the user to a `docker` group.

## Reset / remove

- Config back to W default: `w-reset containers` (uses the bundle manifest).
- Bundle removal is a later phase (shared pacman deps) — do not `pacman -Rns` the
  stack manually without checking dependents.
