#!/usr/bin/env bats
# tdata.bats — the telegram bundle's first-launch seed round-trips through the
# dev-side reader (pack-telegram.md, stage 2).
#
# Two independent implementations of tdesktop's on-disk format meet here: the
# seeder writes (scripts/packs/telegram/tdata-seed.py), w-tdata-decode reads
# (devtools, the tool that decoded the format off a real tdata in the first
# place). A seed the reader cannot open would still be "accepted" by tdesktop —
# silently, as a discarded file and a stock look — so this is the only gate
# that says the bytes are right before a VM run. The dbiApplicationSettings
# prefix is additionally held against a fresh-start capture from the VM
# (fixtures/tdata-app-settings-<ver>.hex): every field but nativeWindowFrame
# must be what an untouched tdesktop writes itself, or the seed would silently
# override a default. Re-capture on a telegram-desktop bump (recipe in
# pack-telegram.md).

load helpers

SEED="$REPO/scripts/packs/telegram/tdata-seed.py"
DECODE="$REPO/devtools/usr/local/bin/w-tdata-decode"
FIXTURE="$FIXTURES/tdata-app-settings-7.2.7.hex"

setup() {
  command -v python3 &>/dev/null || skip "python3 not installed"
  python3 -c 'import cryptography' 2>/dev/null || skip "python-cryptography not installed"
  DATA="$BATS_TEST_TMPDIR/TelegramDesktop"
  mkdir -p "$DATA"
  THEME="$DATA/w.tdesktop-theme"
  printf 'PK\003\004 not a real zip, but %d bytes of content' 4 >"$THEME"
}

seed() { python3 "$SEED" --data-dir "$DATA" --theme "$THEME" --version 7002007 "$@"; }

@test "tdata: seed writes settingss + one theme record, decoder reads both" {
  run seed
  [ "$status" -eq 0 ]
  [ -f "$DATA/tdata/settingss" ]
  [ "$(find "$DATA/tdata" -name '*s' -type f | wc -l)" -eq 2 ]

  run python3 "$DECODE" "$DATA/tdata" --app-settings
  [ "$status" -eq 0 ]
  [[ "$output" == *"settingss: version=7002007"*"decrypted"* ]]
  # both slots on the same record, night mode on
  [[ "$output" =~ ThemeKey:\ day=([0-9A-F]{16})\ night=([0-9A-F]{16})\ nightMode=1 ]]
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]
  # the record the key names exists and carries the file as content
  [[ "$output" =~ →\ files\ ([0-9A-F]{16})s\ / ]]
  [ -f "$DATA/tdata/${BASH_REMATCH[1]}s" ]
  [[ "$output" == *"theme record: content $(stat -c %s "$THEME") bytes"* ]]
  [[ "$output" == *"pathAbsolute='$THEME' pathRelative='w.tdesktop-theme'"* ]]
  [[ "$output" == *"cloud id=0 hash=0 slug=None title=None doc=0 field1=0"* ]]
  [[ "$output" == *"cache: paletteChecksum=0 contentChecksum=0 colors=0 background=0 field2=0"* ]]
  # Qt window frame on, and the prefix stops right there
  [[ "$output" == *"nativeWindowFrame = 1"* ]]
  [[ "$output" == *"prefix ends at 200 of 200 bytes"* ]]
}

@test "tdata: the seeded content is the theme file byte for byte" {
  run seed
  [ "$status" -eq 0 ]
  mkdir "$BATS_TEST_TMPDIR/dump"
  python3 "$DECODE" "$DATA/tdata" --dump "$BATS_TEST_TMPDIR/dump" >/dev/null
  rec="$(find "$BATS_TEST_TMPDIR/dump" -name '*s.dec' ! -name 'settingss.dec')"
  # QDataStream: uint32 BE length, then the bytes
  python3 - "$rec" "$THEME" <<'EOF'
import struct, sys
plain = open(sys.argv[1], "rb").read()
n = struct.unpack(">I", plain[:4])[0]
assert plain[4:4 + n] == open(sys.argv[2], "rb").read(), "content differs"
EOF
}

