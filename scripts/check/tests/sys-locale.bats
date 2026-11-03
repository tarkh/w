#!/usr/bin/env bats
# sys-locale.bats — the target's /etc/vconsole.conf carries the VT font of the
# installer's language: firstboot's dialogs speak it before w-langpack (apply phase)
# sets FONT= by locale, and the kernel's built-in font is Latin-only (Cyrillic came
# out as "Vyberite set'" — found live). chroot_run is a stub.

load helpers

setup() {
  MNT="$BATS_TEST_TMPDIR/mnt"; mkdir -p "$MNT/etc"
  source "$REPO/scripts/install/lib/system.sh"
  ui_info() { :; }
  chroot_run() { :; }
  declare -gA MSG=()
  CONF_KEYMAP=ru CONF_LOCALE=ru_RU.UTF-8
}

@test "a language with a console font → KEYMAP and FONT" {
  MSG[_console_font]=LatArCyrHeb-16
  sys_locale
  [ "$(cat "$MNT/etc/vconsole.conf")" = $'KEYMAP=ru\nFONT=LatArCyrHeb-16' ]
}

@test "a language without one (English) → KEYMAP only, the kernel font stays" {
  sys_locale
  [ "$(cat "$MNT/etc/vconsole.conf")" = 'KEYMAP=ru' ]
}
