#!/usr/bin/env bash
# invokeai bundle — where the engine stands. Run by `w-pack outdated` (rootless)
# and `w-pack upgrade` (root, to build the plan), with:
#   BUNDLE_NAME  BUNDLE_DIR  [PACK_PLAN]
#
# Prints one TSV row, the contract in w-pack's "outdated / upgrade" section:
#   InvokeAI <installed> <target> [<note>]
#
# installed — the invokeai dist-info in the venv the unit runs (WorkingDirectory
#   is $ROOT/data, the venv $ROOT/app/.venv). Readable without root through w-ai.
# target — invokeai.VERSION when it holds a version, otherwise PyPI's current
#   release (info.version skips pre-releases).
# note (PACK_PLAN=1, root only) — whether the move brings a different torch.
#   InvokeAI pins torch per release, and a new torch is the multi-GB part of an
#   upgrade (and the part that broke ROCm before, #9410), so the plan says so
#   BEFORE the question is asked. A uv dry-run as the service account, with the
#   torch backend read off the installed build: metadata only, nothing installed.

set -uo pipefail

source /usr/lib/w/w-conf-lib.sh
wconf_load invokeai
want="$(wconf_get invokeai VERSION latest)"; want="${want#v}"

data="$(systemctl show -P WorkingDirectory invokeai.service 2>/dev/null)"
ROOT="${data%/data}"
VENV="$ROOT/app/.venv"
dist_version() {                                        # <dist> → version from the dist-info name
  local d; d="$(compgen -G "$VENV/lib/python3*/site-packages/$1-*.dist-info" | head -n1)"
  [[ -n "$d" ]] || return 0
  d="${d##*/"$1"-}"; echo "${d%.dist-info}"
}
have="$(dist_version invokeai)"

if [[ "$want" == latest ]]; then
  want="$(curl -fsS -m 30 https://pypi.org/pypi/invokeai/json 2>/dev/null | jq -r '.info.version // empty' 2>/dev/null)"
fi

note=""
if [[ "${PACK_PLAN:-0}" == 1 && $EUID -eq 0 && -n "$have" && -n "$want" && "$have" != "$want" ]]; then
  torch="$(dist_version torch)"
  if [[ "$torch" == *+* ]]; then
    if ! new="$(cd "$ROOT" && runuser -u invokeai -- env HOME="$ROOT" PATH=/usr/bin:/bin \
      uv pip install --dry-run --python "$VENV/bin/python" --python-preference only-managed \
      --torch-backend="${torch#*+}" "invokeai==$want" 2>&1)"; then
      note="the dependency resolution fails — the upgrade would not go through"
    else
      new="$(sed -n 's/^ + torch==\(.*\)$/\1/p' <<< "$new")"
      if [[ -n "$new" ]]; then note="brings torch $torch → $new, a multi-GB download"
      else note="torch $torch stays"; fi
    fi
  fi
fi

printf 'InvokeAI\t%s\t%s\t%s\n' "${have:-unknown}" "${want:-unknown}" "$note"
