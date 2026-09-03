#!/usr/bin/env bats
# release-signing.bats — the signature that stands between a compromised repository
# and root on a user's machine.
#
# w-sync runs apply.sh as root on whatever it pulls, so verify_tip() is the whole
# security boundary of the edge channel. It is tested by RUNNING it: the function is
# lifted out of the script (which cannot be sourced — it dispatches at the bottom) and
# evaluated against a real git repo with real signatures, so what passes here is the
# code that ships, not a restatement of it. A test that only grepped for `verify-tag`
# would keep passing after the flag that makes it meaningful was dropped.
#
# The throwaway keys are generated per test. Nothing here touches the real release
# key, which is not on this disk at all.

load helpers

ANCHOR="$REPO/rootfs/usr/share/w/update/w-release.allowed_signers"
WSYNC="$REPO/rootfs/usr/bin/w-sync"

setup() {
  command -v ssh-keygen >/dev/null || skip "openssh not installed"
  command -v git >/dev/null || skip "git not installed"
}

# ── The anchor that ships ────────────────────────────────────────────────────

@test "anchor: exists and lists at least one key" {
  [ -f "$ANCHOR" ]
  run bash -c "awk '!/^[[:space:]]*#/ && NF >= 3' '$ANCHOR' | wc -l"
  [ "$output" -ge 1 ]
}

# ssh-keygen SKIPS a line it cannot parse rather than refusing the file, so a typo in
# the key would not announce itself anywhere: verification would simply never match,
# and every machine would refuse every update until someone read the file by hand.
# Each key is therefore parsed on its own.
@test "anchor: every key in it is a well-formed public key" {
  local n=0 key
  while read -r key; do
    [[ -n "$key" ]] || continue
    run bash -c "printf '%s\n' \"$key\" | ssh-keygen -lf -"
    [ "$status" -eq 0 ]
    n=$((n + 1))
  done < <(awk '!/^[[:space:]]*#/ && NF >= 3 { print $2 " " $3 }' "$ANCHOR")
  [ "$n" -ge 1 ]
}

@test "anchor: carries no private key material" {
  run grep -c "PRIVATE KEY" "$ANCHOR"
  [ "$output" -eq 0 ]
}

@test "anchor: is deployed by mod_updatesys and owned by its manifest" {
  run grep -q "install -Dm644 .*w-release.allowed_signers" "$REPO/scripts/install/modules/updatesys.sh"
  [ "$status" -eq 0 ]
  run grep -q "^/usr/share/w/update/w-release.allowed_signers	managed" \
    "$REPO/rootfs/usr/share/w/update/updatesys.manifest"
  [ "$status" -eq 0 ]
}

# ── verify_tip(), run for real ───────────────────────────────────────────────

# Build a repo with a signed tag, a second identity, and the function under test.
# Echoes nothing; sets $T (repo), $GOOD (trusted anchor), $EVIL (anchor listing a
# different key).
_fixture() {
  T="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$T"
  ssh-keygen -q -t ed25519 -N '' -C w-release -f "$BATS_TEST_TMPDIR/rel"
  ssh-keygen -q -t ed25519 -N '' -C attacker   -f "$BATS_TEST_TMPDIR/att"
  GOOD="$BATS_TEST_TMPDIR/good.signers"
  EVIL="$BATS_TEST_TMPDIR/evil.signers"
  printf 'w-release@w.tarkh.com %s\n' "$(awk '{print $1" "$2}' "$BATS_TEST_TMPDIR/rel.pub")" > "$GOOD"
  printf 'w-release@w.tarkh.com %s\n' "$(awk '{print $1" "$2}' "$BATS_TEST_TMPDIR/att.pub")" > "$EVIL"

  git -C "$T" init -q -b main
  git -C "$T" config user.name w
  git -C "$T" config user.email w@example.com
  echo x > "$T/f"
  git -C "$T" add f
  git -C "$T" commit -qm "release"

  # The function's environment: everything it reads, and stubs for everything it
  # says. git_c is the real wrapper's contract — git, bound to the checkout.
  git_c() { git -C "$T" "$@"; }
  info() { echo "info: $*"; }
  warn() { echo "warn: $*"; }
  err()  { echo "err: $*"; }
  die()  { echo "die: $*"; return 1; }
  UPSTREAM=main
  UPDATE_CONF=/etc/w/update.conf
  VERIFY_SIGNATURE=yes
  SIGNERS_SYS="$GOOD"
  eval "$(sed -n '/^verify_tip()/,/^}/p' "$WSYNC")"
}

_sign_tag() { # <name> <key-basename>
  local k="$BATS_TEST_TMPDIR/$2"
  git -C "$T" -c gpg.format=ssh -c "user.signingkey=$k" tag -s "$1" -m "$1"
}

@test "verify_tip: accepts a tag signed by a trusted key" {
  _fixture
  _sign_tag v1.0.0 rel
  run verify_tip
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature OK"* ]]
}

