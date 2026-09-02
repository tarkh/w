# modules/devtools.sh — DEV-ONLY test helpers for the development VM.
# apply.sh context: runs on the live/installed system as root, BUT only ever when a
# human invokes `apply.sh --devtools` (or the `--dev` convenience) by hand inside the
# dev VM. It is intentionally NOT part of `--all`, and neither install.sh nor
# build-iso.sh reference it — so these helpers cannot leak into the real OS build.
#
# Mechanism: devtools/ is a second overlay tree, parallel to rootfs/ but physically
# OUTSIDE it (rootfs/ is the only overlay that ships). mod_devtools rsyncs devtools/
# onto / exactly like apply_rootfs does for rootfs/. Anything dev-only therefore lives
# under devtools/ and is structurally excluded from the build. Current resident:
#   usr/local/bin/sensors — fake lm_sensors so the bar temp block has data in a VM
#                           (sensors-less hardware); see devtools/.../sensors header.
#
# Guard: refuse to run outside the dev VM. The virtiofs project share mounted at
# /mnt/w-src is the unmistakable signature of the dev VM and is absent on real
# hardware — a belt-and-braces stop against a stray --devtools on an installed system.

mod_devtools() {
  if ! mountpoint -q /mnt/w-src; then
    info "Refusing --devtools: /mnt/w-src not mounted — not a dev VM. Skipping."
    return 0
  fi

  info "Deploying dev-only test helpers (devtools/ overlay)..."
  if compgen -G "$SRC/devtools/*" &>/dev/null; then
    rsync -av --chown=root:root --exclude='.gitkeep' "$SRC/devtools/" /
    info "Dev helpers deployed. Fake sensors live; drive it with: echo 95 > /run/w/dev/temp"
  else
    echo "  devtools/ is empty, skipping."
  fi
}
