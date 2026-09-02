# check/i18n.sh — localization completeness + steps.conf references.
#
# Three surfaces, three failure modes this catches before a VM run:
#   1. TUI dicts (install/i18n/*.conf): a key added to en but not ru renders
#      as a raw key name mid-install.
#   2. steps.conf: a title/prompt i18n key or an options/validate/condition
#      function that doesn't exist fails only when the wizard reaches that row.
#   3. Quickshell (shell + greeter trees): Strings.t("x") with a key missing
#      from that tree's core/i18n.json (or missing a language) shows raw keys
#      in the UI. Only literal calls are checkable — dynamic ones (2 known,
#      Hub panel titles) are registered elsewhere and resolve at runtime,
#      which is also why unused-key detection is informational, not gating.

_i18n_keys() { grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$1" | sed 's/=$//' | sort; }

chk_i18n() {
  local rc=0 base="scripts/install/i18n"

  # 1. Dict parity — every sibling <code>.conf must carry exactly the en keys.
  #    `_`-prefixed keys are per-language metadata consumed with a `:-` fallback
  #    (_lang_name, ru-only _console_font) — exempt from parity by convention.
  local lang diff
  for lang in "$base"/*.conf; do
    [[ "$lang" == "$base/en.conf" ]] && continue
    diff="$(comm -3 <(_i18n_keys "$base/en.conf" | grep -v '^_') \
                    <(_i18n_keys "$lang" | grep -v '^_') || true)"
    [[ -z "$diff" ]] || { echo "  key mismatch en.conf vs ${lang##*/}:"; echo "$diff" | sed 's/^/    /'; rc=1; }
  done

  # 2. steps.conf: i18n keys exist; bare-identifier options/validate/condition
  #    resolve to a function defined somewhere in the installer.
  local en_keys funcs id type var title prompt opts validate cond n=0
  en_keys=" $(_i18n_keys "$base/en.conf" | tr '\n' ' ') "
  funcs=" $(grep -rhoE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\(\)' \
              scripts/install.sh scripts/install/lib scripts/install/modules \
            | tr -d ' ()' | sort -u | tr '\n' ' ') "
  while IFS='|' read -r id type var title prompt opts validate cond; do
    n=$((n + 1))
    id="${id//[[:space:]]/}"
    [[ -z "$id" || "$id" == \#* ]] && continue
    for k in $title $prompt; do
      [[ "$en_keys" == *" $k "* ]] || { echo "  steps.conf:$n ($id): i18n key not in en.conf: $k"; rc=1; }
    done
    # Whole field must be a bare identifier to be a function reference —
    # inline `[[ … ]]` condition expressions are runtime-only, skip them.
    local fn
    for fn in "${opts//[[:space:]]/}" "${validate//[[:space:]]/}" "${cond//[[:space:]]/}"; do
      [[ "$fn" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      [[ "$funcs" == *" $fn "* ]] || { echo "  steps.conf:$n ($id): function not defined: $fn"; rc=1; }
    done
  done < scripts/install/steps.conf

  # 3. Quickshell trees: each against its own dictionary.
  local tree
  for tree in rootfs/etc/skel/.config/quickshell/w rootfs/etc/greetd/quickshell/w; do
    python3 - "$tree" <<'PY' || rc=1
import json, pathlib, re, sys
tree = pathlib.Path(sys.argv[1])
d = json.load(open(tree / "core/i18n.json"))
keys = {k for k in d if k != "_comment"}
rc = 0
for k in sorted(keys):
    missing = {"en", "ru"} - set(d[k])
    if missing:
        print(f"  i18n.json ({tree.name} tree): '{k}' missing {sorted(missing)}"); rc = 1
used = set()
for f in tree.rglob("*.qml"):
    used |= set(re.findall(r'Strings\.t\("([^"]+)"\)', f.read_text()))
for k in sorted(used - keys):
    print(f"  {tree}: Strings.t(\"{k}\") has no i18n.json entry"); rc = 1
unused = keys - used
print(f"  {tree.parent.parent.name}/{tree.name}: {len(used)} used keys, {len(unused)} unreferenced (dynamic/reserve)")
sys.exit(rc)
PY
  done
  return $rc
}
