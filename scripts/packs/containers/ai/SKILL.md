---
name: containers
description: >-
  Operating containers on W Linux with the `containers` W-Pack: Podman rootless, a
  Docker-compatible CLI + API socket, and lazydocker. Load this when the user works
  with containers — status, logs, finding and pulling an image, running a service
  (quadlet), compose, cleanup, troubleshooting — and `w-pack status containers`
  reports installed. Everything here is rootless: you run it yourself, no sudo.
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

## You are the AI layer of this bundle

There is no container MCP server and no `w_container_*` tool — by design.
Podman is rootless, so every operation below is an ordinary user command you
run through the shell with **no privilege prompt**; the knowledge here is what
makes you effective. Prefer `podman` (native) over `docker` (the shim) in what
you run yourself; both address the same rootless engine.

## Status and inspection

- Engine health: `podman info --format '{{.Host.Arch}} {{.Store.GraphDriverName}} {{.Host.RemoteSocket.Exists}}'`;
  smoke test `podman run --rm docker.io/library/hello-world` (needs network).
- Containers: `podman ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'`;
  one container: `podman inspect <name>`, `podman logs --tail 100 -f <name>`,
  `podman stats --no-stream`, `podman top <name>`, `podman exec -it <name> sh`.
- Images / volumes / networks: `podman images`, `podman volume ls`, `podman network ls`;
  disk: `podman system df`.
- Services (quadlets): `systemctl --user list-units 'podman*' '*.service' --all`;
  `systemctl --user status <name>`; `journalctl --user -u <name> -e`.
- Interactive overview for the user: `lazydocker`.

## Find → pull → run (the "install me X" request)

1. **Find the image.** Use fully qualified names — it is unambiguous and skips
   the short-name prompt:
   `podman search --limit 10 docker.io/<term>` (or `quay.io/<term>`); tags:
   `podman search --list-tags docker.io/library/<image> | tail -20`.
   Prefer official images (`docker.io/library/<x>`),
   pinned tags (`postgres:16-alpine`, not `latest`). When several candidates
   fit, present 2–3 with one line each and let the user pick.
2. **Pull:** `podman pull docker.io/library/<image>:<tag>` — show the size
   (`podman images <image>`) before pulling something large if the network is
   metered.
3. **Run.** Ephemeral or one-off: `podman run --rm -it <image> …`. Anything
   the user wants to *keep* (a database, a web UI, a game server) is a
   **quadlet**, not a `podman run -d` — see below. Port rules: `-p 127.0.0.1:8080:80`
   binds only locally (default to that unless the user asks to expose on the
   LAN); ports **≥ 1024** bind rootless without extra rights, `:80/:443` need
   `sudo sysctl net.ipv4.ip_unprivileged_port_start=80` (persist via
   `/etc/sysctl.d/`) — ask first, it is a system-wide change. Persistent data
   goes into a **named volume** (`-v <name>:/path`, listed by `podman volume ls`,
   stored under `~/.local/share/containers`, excluded from `@home` snapshots),
   or a bind mount `-v ~/dir:/path` when the user wants the files visible
   (add `--userns=keep-id` so files the container writes stay owned by the user).

## Author a quadlet from scratch (long-lived services)

Quadlets are declarative systemd user units generated from
`~/.config/containers/systemd/<name>.container`. Linger is enabled by the
bundle, so they start at boot without a login. Template to adapt:

```ini
[Unit]
Description=<what it is>

[Container]
Image=docker.io/library/<image>:<tag>
ContainerName=<name>
PublishPort=127.0.0.1:<host>:<container>
Environment=KEY=value
Volume=<name>-data:/path/in/container
AutoUpdate=registry              # optional: `podman auto-update` may pull newer tags

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

Then: `systemctl --user daemon-reload` → `systemctl --user start <name>`
(unit = file stem; `enable` is implied by `[Install]`, no `enable` step —
quadlets are generated, `systemctl --user enable` fails on them by design).
Check `systemctl --user status <name>` and `podman ps`. Secrets: `podman secret create`
+ `Secret=<name>,type=env,target=VAR` beats a password in the unit file. Full
reference: `man podman-systemd.unit`. A shipped example lives at
`/usr/share/w/packs/containers/quadlet/postgres.container`. Other unit kinds:
`.pod` (several containers, one network namespace), `.volume`, `.network`,
`.kube` (a Kubernetes YAML). Convert an existing `podman run` line into a
quadlet by hand — read its `-p`/`-v`/`-e` into `PublishPort`/`Volume`/`Environment`.

**Updates:** `podman auto-update` (units with `AutoUpdate=registry`) pulls and
restarts; `podman auto-update --dry-run` previews. The bundle enables no timer
— offer `systemctl --user enable --now podman-auto-update.timer` if the user
wants it unattended.

## Compose projects

`docker compose up -d` (and `podman compose`, same provider: `docker-compose`
against the podman socket) works from a directory with `compose.yaml`;
`DOCKER_HOST` and `DOCKER_BUILDKIT=0` are already exported in the session.
Compose is fine for a dev stack the user brings; for something that should
survive reboots on this machine, translate it to quadlets (one `.container`
per service, `.network` for the shared network) — compose has no systemd
integration. Building: `podman build -t <name> .` (Containerfile/Dockerfile).

## Housekeeping

- Stopped containers, dangling images, unused networks: `podman system prune`;
  add `--volumes` only when the user confirms — that deletes data. `-a` also
  removes every unused image.
- Remove one thing: `podman rm <c>`, `podman rmi <image>`, `podman volume rm <v>`.
  A quadlet service: `systemctl --user stop <name>` → delete the `.container`
  file → `daemon-reload` (the volume stays until removed explicitly).
- Storage lives in `~/.local/share/containers` (nested btrfs subvolume, not in
  snapshots — a rollback does not bring images back; `podman pull` does).

## Troubleshooting

- `docker ps` → "cannot connect": the socket is not up for this session —
  `systemctl --user start podman.socket`; `DOCKER_HOST` is set at login by
  `/etc/w/env.d/containers.sh` (a pack installed mid-session gets it at the
  next login).
- Service not starting at boot: `loginctl show-user $USER -p Linger` must be
  `yes` (`loginctl enable-linger`), and the quadlet must have `[Install]
  WantedBy=default.target`.
- Unit not generated after editing: `systemctl --user daemon-reload`, then
  `/usr/lib/podman/quadlet -dryrun -user` prints why a file was rejected.
- Container cannot resolve names: aardvark-dns listens on **20053** by W's
  `containers.conf.d/10-w.conf` so the DoT stub on `:53` is untouched — do not
  "fix" DNS by changing that port; check `podman network inspect podman` and
  that the container is on a network with `dns_enabled: true`.
- Permission errors on a bind mount are UID mapping (rootless): files the
  container wrote show up owned by a sub-UID. Run with `--userns=keep-id`
  (quadlet: `UserNS=keep-id`), or fix ownership from the host side with
  `podman unshare chown -R $UID:$UID <dir>`.
- Ports below 1024 refused → the `ip_unprivileged_port_start` rule above.

## Gotchas

- **compose:** BuildKit must stay off (`DOCKER_BUILDKIT=0`), already handled.
- **No rootful Docker:** there is no `docker` daemon or socket in `/var/run` — that is
  intentional. Do not suggest adding the user to a `docker` group.

## Reset / remove

- Config back to W default: `w-reset containers` (uses the bundle manifest).
- Bundle removal is a later phase (shared pacman deps) — do not `pacman -Rns` the
  stack manually without checking dependents.
