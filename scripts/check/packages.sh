# check/packages.sh — package list hygiene (+ optional existence probe).
#
# A single stale name aborts the whole `pacman -S` transaction under set -e
# (the neofetch→fastfetch class), and a bad AUR name dies mid-firstboot.
# Offline: format + duplicates. With --online: every official name is asked
# from archlinux.org, every AUR name from the RPC — the only check here that
# needs network, hence opt-in (rolling repos change under us, not with us).
#
# The ISO's own list (archiso/profile/packages.x86_64) is covered too, and was
# not until 2026-09-02. It cost a broken nightly: `broadcom-wl` was dropped from
# the repositories, and because this suite only ever read packages/*.txt the
# green `check` job was followed by mkarchiso dying on `target not found` in the
# middle of pacstrap. It is checked SEPARATELY from packages/*.txt rather than
# merged into the same table — the live ISO and the installed system are two
# different machines, so the same name legitimately appears in both.

_pkg_names() { sed 's/#.*//' "$1" | tr -d ' \t' | grep -v '^$' || true; }

chk_packages() {
  local rc=0 f p
  declare -A WHERE=()
  for f in packages/base.txt packages/pacman.txt packages/aur.txt; do
    while IFS= read -r p; do
      [[ "$p" =~ ^[A-Za-z0-9@._+][A-Za-z0-9@._+-]*$ ]] \
        || { echo "  ${f##*/}: invalid package name: '$p'"; rc=1; continue; }
      if [[ -n "${WHERE[$p]:-}" ]]; then
        echo "  ${f##*/}: duplicate of ${WHERE[$p]}: $p"; rc=1
      fi
      WHERE[$p]="${f##*/}"
    done < <(_pkg_names "$f")
  done
  echo "  package lists: ${#WHERE[@]} unique names"

  local iso=archiso/profile/packages.x86_64
  declare -A ISOSEEN=()
  if [[ -f "$iso" ]]; then
    while IFS= read -r p; do
      [[ "$p" =~ ^[A-Za-z0-9@._+][A-Za-z0-9@._+-]*$ ]] \
        || { echo "  ${iso##*/}: invalid package name: '$p'"; rc=1; continue; }
      [[ -z "${ISOSEEN[$p]:-}" ]] || { echo "  ${iso##*/}: duplicate: $p"; rc=1; }
      ISOSEEN[$p]=1
    done < <(_pkg_names "$iso")
    echo "  ISO list: ${#ISOSEEN[@]} unique names"
  else
    echo "  ISO list not found: $iso"; rc=1
  fi

  if [[ ${ONLINE:-0} -eq 1 ]]; then
    python3 - <<'PY' || rc=1
import json, sys, time, urllib.parse, urllib.request

def names(path):
    out = []
    for line in open(path):
        line = line.split("#")[0].strip()
        if line: out.append(line)
    return out

# A definitive "no such name" (HTTP 200, empty results) fails the suite; a
# network hiccup is indeterminate — retried, then reported without failing
# (this probe is an opt-in diagnostic, flaky Wi-Fi must not turn it red).
def fetch(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                return json.load(r)
        except Exception as e:
            err = e; time.sleep(2 * attempt + 1)
    raise err

rc = 0; unreachable = []
official = sorted(set(names("packages/base.txt") + names("packages/pacman.txt")
                      + names("archiso/profile/packages.x86_64")))
print(f"  online: probing {len(official)} official + AUR names...")
for p in official:
    try:
        d = fetch(f"https://archlinux.org/packages/search/json/?name={urllib.parse.quote(p)}")
        if not d["results"]:
            print(f"  not in official repos: {p}"); rc = 1
    except Exception:
        unreachable.append(p)

aur = names("packages/aur.txt")
if aur:
    try:
        q = "&".join("arg[]=" + urllib.parse.quote(p) for p in aur)
        found = {x["Name"] for x in fetch(f"https://aur.archlinux.org/rpc/v5/info?{q}")["results"]}
        for p in set(aur) - found:
            print(f"  not in AUR: {p}"); rc = 1
    except Exception:
        unreachable += aur

if unreachable:
    print(f"  warning: {len(unreachable)} probes unreachable (network) — rerun when stable: {' '.join(unreachable[:5])}...")
sys.exit(rc)
PY
  fi
  return $rc
}
