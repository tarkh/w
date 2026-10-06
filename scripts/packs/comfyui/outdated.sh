#!/usr/bin/env bash
# comfyui bundle — where the engine stands. Run by `w-pack outdated` (rootless)
# and `w-pack upgrade` (root, to build the plan), with:
#   BUNDLE_NAME  BUNDLE_DIR  [PACK_PLAN]
#
# Prints one TSV row, the contract in w-pack's "outdated / upgrade" section:
#   ComfyUI <installed> <target>
#
# installed — the release the checkout says it is (comfyui_version.py). The tree
#   is found through the unit's WorkingDirectory ($ROOT/app), the one place that
#   says where the RUNNING engine lives — w-conf may already name a ROOT the next
#   refresh has not moved to. Readable without root: $ROOT is 0750 comfyui:w-ai,
#   and every account that set the pack up is in w-ai.
# target — comfyui.VERSION when it holds a version, otherwise the highest stable
#   semver tag of the checkout's own origin. That is comfy-cli's own definition
#   of "latest" (it ranks tags, not GitHub's mutable releases/latest flag), and
#   ls-remote needs no API token and has no rate limit.
# `unknown` stands in for either side that cannot be read. No PACK_PLAN note:
# the move never touches torch (upgrade.sh enforces that), so there is nothing
# heavy to warn about up front.

set -uo pipefail

source /usr/lib/w/w-conf-lib.sh
wconf_load comfyui
want="$(wconf_get comfyui VERSION latest)"; want="${want#v}"

app="$(systemctl show -P WorkingDirectory comfyui.service 2>/dev/null)"
have="$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "${app:-/nonexistent}/comfyui_version.py" 2>/dev/null)"

if [[ "$want" == latest ]]; then
  origin="$(git config -f "$app/.git/config" remote.origin.url 2>/dev/null)"
  want="$(timeout 30 git ls-remote --tags --refs "${origin:-https://github.com/comfyanonymous/ComfyUI}" 'v*' 2>/dev/null \
    | sed -n 's|.*refs/tags/v\([0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' | sort -V | tail -n1)"
fi

printf 'ComfyUI\t%s\t%s\n' "${have:-unknown}" "${want:-unknown}"
