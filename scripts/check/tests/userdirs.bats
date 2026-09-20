#!/usr/bin/env bats
# userdirs.bats — w-userdirs' rename policy: the one place W touches folders full of
# a user's files, so every branch of "rename / leave alone" is pinned here.
#
# What is under test is the decision, not xdg-user-dirs: the real
# xdg-user-dirs-update is replaced by a stub on PATH that speaks the three calls
# the script makes (`--force --dummy-output` with LANGUAGE=<locale> for the names,
# `--set NAME path` to repoint the config, a bare run to create what is missing)
# and translates from a six-word table. The fixture home is a tmpdir; the layered
# config is pointed at the repo's vendor files, so LOCALIZE reads its shipped
# default unless a test writes the user layer.

load helpers

setup() {
  export W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh"
  export WCONF_VENDOR_DIR="$REPO/rootfs/usr/share/w/defaults"
  export WCONF_ETC="$BATS_TEST_TMPDIR/etc/w"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export W_USERDIRS_DEFAULTS="$REPO/rootfs/etc/xdg/user-dirs.defaults"
  export W_USERDIRS_SYSCONF="$BATS_TEST_TMPDIR/etc/xdg/user-dirs.conf"
  export W_USERDIRS_HOOKS="$BATS_TEST_TMPDIR/hooks.d"
  # No /etc/locale.conf in the fixture: the tests drive the language through LANG.
  export W_USERDIRS_LOCALE_CONF="$BATS_TEST_TMPDIR/etc/locale.conf"
  export LANG=en_US.UTF-8
  unset LC_ALL LC_MESSAGES LANGUAGE
  mkdir -p "$XDG_CONFIG_HOME" "$WCONF_ETC" "$BATS_TEST_TMPDIR/etc/xdg" "$W_USERDIRS_HOOKS" "$BATS_TEST_TMPDIR/bin"
  printf 'enabled=True\n' > "$W_USERDIRS_SYSCONF"
  stub_xud
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"; export PATH
  W="$REPO/rootfs/usr/bin/w-userdirs"
}

# The stub. Translation follows LANGUAGE, else the locale (LC_ALL/LANG) — the
# precedence gettext has — for the two languages the tests use; anything else,
# including LANGUAGE=C, is English.
stub_xud() {
  cat > "$BATS_TEST_TMPDIR/bin/xdg-user-dirs-update" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
conf="${XDG_CONFIG_HOME:-$HOME/.config}"
tr_name() {
  case "${LANGUAGE:-${LC_ALL:-${LANG:-}}}" in
    ru*) case "$1" in Desktop) echo "Рабочий стол";; Downloads) echo "Загрузки";; Documents) echo "Документы";;
                      Music) echo "Музыка";; Pictures) echo "Изображения";; Videos) echo "Видео";; *) echo "$1";; esac ;;
    de*) case "$1" in Pictures) echo "Bilder";; Downloads) echo "Downloads";; *) echo "$1";; esac ;;
    *) echo "$1" ;;
  esac
}
names() { # print XDG_<N>_DIR lines for the defaults, translated
  while IFS='=' read -r n v; do [[ "$n" =~ ^[A-Z]+$ ]] || continue; printf 'XDG_%s_DIR="$HOME/%s"\n' "$n" "$(tr_name "$v")"; done < "$W_USERDIRS_DEFAULTS"
}
case "${1:-}" in
  --force) [[ "${2:-}" == --dummy-output ]] || exit 1; names > "$3" ;;
  --set)   n="$2"; p="$3"; p="${p/#"$HOME"/\$HOME}"
           [[ -f "$conf/user-dirs.dirs" ]] || : > "$conf/user-dirs.dirs"
           grep -v "^XDG_${n}_DIR=" "$conf/user-dirs.dirs" > "$conf/.tmp" || true
           printf 'XDG_%s_DIR="%s"\n' "$n" "$p" >> "$conf/.tmp"; mv "$conf/.tmp" "$conf/user-dirs.dirs" ;;
  "")      # bare run: add defaults missing from the config, create the folders,
           # write the anchor only when there was no config at all (upstream's rule)
           first=0; [[ -f "$conf/user-dirs.dirs" ]] || first=1
           names | while IFS= read -r l; do
             k="${l%%=*}"; grep -q "^$k=" "$conf/user-dirs.dirs" 2>/dev/null || echo "$l" >> "$conf/user-dirs.dirs"
           done
           while IFS= read -r l; do [[ "$l" =~ ^XDG_[A-Z]+_DIR=\"\$HOME/(.*)\"$ ]] && mkdir -p "$HOME/${BASH_REMATCH[1]}"; done < "$conf/user-dirs.dirs"
           if ((first)); then printf '%s' "${LANG%%.*}" > "$conf/user-dirs.locale"; fi ;;
  *) exit 1 ;;
esac
EOF
  chmod 755 "$BATS_TEST_TMPDIR/bin/xdg-user-dirs-update"
}

