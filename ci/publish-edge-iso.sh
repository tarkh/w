#!/usr/bin/env bash
# ci/publish-edge-iso.sh — put the freshly built ISO in front of users.
#
# W publishes exactly ONE install image: the current tree, rebuilt nightly and
# again whenever someone dispatches edge-iso by hand — a release on its own no
# longer triggers a build. There are no per-version images on purpose —
# on a rolling distro an image is a bootstrap medium, not an artifact of record
# (an old ISO installs old packages and then immediately updates), and a shelf
# of stale downloads only makes a newcomer pick the wrong one. So this maintains
# one rolling pre-release, tagged `edge`, whose single asset is replaced by
# every run. Version releases carry their source archives, which GitHub attaches
# on its own, and nothing else.
#
# Two details that would otherwise quietly lie:
#
#   * The asset keeps the name build-iso.sh gave it — w-<release>-<date>-x86_64
#     .iso — so the file on someone's disk still says which release it is and
#     which day it was assembled. The previous asset is deleted only AFTER the
#     new one is uploaded, so a failed upload never leaves the page empty.
#   * A release's tag does not follow its assets. Left alone, `edge` would go on
#     pointing at the commit of the very first run while the image moved on, and
#     the "Source code" archives GitHub shows under it would come from a tree
#     that is not the one the image was built from. The ref is repointed here.
#
# Needs GH_TOKEN with contents:write. Called by .github/workflows/edge-iso.yml.
set -euo pipefail

TAG="${W_EDGE_TAG:-edge}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set — this runs in Actions}"
SHA="${GITHUB_SHA:?GITHUB_SHA not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;35m==>\033[0m $*"; }

mapfile -t ISOS < <(find "$REPO_DIR/archiso/out" -maxdepth 1 -name '*.iso' -print | sort)
[[ ${#ISOS[@]} -eq 1 ]] || die "expected exactly one ISO in archiso/out, found ${#ISOS[@]}"
ISO="${ISOS[0]}"
ISO_NAME="$(basename "$ISO")"
ISO_SIZE="$(du -h "$ISO" | cut -f1)"
ISO_SHA="$(sha256sum "$ISO" | cut -d' ' -f1)"

# GitHub refuses release assets over 2 GiB. At 1.5 GB there is room, but the
# margin is what shrinks as W grows, so fail loudly here rather than at upload.
ISO_BYTES="$(stat -c%s "$ISO")"
(( ISO_BYTES < 2147483648 )) \
  || die "ISO is $ISO_SIZE — over GitHub's 2 GiB asset limit. Time for real hosting."
# And a step before that: a hard stop the day the image outgrows the limit is a
# broken nightly with no runway. Warn at 1.8 GiB, where there is still time to
# move the download to real hosting deliberately (planned alongside Ф.6).
(( ISO_BYTES < 1932735283 )) \
  || echo -e "\033[1;33mWARN:\033[0m ISO is $ISO_SIZE — within 10% of GitHub's 2 GiB asset limit." >&2

RELEASE="$(sed -n 's/^IMAGE_VERSION=//p' "$REPO_DIR/rootfs/etc/os-release" | tr -d '"')"
BUILD_DATE="$(date -u +%Y.%m.%d)"

info "$ISO_NAME ($ISO_SIZE) · release $RELEASE · commit ${SHA:0:8}"

# ── The rolling release ───────────────────────────────────────────────────────
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  info "Repointing tag '$TAG' at ${SHA:0:8}..."
  gh api -X PATCH "repos/$REPO/git/refs/tags/$TAG" -f "sha=$SHA" -F force=true >/dev/null
else
  info "Creating the rolling pre-release '$TAG'..."
  gh release create "$TAG" --repo "$REPO" --target "$SHA" --prerelease \
    --title "W install image — edge" --notes "Building..."
fi

info "Uploading $ISO_NAME..."
gh release upload "$TAG" "$ISO" --repo "$REPO" --clobber

# Only now is it safe to drop what the previous run left.
while read -r stale; do
  [[ -n "$stale" && "$stale" != "$ISO_NAME" ]] || continue
  info "Deleting superseded asset $stale"
  gh release delete-asset "$TAG" "$stale" --repo "$REPO" --yes
done < <(gh release view "$TAG" --repo "$REPO" --json assets --jq '.[][].name')

# ── The page a human reads before downloading ─────────────────────────────────
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<EOF
The W install image, rebuilt every night from the tip of \`main\` and again
after every release. This is the only image W publishes — there is no separate
per-version download.

| | |
|---|---|
| **File** | \`$ISO_NAME\` |
| **Release** | $RELEASE |
| **Built** | $BUILD_DATE (UTC) |
| **From commit** | [\`${SHA:0:8}\`](https://github.com/$REPO/commit/$SHA) |
| **Size** | $ISO_SIZE |
| **SHA-256** | \`$ISO_SHA\` |

W is a rolling distribution, so the release number and the build date say two
different things: \`$RELEASE\` is which version of W's own configuration this is,
and $BUILD_DATE is the day its packages were pulled from Arch. Both are recorded
in \`/etc/os-release\` on the installed system as \`IMAGE_VERSION\` and
\`W_BUILD_DATE\`. An image of the same release built a month apart is a different
set of packages — that is normal, and it is why this download is rebuilt nightly
instead of being frozen per version.

\`\`\`
sha256sum $ISO_NAME
\`\`\`
EOF
gh release edit "$TAG" --repo "$REPO" --notes-file "$NOTES" >/dev/null
info "Published: https://github.com/$REPO/releases/tag/$TAG"
