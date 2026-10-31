#!/usr/bin/env bats
# crypt.bats — w-crypt's two judgements that have no other test before a real boot:
#   * tpm_reseal_state recomputes the TPM2 policy digest systemd-cryptenroll sealed to
#     from the live PCR values; the reference pair below (PCR7 → policy hash) was read
#     off an e2e VM booted through shim, so a drift in the arithmetic is a red check
#     rather than a Hub that says "re-seal" on every boot (or never);
#   * secureboot_enforced is the gate enroll-tpm stands behind — Secure Boot on in W,
#     enforced by the firmware, phase 2 done.
# The functions are lifted out of the script (it dispatches on load) with their
# absolute paths rewritten into the test.

load helpers

PCR7=FE6CA05ACA68D99A8488CBB4AD66EFB40ABCFFFF9F656ABE9B46FE6441E4B82C
POLICY=157dc88eaf75e6adcd2be5bd57664d4032833429481d2b21524f386b7c712c6c

setup() {
  SYS="$BATS_TEST_TMPDIR/tpm0"; mkdir -p "$SYS/pcr-sha256"
  echo "$PCR7" > "$SYS/pcr-sha256/7"
  RESEAL_MARKER="$BATS_TEST_TMPDIR/tpm-reseal-pending"
  eval "$(sed -n -e '/^tpm_reseal_state() {/,/^}/p' -e '/^secureboot_enforced() {/,/^}/p' \
    "$REPO/rootfs/usr/bin/w-crypt" | sed "s#/sys/class/tpm/tpm0#$SYS#")"
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"; PATH="$bin:$PATH"
}

token() { printf '{"type":"systemd-tpm2","tpm2-pcrs":%s,"tpm2-pcr-bank":"sha256","tpm2-policy-hash":"%s"%s}' "$1" "$2" "${3:-}"; }

@test "reseal: the seal matches the live PCR7 → no" {
  [ "$(tpm_reseal_state "$(token '[7]' "$POLICY")")" = no ]
}

@test "reseal: PCR7 moved (firmware/shim update) → stale" {
  echo "00${PCR7:2}" > "$SYS/pcr-sha256/7"
  [ "$(tpm_reseal_state "$(token '[7]' "$POLICY")")" = stale ]
}

@test "reseal: a PIN seal adds PolicyAuthValue — the bare PCR digest no longer matches" {
  [ "$(tpm_reseal_state "$(token '[7]' "$POLICY" ',"tpm2-pin":true')")" = stale ]
}

@test "reseal: a seal bound to no PCR → stale, or pending under the installer's marker" {
  [ "$(tpm_reseal_state "$(token '[]' "")")" = stale ]
  touch "$RESEAL_MARKER"
  [ "$(tpm_reseal_state "$(token '[]' "")")" = pending ]
}

@test "reseal: signed or pcrlock policies are not recomputed → unknown" {
  [ "$(tpm_reseal_state "$(token '[7]' "$POLICY" ',"tpm2_pubkey_pcrs":[11]')")" = unknown ]
  [ "$(tpm_reseal_state "$(token '[7]' "$POLICY" ',"tpm2_pcrlock":true')")" = unknown ]
}

sb() { printf '#!/bin/sh\nprintf "state\\tsecure_boot\\tsetup_mode\\ttpm_pending\\tmode\\tconfig_hash\\tmok\\n%s\\n"\n' "$1" > "$bin/w-secureboot"; chmod +x "$bin/w-secureboot"; }

@test "gate: Secure Boot on in W, enforced, phase 2 done → open" {
  sb 'on\tyes\tno\tno\tshim\tok\tyes'
  secureboot_enforced
}

@test "gate: off in W, off in the firmware, or phase 2 pending → closed" {
  sb 'off\tno\tno\tno\tnone\tunknown\tna';          ! secureboot_enforced
  sb 'on\tno\tno\tno\tshim\tok\tyes';               ! secureboot_enforced
  sb 'on\tyes\tno\tready\tshim\tok\tyes';           ! secureboot_enforced
}