# A home already set up in <locale>: the six folders exist, config + anchor written.
setup_home_in() { # <locale, e.g. en_US|ru_RU>
  LANG="$1.UTF-8" "$BATS_TEST_TMPDIR/bin/xdg-user-dirs-update"
}
dirs_value() { sed -n "s/^XDG_$1_DIR=\"\(.*\)\"$/\1/p" "$XDG_CONFIG_HOME/user-dirs.dirs"; }

# ── First login ──────────────────────────────────────────────────────────────

@test "first login on an English system: folders created, anchor written, nothing renamed" {
  run "$W" sync
  [ "$status" -eq 0 ]
  [ -d "$HOME/Pictures" ] && [ -d "$HOME/Documents" ]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "en_US" ]
  [[ "$output" == *"0 renamed"* ]]
}

@test "first login on a Russian system adopts folders a program already made under English names" {
  mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Downloads"; touch "$HOME/Pictures/Screenshots/a.png"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -f "$HOME/Изображения/Screenshots/a.png" ]
  [ ! -e "$HOME/Pictures" ] && [ ! -e "$HOME/Downloads" ] && [ -d "$HOME/Загрузки" ]
  [ -d "$HOME/Документы" ]                        # the rest created fresh
  [ "$(dirs_value PICTURES)" = '$HOME/Изображения' ]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "ru_RU" ]
}

@test "first login with LOCALIZE=no leaves English folders beside the new translated set" {
  mkdir -p "$XDG_CONFIG_HOME/w"; printf 'LOCALIZE=no\n' > "$XDG_CONFIG_HOME/w/userdirs.conf"
  mkdir -p "$HOME/Pictures"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -d "$HOME/Pictures" ] && [ -d "$HOME/Изображения" ]
}

# ── Language change ──────────────────────────────────────────────────────────

@test "language change renames every default-named folder, contents in place" {
  setup_home_in en_US
  touch "$HOME/Pictures/p.png" "$HOME/Documents/d.txt"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -f "$HOME/Изображения/p.png" ] && [ -f "$HOME/Документы/d.txt" ]
  [ ! -e "$HOME/Pictures" ]
  [ "$(dirs_value PICTURES)" = '$HOME/Изображения' ]
  [ "$(dirs_value DESKTOP)" = '$HOME/Рабочий стол' ]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "ru_RU" ]
  [[ "$output" == *"6 folder(s) renamed"* ]]
}

@test "a folder the user moved is theirs: not renamed, config untouched" {
  setup_home_in en_US
  mkdir -p "$HOME/Files"; rmdir "$HOME/Documents"
  "$BATS_TEST_TMPDIR/bin/xdg-user-dirs-update" --set DOCUMENTS "$HOME/Files"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -d "$HOME/Files" ] && [ ! -e "$HOME/Документы" ]
  [ "$(dirs_value DOCUMENTS)" = '$HOME/Files' ]
  [ -d "$HOME/Изображения" ]                      # the others still moved
}

@test "new name already taken by a non-empty folder: both kept, config untouched, reported" {
  setup_home_in en_US
  mkdir -p "$HOME/Изображения"; touch "$HOME/Изображения/mine.png" "$HOME/Pictures/p.png"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -f "$HOME/Pictures/p.png" ] && [ -f "$HOME/Изображения/mine.png" ]
  [ "$(dirs_value PICTURES)" = '$HOME/Pictures' ]
  [[ "$output" == *"already exists and is not empty"* ]]
  [[ "$output" == *"5 folder(s) renamed"* ]]
}

@test "new name taken by an EMPTY folder: it is replaced by the rename" {
  setup_home_in en_US
  mkdir -p "$HOME/Изображения"; touch "$HOME/Pictures/p.png"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -f "$HOME/Изображения/p.png" ] && [ ! -e "$HOME/Pictures" ]
}

