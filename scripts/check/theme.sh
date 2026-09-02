# check/theme.sh — the tier contract of every shipped theme.conf.
#
# theme.conf is the single source of colour for the whole distro, and since
# `w-theme new` generates themes from a wallpaper it is also a machine-written
# format. Both facts need the same guarantee: the file stays reskinnable by
# editing pigments alone. That only holds while the tiers keep their discipline,
# which nothing enforced before this suite.
#
# Contract (documented at the top of rootfs/etc/w/themes/w/theme.conf):
#   Tier 1  W_PALETTE_*   raw pigments — the ONLY place a hex literal may sit.
#                         A pigment may alias an earlier pigment (the ANSI
#                         magenta of theme `w` IS the brand vivid); every
#                         pigment needs at least one consumer — no dead ink.
#   Tier 2  W_<ROLE>      semantic roles — reference Tier 1 only, never hex.
#   Tier 3  W_<COMP>_*    component tokens — reference Tier 2, a sibling Tier 3
#                         token, or a Tier 1 pigment where no semantic role
#                         exists (the ANSI hue wheel, the shell syntax roles).
#
# Tier 3 is recognised by its component prefix (the list below); everything else
# that is not a pigment is a Tier 2 role. Non-colour meta tokens (appearance,
# widget engine, icon theme names) are exempt from the hex rule by name.
#
# The suite also closes a gap no other check covered: a token that w-style reads
# but a theme forgets to define renders as an empty string, and the axis writes a
# broken config instead of failing. So every $W_* consumed by the renderer must
# exist in EVERY theme.

# Component prefixes that mark a Tier 3 token (after the leading W_).
_THEME_TIER3_PREFIXES='TERM|HYPR|GRUB|PLYMOUTH|LOCK|QS|QT|GTK|ICON|SHELL|YAZI|DIR_HUE'
# Tokens whose value is deliberately not a colour.
_THEME_META_TOKENS='W_APPEARANCE|W_QT_STYLE|W_ICON_THEME|W_ICON_FOLDER'

chk_theme() {
  local rc=0 t
  local -a themes=()
  for t in rootfs/etc/w/themes/*/theme.conf; do [[ -f "$t" ]] && themes+=("$t"); done
  [[ ${#themes[@]} -gt 0 ]] || { echo "  no themes found under rootfs/etc/w/themes/"; return 1; }

  # Tokens the renderer reads: $W_FOO / ${W_FOO} across the w-style tree, minus
  # the ones that come from the sibling per-axis configs (font/geometry/effects/
  # motion) or from the module's own locals rather than theme.conf.
  local consumed
  consumed="$(grep -rhoE '\$\{?W_[A-Z0-9_]+' \
                rootfs/usr/lib/w/w-style/modules/*/module.sh \
                rootfs/usr/lib/w/w-style/lib/core.sh \
              | tr -d '${' | sort -u \
              | grep -vE '^W_(FONT|GEO|FX|MOTION|KDE|HOME|STYLE)' || true)"

  THEME_TIER3_PREFIXES="$_THEME_TIER3_PREFIXES" \
  THEME_META_TOKENS="$_THEME_META_TOKENS" \
  THEME_CONSUMED="$consumed" \
  python3 - "${themes[@]}" <<'PY' || rc=1
import os, re, sys

tier3 = re.compile(r'^W_(%s)' % os.environ['THEME_TIER3_PREFIXES'])
meta = re.compile(r'^(%s)$' % os.environ['THEME_META_TOKENS'])
consumed = [t for t in os.environ['THEME_CONSUMED'].split() if t]
assign = re.compile(r'^(W_[A-Z0-9_]+)="([^"]*)"\s*(#.*)?$')
ref = re.compile(r'\$\{?(W_[A-Z0-9_]+)')

rc = 0
for path in sys.argv[1:]:
    name = path.split('/')[-2]
    seen, order, used = {}, [], set()
    for n, line in enumerate(open(path), 1):
        line = line.rstrip('\n')
        if not line or line.lstrip().startswith('#'):
            continue
        m = assign.match(line)
        if not m:
            print(f'  {name}:{n}: not a `W_TOKEN="value"` assignment: {line}')
            rc = 1
            continue
        tok, val = m.group(1), m.group(2)
        if tok in seen:
            print(f'  {name}:{n}: duplicate assignment of {tok} (first at line {seen[tok]})')
            rc = 1
        seen[tok] = n
        order.append(tok)
        refs = ref.findall(val)
        used.update(refs)

        for r in refs:
            if r not in seen:
                print(f'  {name}:{n}: {tok} references {r} before it is defined')
                rc = 1

        is_pigment = tok.startswith('W_PALETTE_')
        is_tier3 = bool(tier3.match(tok))
        has_hex = val.startswith('#')

        if has_hex and not is_pigment and not meta.match(tok):
            print(f'  {name}:{n}: hex literal outside tier 1: {tok}="{val}"')
            rc = 1
        if is_pigment and not (has_hex or (refs and val == '$' + refs[0])):
            print(f'  {name}:{n}: tier 1 takes a hex literal or a pigment alias: {tok}="{val}"')
            rc = 1
        if is_pigment and refs and not all(r.startswith('W_PALETTE_') for r in refs):
            print(f'  {name}:{n}: tier 1 may only alias another pigment: {tok}="{val}"')
            rc = 1
        if not is_pigment and not is_tier3 and not meta.match(tok):
            bad = [r for r in refs if not r.startswith('W_PALETTE_')]
            if bad:
                print(f'  {name}:{n}: tier 2 role {tok} references non-pigment {", ".join(bad)}')
                rc = 1

    dead = [t for t in order if t.startswith('W_PALETTE_') and t not in used]
    if dead:
        print(f'  {name}: dead pigment(s), no consumer: {", ".join(dead)}')
        rc = 1

    missing = [t for t in consumed if t not in seen]
    if missing:
        print(f'  {name}: token(s) w-style reads but the theme never defines: {", ".join(sorted(missing))}')
        rc = 1

print(f'  themes: {len(sys.argv) - 1} checked, {len(consumed)} renderer-consumed tokens required in each')
sys.exit(rc)
PY
  return $rc
}
