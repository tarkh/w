#!/usr/bin/env bats
# time-rtc.bats — w-time's hardware clock mode. Windows keeps the RTC in local time
# and W never writes into Windows, so RTC=auto (the vendor default) resolves to local
# time exactly while w-boot-otheros reports a Windows — on a dual-boot machine the
# clock moved by the zone offset on every switch (found on real hardware). The
# detector is a stub; the layered config is the checkout's vendor file.

load helpers

setup() {
  export W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh"
  export WCONF_VENDOR_DIR="$REPO/rootfs/usr/share/w/defaults"
  export WCONF_ETC="$BATS_TEST_TMPDIR/etc-w"; mkdir -p "$WCONF_ETC"
  export W_OTHEROS="$BATS_TEST_TMPDIR/otheros"
  windows ""
}

windows() { printf '#!/bin/sh\nprintf "%s"\n' "$1" > "$W_OTHEROS"; chmod +x "$W_OTHEROS"; }

@test "auto, the vendor default: UTC without Windows" {
  run "$REPO/rootfs/usr/bin/w-time" rtc
  [ "$status" -eq 0 ]
  [ "$output" = "auto -> utc" ]
}

@test "auto: local time while the firmware has a Windows entry" {
  windows '0000\tWindows Boot Manager\n'
  run "$REPO/rootfs/usr/bin/w-time" rtc
  [ "$output" = "auto -> local" ]
}

@test "the admin's pin wins over the detector" {
  windows '0000\tWindows Boot Manager\n'
  printf 'RTC=utc\n' > "$WCONF_ETC/time.conf"
  run "$REPO/rootfs/usr/bin/w-time" rtc
  [ "$output" = "utc -> utc" ]
}

@test "an unknown mode is a usage error" {
  run "$REPO/rootfs/usr/bin/w-time" rtc sometimes
  [ "$status" -eq 2 ]
}