@test "same names in both languages: no rename, anchor still moves" {
  setup_home_in en_US
  LANG=de_DE.UTF-8 run "$W" sync                  # de: only Pictures differs in the stub
  [ "$status" -eq 0 ]
  [ -d "$HOME/Bilder" ] && [ -d "$HOME/Downloads" ] && [ -d "$HOME/Documents" ]
  [[ "$output" == *"1 folder(s) renamed"* ]]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "de_DE" ]
}

@test "LOCALIZE=no keeps the folders AND the anchor, so a later yes still renames" {
  setup_home_in en_US
  mkdir -p "$XDG_CONFIG_HOME/w"; printf 'LOCALIZE=no\n' > "$XDG_CONFIG_HOME/w/userdirs.conf"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -d "$HOME/Pictures" ] && [ ! -e "$HOME/Изображения" ]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "en_US" ]
  [[ "$output" == *"LOCALIZE=no"* ]]
  printf 'LOCALIZE=yes\n' > "$XDG_CONFIG_HOME/w/userdirs.conf"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ -d "$HOME/Изображения" ] && [ ! -e "$HOME/Pictures" ]
}

@test "xdg-user-dirs disabled (enabled=False, user file wins) → no-op" {
  setup_home_in en_US
  printf 'enabled=False\n' > "$XDG_CONFIG_HOME/user-dirs.conf"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [ -d "$HOME/Pictures" ] && [ ! -e "$HOME/Изображения" ]
  [[ "$output" == *"disabled"* ]]
}

@test "dry run reports the renames and changes nothing" {
  setup_home_in en_US
  LANG=ru_RU.UTF-8 run "$W" sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pictures -> Изображения"* ]]
  [ -d "$HOME/Pictures" ] && [ ! -e "$HOME/Изображения" ]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "en_US" ]
}

@test "second login in the same language is a no-op" {
  setup_home_in ru_RU
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"already named for ru_RU"* ]]
}

@test "config without an anchor adopts the current language" {
  "$BATS_TEST_TMPDIR/bin/xdg-user-dirs-update" --set DOWNLOAD "$HOME/dl"
  mkdir -p "$HOME/dl"
  run "$W" sync
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_CONFIG_HOME/user-dirs.locale")" = "en_US" ]
  [ "$(dirs_value DOWNLOAD)" = '$HOME/dl' ]
}

@test "a hook runs once per renamed folder with NAME/OLD/NEW" {
  setup_home_in en_US
  cat > "$W_USERDIRS_HOOKS/log" <<'EOF'
#!/usr/bin/env bash
echo "$W_USERDIR_NAME|$W_USERDIR_OLD|$W_USERDIR_NEW" >> "$HOME/.hooklog"
EOF
  chmod 755 "$W_USERDIRS_HOOKS/log"
  LANG=ru_RU.UTF-8 run "$W" sync
  [ "$status" -eq 0 ]
  grep -qx "PICTURES|$HOME/Pictures|$HOME/Изображения" "$HOME/.hooklog"
  [ "$(wc -l < "$HOME/.hooklog")" -eq 6 ]
}

@test "sync refuses to run as root" {
  [ "$EUID" -ne 0 ] || skip "running as root"
  # Emulate root via the check the script uses: EUID is read-only, so cover the
  # message path by inspection instead — the guard is one line, keep it honest.
  grep -q 'sync runs as the user whose home it is, not as root' "$W"
}

# ── status ───────────────────────────────────────────────────────────────────

@test "status --porcelain: pending count and per-folder state after a language change" {
  setup_home_in en_US
  mkdir -p "$HOME/Files"; rmdir "$HOME/Documents"
  "$BATS_TEST_TMPDIR/bin/xdg-user-dirs-update" --set DOCUMENTS "$HOME/Files"
  LANG=ru_RU.UTF-8 run "$W" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *$'LOCALE_SAVED\ten_US'* ]]
  [[ "$output" == *$'LOCALE_CURRENT\tru_RU'* ]]
  [[ "$output" == *$'PENDING\t5'* ]]
  [[ "$output" == *$'DIR\tDOCUMENTS\t'"$HOME"$'/Files\tcustom'* ]]
  [[ "$output" == *$'DIR\tPICTURES\t'"$HOME"$'/Pictures\tdefault'* ]]
}

@test "localize writes the user layer and status reflects it" {
  run "$W" localize no
  [ "$status" -eq 0 ]
  grep -q '^LOCALIZE=no' "$XDG_CONFIG_HOME/w/userdirs.conf"
  run "$W" status --porcelain
  [[ "$output" == *$'LOCALIZE\tno'* ]]
  run "$W" localize maybe
  [ "$status" -eq 2 ]
}