@test "tdata: dbiApplicationSettings prefix equals the fresh-start capture (nativeWindowFrame aside)" {
  run seed
  [ "$status" -eq 0 ]
  mkdir "$BATS_TEST_TMPDIR/dump"
  python3 "$DECODE" "$DATA/tdata" --dump "$BATS_TEST_TMPDIR/dump" >/dev/null
  python3 - "$BATS_TEST_TMPDIR/dump/settingss.dec" "$FIXTURE" <<'EOF'
import struct, sys
plain = open(sys.argv[1], "rb").read()
i = plain.find(struct.pack(">I", 0x5E))          # dbiApplicationSettings
n = struct.unpack(">I", plain[i + 4:i + 8])[0]
blob = plain[i + 8:i + 8 + n]
captured = bytes.fromhex(open(sys.argv[2]).read().strip())
assert len(blob) == len(captured) == 200, (len(blob), len(captured))
assert blob[:-4] == captured[:-4], "a default drifted from the capture"
assert struct.unpack(">i", captured[-4:])[0] == 0, "capture must be a fresh start (frame off)"
assert struct.unpack(">i", blob[-4:])[0] == 1, "seed must turn the frame on"
EOF
}

@test "tdata: --no-app-settings leaves only the theme block" {
  run seed --no-app-settings
  [ "$status" -eq 0 ]
  run python3 "$DECODE" "$DATA/tdata" --app-settings
  [[ "$output" != *"ApplicationSettings"* ]]
  [[ "$output" == *"nightMode=1"* ]]
}

@test "tdata: an initialised tdata is never touched (exit 3, no writes)" {
  mkdir -p "$DATA/tdata"
  : >"$DATA/tdata/settingss"
  run seed
  [ "$status" -eq 3 ]
  [ "$(find "$DATA/tdata" -type f | wc -l)" -eq 1 ]
  rm "$DATA/tdata/settingss"; : >"$DATA/tdata/settings0"   # legacy name counts too
  run seed
  [ "$status" -eq 3 ]
}

@test "tdata: refuses an empty theme, a relative path and a bad version" {
  : >"$THEME"
  run seed
  [ "$status" -eq 2 ]
  [ ! -e "$DATA/tdata" ] || [ -z "$(ls -A "$DATA/tdata")" ]
  printf 'PK\003\004....' >"$THEME"
  run python3 "$SEED" --data-dir "$DATA" --theme w.tdesktop-theme --version 7002007
  [ "$status" -eq 2 ]
  run python3 "$SEED" --data-dir "$DATA" --theme "$THEME" --version 0
  [ "$status" -eq 2 ]
}

@test "tdata: the header carries the version given (tdesktop rejects newer-than-itself)" {
  python3 "$SEED" --data-dir "$DATA" --theme "$THEME" --version 6001002 >/dev/null
  run python3 "$DECODE" "$DATA/tdata"
  [[ "$output" == *"settingss: version=6001002"* ]]
}

@test "tdata: setup-user.sh maps a pacman version to AppVersion and calls the seeder" {
  # Drive the bundle script with stubbed pacman/pgrep/w-style, unprivileged.
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  printf '#!/bin/bash\necho "telegram-desktop 7.2.7-2"\n' >"$bin/pacman"
  printf '#!/bin/bash\nexit 1\n' >"$bin/pgrep"
  printf '#!/bin/bash\nexit 0\n' >"$bin/w-style"
  chmod +x "$bin"/*
  home="$BATS_TEST_TMPDIR/home"; mkdir -p "$home/.local/share/TelegramDesktop"
  cp "$THEME" "$home/.local/share/TelegramDesktop/w.tdesktop-theme"
  PATH="$bin:$PATH" BUNDLE_NAME=telegram BUNDLE_DIR="$REPO/scripts/packs/telegram" \
    PACK_USER="$(id -un)" PACK_HOME="$home" PACK_AS_ROOT=0 \
    run bash "$REPO/scripts/packs/telegram/setup-user.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version 7002007"* ]]
  [[ "$output" == *"from its very first launch"* ]]
  [ -f "$home/.local/share/TelegramDesktop/tdata/settingss" ]

  # Second run: initialised → untouched, the one-click text instead.
  PATH="$bin:$PATH" BUNDLE_NAME=telegram BUNDLE_DIR="$REPO/scripts/packs/telegram" \
    PACK_USER="$(id -un)" PACK_HOME="$home" PACK_AS_ROOT=0 \
    run bash "$REPO/scripts/packs/telegram/setup-user.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has run before"* ]]
  [[ "$output" == *"Choose from file"* ]]

  # A running Telegram blocks the seed.
  rm -rf "$home/.local/share/TelegramDesktop/tdata"
  printf '#!/bin/bash\nexit 0\n' >"$bin/pgrep"
  PATH="$bin:$PATH" BUNDLE_NAME=telegram BUNDLE_DIR="$REPO/scripts/packs/telegram" \
    PACK_USER="$(id -un)" PACK_HOME="$home" PACK_AS_ROOT=0 \
    run bash "$REPO/scripts/packs/telegram/setup-user.sh"
  [[ "$output" == *"Telegram is running"* ]]
  [ ! -e "$home/.local/share/TelegramDesktop/tdata" ]
}
