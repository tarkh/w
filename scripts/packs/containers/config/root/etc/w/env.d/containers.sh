# W Linux — containers bundle session env (managed by W-Packs, do not edit).
# Sourced by /etc/xdg/uwsm/env-hyprland at graphical-session-pre (see packs.md).
#
# Point the Docker CLI, docker-compose, lazydocker and testcontainers at the
# rootless Podman API socket (podman.socket, enabled per-user by setup.sh). One
# socket serves every Docker-API client at once.
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"

# docker-compose against Podman requires BuildKit off, or compose integration
# breaks (pack-containers.md).
export DOCKER_BUILDKIT=0