@test "verify_tip: refuses a tag signed by a key it does not trust" {
  _fixture
  _sign_tag v1.0.0 att
  run verify_tip
  [ "$status" -ne 0 ]
  [[ "$output" == *"REFUSING TO UPDATE"* ]]
}

@test "verify_tip: refuses an unsigned tag" {
  _fixture
  git -C "$T" tag -a v1.0.0 -m v1.0.0
  run verify_tip
  [ "$status" -ne 0 ]
  [[ "$output" == *"REFUSING TO UPDATE"* ]]
}

@test "verify_tip: refuses a tip with no release tag at all" {
  _fixture
  run verify_tip
  [ "$status" -ne 0 ]
  [[ "$output" == *"no release tag"* ]]
}

# The rolling `edge` tag is moved by CI, which holds no key. Accepting it would hand
# the workflow token exactly the power the signature exists to withhold.
@test "verify_tip: does not accept the rolling 'edge' tag as a release" {
  _fixture
  git -C "$T" tag edge
  run verify_tip
  [ "$status" -ne 0 ]
  [[ "$output" == *"no release tag"* ]]
}

@test "verify_tip: refuses when the trust anchor is missing" {
  _fixture
  _sign_tag v1.0.0 rel
  SIGNERS_SYS="$BATS_TEST_TMPDIR/absent"
  run verify_tip
  [ "$status" -ne 0 ]
  [[ "$output" == *"trust anchor"* ]]
}

@test "verify_tip: VERIFY_SIGNATURE=no pulls unverified, and says so" {
  _fixture
  VERIFY_SIGNATURE=no
  run verify_tip
  [ "$status" -eq 0 ]
  [[ "$output" == *"warn:"* ]]
}

# ── Where the anchor is read from ────────────────────────────────────────────

# The one inversion of w-sync's "prefer the freshly pulled copy" rule. Verifying a
# repository with a key taken from that repository verifies nothing, so the checkout
# path must not appear anywhere near the anchor.
@test "w-sync: the anchor is read from /usr/share/w, never from the checkout" {
  run grep -n 'REPO.*allowed_signers\|\$REPO/rootfs/usr/share/w/update/w-release' "$WSYNC"
  [ "$status" -ne 0 ]
  run grep -q 'SIGNERS_SYS="/usr/share/w/update/w-release.allowed_signers"' "$WSYNC"
  [ "$status" -eq 0 ]
}

# A verification that runs after the snapshot, or after the pull, is not a
# verification — the machine has already changed by then.
@test "w-sync: verify_tip runs before the pre-snapshot and before the pull" {
  local v s p
  v="$(grep -n '^  verify_tip$' "$WSYNC" | cut -d: -f1)"
  s="$(grep -n '^  pre_snapshot$' "$WSYNC" | cut -d: -f1)"
  p="$(grep -n 'pull --ff-only origin' "$WSYNC" | cut -d: -f1)"
  [ -n "$v" ] && [ -n "$s" ] && [ -n "$p" ]
  [ "$v" -lt "$s" ]
  [ "$v" -lt "$p" ]
}

@test "w-sync: signature checking defaults to on when update.conf predates the key" {
  run grep -q 'VERIFY_SIGNATURE="$(get_conf "$UPDATE_CONF" VERIFY_SIGNATURE yes)"' "$WSYNC"
  [ "$status" -eq 0 ]
}

# ── The publishing side (dev tree only) ──────────────────────────────────────

@test "publish.sh: signs the tag and the snapshot commit, and pushes atomically" {
  [ -f "$REPO/scripts/publish.sh" ] || skip "public tree — publish.sh is dev-only"
  run grep -q 'git_signed "$sign_key" tag -s' "$REPO/scripts/publish.sh"
  [ "$status" -eq 0 ]
  run grep -q 'git_signed "$sign_key" commit-tree -S' "$REPO/scripts/publish.sh"
  [ "$status" -eq 0 ]
  run grep -cq 'push --atomic' "$REPO/scripts/publish.sh"
  [ "$status" -eq 0 ]
}

# The gate that catches a botched key rotation: a release that ships a new anchor
# while still being signed by the old key would be refused by every machine that
# installs it, and by rule 1 it could not be taken back.
@test "publish.sh: verifies the release against the anchor inside the published tree" {
  [ -f "$REPO/scripts/publish.sh" ] || skip "public tree — publish.sh is dev-only"
  run grep -q 'gpg.ssh.allowedSignersFile=$dir/$SIGNERS_FILE" verify-tag' "$REPO/scripts/publish.sh"
  [ "$status" -eq 0 ]
}

@test "publish.sh: takes its signing key from the anchor it ships" {
  [ -f "$REPO/scripts/publish.sh" ] || skip "public tree — publish.sh is dev-only"
  run grep -q 'SIGNERS_FILE="rootfs/usr/share/w/update/w-release.allowed_signers"' "$REPO/scripts/publish.sh"
  [ "$status" -eq 0 ]
}
