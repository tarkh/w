# modules/packs.sh — W-Packs framework staging (apply.sh --packs).
#
# Second install layer on top of the base apply.sh: opt-in software bundles by
# direction (containers/graphics/office/gaming…). This module stages the framework
# so the `w-pack` CLI works standalone on the client; it does NOT install any
# bundle (that is `w-pack install <bundle>`, driven by the TUI selection at
# firstboot — a later phase). See packs.md.
#
# What it stages (edge/apply context; on stable the w-system package ships these):
#   • w-pack itself                  — rides in via apply_rootfs; re-installed here
#                                       so `apply.sh --packs` alone is sufficient.
#   • scripts/packs/ → /usr/share/w/packs   — the self-contained bundle tree,
#                                       read offline by w-pack on the client.
#   • deploy SDK → /usr/lib/w/lib/deploy.sh — w-pack reuses seed_user_file
#                                       for bundle config (no duplicated logic).
#   • w-style drop-in root modules.d/ — ensured present so bundles can drop axes in
#                                       (rides in via apply_rootfs too; belt-and-braces).
#
# Order-independent in --all (like mod_reset): it only lays down framework paths.

mod_packs() {
  info "Installing W-Packs framework (w-pack)..."
  install -Dm755 "$SRC/rootfs/usr/bin/w-pack" /usr/bin/w-pack

  # Reusable config-ownership SDK (seed_user_file) for bundle config deploy — the
  # same source apply.sh reads from the repo, shipped to a stable system path so
  # w-pack can source it on a client without the repo.
  info "Staging config-ownership deploy SDK for w-pack..."
  install -Dm644 "$SRC/scripts/install/lib/deploy.sh" /usr/lib/w/lib/deploy.sh

  # Ensure the w-style drop-in root exists (bundles deploy their axes here). Ships
  # via apply_rootfs as well; created here so --packs is self-sufficient.
  install -d /usr/lib/w/w-style/modules.d

  # Stage the self-contained bundle tree to the offline client path. --delete so a
  # removed/renamed bundle in the repo doesn't linger on the target. Excludes the
  # .gitkeep placeholder. When the tree is empty (no bundles yet) this just creates
  # the directory.
  info "Staging bundle tree to /usr/share/w/packs..."
  install -d /usr/share/w/packs
  if compgen -G "$SRC/scripts/packs/*/" >/dev/null 2>&1; then
    rsync -a --delete --chown=root:root --exclude='.gitkeep' \
      "$SRC/scripts/packs/" /usr/share/w/packs/
  else
    echo "  No bundles staged yet (scripts/packs is empty)."
  fi

  info "w-pack installed. List bundles: w-pack list; install one: sudo w-pack install <bundle>."
}
