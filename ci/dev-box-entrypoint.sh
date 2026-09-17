#!/usr/bin/env bash
# ci/dev-box-entrypoint.sh — privilege drop inside the w-dev-box image.
#
# Baked into the cached image by devtools/usr/local/bin/w-dev-box and run as the
# container's root, whose only job is to stop being root before the work starts.
#
# Why that matters enough to need its own file: scripts/check.sh must run
# unprivileged, and not as a precaution — the suites assert it. wconf.bats' "a
# non-root caller may not act for someone else" is the one test in its
# neighbourhood that deliberately does NOT set the W_EUID=0 seam; it reads the
# process's real euid and expects a refusal. As root it fails, because root
# genuinely may act for someone else. ci/iso-build-entrypoint.sh has always known
# this (`runuser -u builder`), and this file is how the cached path keeps the same
# promise instead of quietly becoming a second, more permissive environment.
#
# The account is created here rather than baked into the image so the image is not
# pinned to one uid. W_BOX_UID/W_BOX_GID come from the OWNER OF THE CHECKOUT, not
# from the caller's `id -u` — by the time w-dev-box runs, the caller is usually
# root already (run0, sudo, CI) and their own uid says nothing. Matching the
# checkout's owner is also what keeps files the run touches owned by the right
# person on the bind mount.
set -euo pipefail

uid="${W_BOX_UID:-1000}"
gid="${W_BOX_GID:-1000}"

# `|| groupadd checker` without -g: a uid/gid already taken inside the image is
# not worth failing over. What the suites need is "not root", not a specific uid.
getent group checker >/dev/null 2>&1 || groupadd -g "$gid" checker 2>/dev/null || groupadd checker
id checker >/dev/null 2>&1 || useradd -m -u "$uid" -g checker checker 2>/dev/null || useradd -m -g checker checker

# git refuses a tree owned by another uid, and check.sh's whole file inventory is
# `git ls-files`. Declared for the account that will actually run it.
runuser -u checker -- git config --global --add safe.directory /w

exec runuser -u checker -- "$@"
