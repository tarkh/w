# modules/langpack.sh — the system language profile (w-langpack).
#
# Delivers everything the chosen locale needs BEYOND `LANG=`: the Firefox
# language pack, a spell-checking dictionary, translated man pages where they
# exist, and the Linux-console font that keeps a TTY from transliterating
# non-Latin text. The catalogue is probed against pacman's sync db inside
# w-langpack, so this module has no language table of its own and covers every
# locale the wizard offers. See config-i18n.md / w-langpack.
#
# Runs post-boot only, right after mod packages: /usr/bin/w-langpack arrives with
# apply_rootfs and pacman must already be past its own transaction. Re-running a
# full apply just re-checks — the whole thing is idempotent, which is also how a
# machine that switched language from the Hub picks its packages up later.
#
# Never fatal. A language pack that cannot be downloaded leaves a fully usable
# system in the fallback language; failing the apply over it would be a far worse
# outcome than an English Firefox (w-langpack itself downgrades the pacman failure
# to a warning, this is the second belt).

# Compatibility shim: apply.sh uses info(), install context uses ui_info().
command -v ui_info &>/dev/null || ui_info() { info "$@"; }

mod_langpack() {
  # Post-boot only: inside the chroot there is no live VT to load a font onto and
  # the target's package transaction is still mod_base's business.
  [[ -n "${MNT:-}" ]] && return 0

  command -v w-langpack >/dev/null 2>&1 || {
    ui_info "w-langpack not present, skipping language profile."
    return 0
  }

  ui_info "Applying the language profile..."
  w-langpack apply || ui_info "Language profile incomplete (non-fatal)."
  return 0
}
