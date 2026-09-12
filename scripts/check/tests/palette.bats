#!/usr/bin/env bats
# palette.bats — the wallpaper→theme colour engine (lib/w/w-theme/palette.py).
#
# The engine is the one part of `w-theme new` that can fail quietly: a bad
# mapping still produces a syntactically valid theme.conf, and the damage only
# shows up as an unreadable desktop. So the assertions here are about the
# PROPERTIES a generated theme must have (every token defined, every foreground
# legible, hex only in tier 1), not about specific colours — those may legitimately
# change when the mapping is tuned.
#
# Inputs are frozen matugen dumps (fixtures/palette/), so the suite needs neither
# matugen nor ImageMagick and stays green on a machine that ships neither.

load helpers

PALETTE="$REPO/rootfs/usr/lib/w/w-theme/palette.py"
TEMPLATE="$REPO/rootfs/etc/w/themes/w/theme.conf"
MG="$BATS_TEST_DIRNAME/fixtures/palette/matugen-purple.json"
MG_MONO="$BATS_TEST_DIRNAME/fixtures/palette/matugen-mono.json"

# Source a rendered theme and dump every W_* token it defines.
#
# `env -i` for the same reason as check/wconf.sh: the dump is "what this FILE
# defines", and a live W session exports its whole W_* theme into the
# environment. Inherited tokens would join the roster and, worse, stand in for a
# token the render dropped — the empty-value assertion below would then pass on a
# broken theme. PATH is carried through for grep and sort.
dump_theme() { # <file>
  env -i PATH="$PATH" bash --noprofile --norc -c '
    set -a; source "$1"; set +a
    for v in $(compgen -v | grep "^W_" | sort); do printf "%s=%s\n" "$v" "${!v}"; done' _ "$1"
}

setup() {
  command -v python3 >/dev/null || skip "python3 not installed"
}

@test "render: produces a theme every token of which resolves" {
  run python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance dark --name unit
  [ "$status" -eq 0 ]
  echo "$output" >"$BATS_TEST_TMPDIR/theme.conf"

  dump_theme "$BATS_TEST_TMPDIR/theme.conf" >"$BATS_TEST_TMPDIR/dump"
  # Same token roster as the baseline: a generated theme that silently drops a
  # token renders an axis with an empty colour.
  dump_theme "$TEMPLATE" | cut -d= -f1 | sort >"$BATS_TEST_TMPDIR/baseline.keys"
  cut -d= -f1 "$BATS_TEST_TMPDIR/dump" | sort >"$BATS_TEST_TMPDIR/gen.keys"
  run comm -23 "$BATS_TEST_TMPDIR/baseline.keys" "$BATS_TEST_TMPDIR/gen.keys"
  [ -z "$output" ]
  # And nothing resolves to an empty string.
  run grep -c '=$' "$BATS_TEST_TMPDIR/dump"
  [ "$output" = "0" ]
}

@test "render: hex literals stay in tier 1" {
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit >"$BATS_TEST_TMPDIR/theme.conf"
  # Only pigments may carry a hex literal (the meta tokens are not colours and
  # never match the pattern below).
  run grep -E '^W_[A-Z0-9_]+="#' "$BATS_TEST_TMPDIR/theme.conf"
  local offenders
  offenders="$(echo "$output" | grep -vE '^W_PALETTE_' || true)"
  [ -z "$offenders" ]
}

@test "render: every foreground clears its contrast target" {
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit >"$BATS_TEST_TMPDIR/theme.conf"
  dump_theme "$BATS_TEST_TMPDIR/theme.conf" >"$BATS_TEST_TMPDIR/dump"

  # The pairs W actually renders somewhere on screen, checked on the RESOLVED
  # values (tier 3 tokens, i.e. what a subsystem receives) rather than on the
  # pigments the engine reasoned about.
  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR/dump" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
tok = dict(l.split("=", 1) for l in open(sys.argv[2]).read().splitlines() if "=" in l)
pairs = [("W_TERM_FG", "W_TERM_BG", 4.5), ("W_QS_TEXT", "W_QS_SURFACE", 4.5),
         ("W_QS_ACCENT_FG", "W_QS_ACCENT", 4.5), ("W_GTK_ACCENT_FG", "W_GTK_ACCENT_BG", 4.5),
         ("W_GRUB_ITEM", "W_GRUB_BG", 4.5), ("W_QS_DANGER_FG", "W_QS_DANGER_BG", 4.5),
         ("W_LOCK_TEXT", "W_LOCK_INNER", 4.5), ("W_QS_MUTED", "W_QS_SURFACE", 3.0),
         # The shell's INK on the shell's card: button outlines, tab labels, icons.
         ("W_QS_ACCENT_INK", "W_QS_SURFACE", 4.5), ("W_QS_ICON_TINT", "W_QS_SURFACE", 4.5)]
pairs += [(f"W_TERM_ANSI_{h}", "W_TERM_BG", 4.5)
          for h in ("RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN")]
bad = [f"{f} on {b}: {palette.contrast_ratio(tok[f], tok[b]):.2f} < {t}"
       for f, b, t in pairs if palette.contrast_ratio(tok[f], tok[b]) < t]
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}

@test "render: the shell's ink is not its fill (the invisible-button regression)" {
  # A container pigment sits close to the surface it fills — that is its job — so it
  # can never also be an outline or a label. The Hub used one token for both, which
  # measured 1.94:1 on the dark card and 1.10:1 on the light one: every outline
  # button, inactive tab and shell icon was invisible on a light theme. The split is
  # W_QS_ACCENT (fill) vs W_QS_ACCENT_INK / W_QS_ICON_TINT (drawn ON the card), and
  # what makes it real is that the inks clear the card while the fill need not.
  for appearance in dark light; do
    python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance "$appearance" --name unit \
      >"$BATS_TEST_TMPDIR/t.conf"
    dump_theme "$BATS_TEST_TMPDIR/t.conf" >"$BATS_TEST_TMPDIR/ink-$appearance.dump"
  done

  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
problems = []
for appearance in ("dark", "light"):
    tok = dict(l.split("=", 1) for l in
               open(f"{sys.argv[2]}/ink-{appearance}.dump").read().splitlines() if "=" in l)
    card = tok["W_QS_SURFACE"]
    for ink in ("W_QS_ACCENT_INK", "W_QS_ICON_TINT"):
        ratio = palette.contrast_ratio(tok[ink], card)
        if ratio < 4.5:
            problems.append(f"{appearance}: {ink} on the card is {ratio:.2f} < 4.5")
    # And the two are genuinely different tokens, not the same value wired twice —
    # if a theme ever points them at one pigment again the split has been undone.
    if tok["W_QS_ACCENT_INK"] == tok["W_QS_ACCENT"]:
        problems.append(f"{appearance}: the accent ink is the accent fill again")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "render: boot marks keep the container in dark and take the accent in light" {
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance dark --name unit \
    >"$BATS_TEST_TMPDIR/dark.conf"
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance light --name unit \
    >"$BATS_TEST_TMPDIR/light.conf"
  for tok in W_PLYMOUTH_LOGO W_GRUB_LOGO; do
    grep -q "^$tok=\"\$W_PRIMARY_CONTAINER\"" "$BATS_TEST_TMPDIR/dark.conf"
    grep -q "^$tok=\"\$W_PRIMARY\""           "$BATS_TEST_TMPDIR/light.conf"
  done
}

@test "render: light mode flips the canvas and the icon theme" {
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance light --name unit \
    >"$BATS_TEST_TMPDIR/light.conf"
  dump_theme "$BATS_TEST_TMPDIR/light.conf" >"$BATS_TEST_TMPDIR/dump"

  grep -q '^W_APPEARANCE=light$' "$BATS_TEST_TMPDIR/dump"
  grep -q '^W_ICON_THEME=Papirus-Light$' "$BATS_TEST_TMPDIR/dump"
  # The root background must not stay the dark theme's absolute black.
  run grep '^W_BG=' "$BATS_TEST_TMPDIR/dump"
  [ "$output" != "W_BG=#000000" ]
  # Text has to be dark on a light surface, i.e. the ramp really inverted.
  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR/dump" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
tok = dict(l.split("=", 1) for l in open(sys.argv[2]).read().splitlines() if "=" in l)
fg = palette.rgb_to_oklch(palette.hex_to_rgb(tok["W_ON_SURFACE"]))[0]
bg = palette.rgb_to_oklch(palette.hex_to_rgb(tok["W_SURFACE"]))[0]
sys.exit(0 if fg < bg else 1)
PY
  [ "$status" -eq 0 ]
}

@test "render: --mono keeps the interface neutral but danger and ANSI coloured" {
  python3 "$PALETTE" render "$MG_MONO" "$TEMPLATE" --mono --name unit \
    >"$BATS_TEST_TMPDIR/mono.conf"
  dump_theme "$BATS_TEST_TMPDIR/mono.conf" >"$BATS_TEST_TMPDIR/dump"

  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR/dump" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
tok = dict(l.split("=", 1) for l in open(sys.argv[2]).read().splitlines() if "=" in l)
chroma = lambda t: palette.rgb_to_oklch(palette.hex_to_rgb(tok[t]))[1]
problems = []
for neutral in ("W_PRIMARY", "W_SURFACE", "W_ON_SURFACE"):
    if chroma(neutral) > 0.03:
        problems.append(f"{neutral} is not neutral ({chroma(neutral):.3f})")
# Meaning must survive the greyscale: an alarm and the terminal hues stay visible.
for coloured in ("W_DANGER", "W_TERM_ANSI_RED", "W_TERM_ANSI_GREEN"):
    if chroma(coloured) < 0.04:
        problems.append(f"{coloured} lost its hue ({chroma(coloured):.3f})")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "render: refuses a template from a different pigment roster" {
  # The old naming (W_PALETTE_PURPLE_*) is exactly what an out-of-date machine
  # would still carry; rendering against it would mix two palettes.
  sed 's/W_PALETTE_ACCENT\b/W_PALETTE_PURPLE/g' "$TEMPLATE" >"$BATS_TEST_TMPDIR/old.conf"
  run python3 "$PALETTE" render "$MG" "$BATS_TEST_TMPDIR/old.conf" --name unit
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of sync"* || "$output" == *"does not produce"* ]]
}

@test "dominant: picks the colour that carries the image, not the biggest area" {
  run python3 "$PALETTE" dominant "$BATS_TEST_DIRNAME/fixtures/palette/histogram.txt"
  [ "$status" -eq 0 ]
  # The near-black background is 12043 px and the orange only 980, but the
  # orange is what a theme should be built from.
  [[ "$output" == *"color=#C46020"* ]]
  [[ "$output" == *"scheme=scheme-content"* ]]
  [[ "$output" == *"mono=0"* ]]
}

@test "dominant: an achromatic histogram is reported as monochrome" {
  cat >"$BATS_TEST_TMPDIR/grey.txt" <<'EOF'
     900: ( 20, 20, 20) #141414 srgb(20,20,20)
     500: (140,140,140) #8C8C8C srgb(140,140,140)
EOF
  run python3 "$PALETTE" dominant "$BATS_TEST_TMPDIR/grey.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mono=1"* ]]
  [[ "$output" == *"scheme=scheme-monochrome"* ]]
}

# ── Contrast levels ───────────────────────────────────────────────────────────
# The level moves the surface ramp and scales the WCAG targets. `medium` is the
# anchor: it must keep producing the calibrated numbers, because the dark theme
# the project already likes is rendered from them.

@test "contrast: medium is the default and reproduces the calibrated ramp" {
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit >"$BATS_TEST_TMPDIR/default.conf"
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit --contrast medium \
    >"$BATS_TEST_TMPDIR/medium.conf"
  run diff "$BATS_TEST_TMPDIR/default.conf" "$BATS_TEST_TMPDIR/medium.conf"
  [ "$status" -eq 0 ]

  # The values the engine is calibrated against: feeding W's own wallpaper
  # through it lands on the hand-authored `w` surfaces (see w-theme.md).
  dump_theme "$BATS_TEST_TMPDIR/medium.conf" >"$BATS_TEST_TMPDIR/dump"
  grep -q '^W_PALETTE_SURFACE_0=#08000d$' "$BATS_TEST_TMPDIR/dump"
  grep -q '^W_PALETTE_SURFACE_2=#22002c$' "$BATS_TEST_TMPDIR/dump"
  # And the canvas is still the absolute the dark theme expects.
  grep -q '^W_BG=#000000$' "$BATS_TEST_TMPDIR/dump"
}

@test "contrast: low tints the light canvas, high leaves it white" {
  for level in low medium high; do
    python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance light --contrast "$level" \
      --name unit >"$BATS_TEST_TMPDIR/$level.conf"
    dump_theme "$BATS_TEST_TMPDIR/$level.conf" >"$BATS_TEST_TMPDIR/$level.dump"
  done

  # This is the whole point of the soft level: a light theme whose terminal and
  # file manager are tinted paper rather than a white sheet.
  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR/low.dump" "$BATS_TEST_TMPDIR/medium.dump" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
def tokens(path):
    return dict(l.split("=", 1) for l in open(path).read().splitlines() if "=" in l)
low, medium = tokens(sys.argv[2]), tokens(sys.argv[3])
problems = []
for name, tok in (("canvas", "W_BG"), ("app background", "W_APP_BG")):
    l_low, c_low, _ = palette.rgb_to_oklch(palette.hex_to_rgb(low[tok]))
    l_med, c_med, _ = palette.rgb_to_oklch(palette.hex_to_rgb(medium[tok]))
    if c_low <= c_med or c_low < 0.02:
        problems.append(f"low {name} is not tinted (chroma {c_low:.3f} vs {c_med:.3f})")
    if l_low >= l_med:
        problems.append(f"low {name} is not softer (lightness {l_low:.3f} vs {l_med:.3f})")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]

  # The crisp level goes the other way: the canvas is the absolute white.
  grep -q '^W_BG=#ffffff$' "$BATS_TEST_TMPDIR/high.dump"
  grep -q '^W_BG=#ffffff$' "$BATS_TEST_TMPDIR/medium.dump"
}

@test "contrast: every level clears the contrast targets, high by more" {
  for appearance in dark light; do
    for level in low medium high; do
      python3 "$PALETTE" render "$MG" "$TEMPLATE" --appearance "$appearance" \
        --contrast "$level" --name unit >"$BATS_TEST_TMPDIR/t.conf"
      dump_theme "$BATS_TEST_TMPDIR/t.conf" >"$BATS_TEST_TMPDIR/$appearance-$level.dump"
    done
  done

  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
def tokens(path):
    return dict(l.split("=", 1) for l in open(path).read().splitlines() if "=" in l)
pairs = [("W_TERM_FG", "W_TERM_BG", 4.5), ("W_QS_TEXT", "W_QS_SURFACE", 4.5),
         ("W_QS_ACCENT_FG", "W_QS_ACCENT", 4.5), ("W_QS_DANGER_FG", "W_QS_DANGER_BG", 4.5),
         ("W_QS_ACCENT_INK", "W_QS_SURFACE", 4.5), ("W_QS_ICON_TINT", "W_QS_SURFACE", 4.5)]
pairs += [(f"W_TERM_ANSI_{h}", "W_TERM_BG", 4.5)
          for h in ("RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN")]
problems = []
for appearance in ("dark", "light"):
    body = {}
    for level in ("low", "medium", "high"):
        tok = tokens(f"{sys.argv[2]}/{appearance}-{level}.dump")
        # Softening a theme may not cost legibility: the floors hold at every level.
        for fg, bg, target in pairs:
            ratio = palette.contrast_ratio(tok[fg], tok[bg])
            if ratio < target:
                problems.append(f"{appearance}/{level}: {fg} on {bg} is {ratio:.2f} < {target}")
        body[level] = palette.contrast_ratio(tok["W_TERM_FG"], tok["W_TERM_BG"])
    if not body["low"] < body["medium"] < body["high"]:
        problems.append(f"{appearance}: body contrast does not rise with the level ({body})")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "render: records the settings a rebuild reads back" {
  run python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit --contrast low \
    --seed "#c967e1" --seed-index 2
  [ "$status" -eq 0 ]
  # `w-theme edit` parses this line to reopen a theme on its own settings, and
  # treats its presence as "this theme was generated, so it may be rebuilt".
  [[ "$output" == *"# w-theme: seed-index=2 seed=#c967e1 contrast=low"* ]]
  [[ "$output" == *'Generated by `w-theme new unit`'* ]]
}

# ── Candidate base colours ────────────────────────────────────────────────────

@test "seeds: keeps distinct colours, drops shades and greys, preserves indices" {
  # A garden, a near-identical second green, a sky, a gold statue, a grey wall.
  run python3 "$PALETTE" seeds "#4f9d3a" "#5aa845" "#3f7fc4" "#e0a92c" "#777777"
  [ "$status" -eq 0 ]
  # The index is matugen's ranking position (what --source-color-index takes),
  # so filtering may not renumber what survives.
  [ "${lines[0]}" = "$(printf '0\t#4f9d3a')" ]
  [ "${lines[1]}" = "$(printf '2\t#3f7fc4')" ]
  [ "${lines[2]}" = "$(printf '3\t#e0a92c')" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "seeds: an image with one hue offers one choice, a grey one none" {
  run python3 "$PALETTE" seeds "#c967e1" "#b033cf"
  [ "${#lines[@]}" -eq 1 ]
  run python3 "$PALETTE" seeds "#808080" "#3a3a3a"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "json: one run answers every seed, appearance and contrast level" {
  run python3 "$PALETTE" json "$MG" "$MG_MONO" --seed "#c967e1" --seed "#808080" \
    --current-appearance light --current-contrast low --current-seed-index 1
  [ "$status" -eq 0 ]

  echo "$output" >"$BATS_TEST_TMPDIR/matrix.json"
  run python3 - "$BATS_TEST_TMPDIR/matrix.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
problems = []
# The Hub previews a click by looking into this, so every cell has to be there:
# one extraction, then dark/light and all three levels are lookups.
if len(d["seeds"]) != 2:
    problems.append(f"expected 2 seeds, got {len(d['seeds'])}")
for i, seed in enumerate(d["seeds"]):
    if seed["index"] != i:
        problems.append(f"seed {i} carries index {seed['index']}")
    for appearance in ("dark", "light"):
        for level in ("low", "medium", "high"):
            if not seed["appearance"].get(appearance, {}).get(level, {}).get("SURFACE_0"):
                problems.append(f"seed {i} has no {appearance}/{level} palette")
if [s["source"] for s in d["seeds"]] != ["#c967e1", "#808080"]:
    problems.append("source colours not echoed in order")
# Different seeds must actually produce different palettes.
if d["seeds"][0]["appearance"]["dark"]["low"] == d["seeds"][1]["appearance"]["dark"]["low"]:
    problems.append("two different seeds produced the same palette")
# An editor reopens on the theme's own cell, not on the defaults.
if d.get("current") != {"appearance": "light", "contrast": "low", "seed_index": 1}:
    problems.append(f"current settings not echoed: {d.get('current')}")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "seeds: --dump reads the colour each candidate palette was built around" {
  # How w-theme actually enumerates: matugen 4.x can select its Nth ranked source
  # colour but not list them, so each index is extracted and read back here. The
  # two fixtures stand in for two ranked candidates of one image.
  run python3 "$PALETTE" seeds --dump "$MG" --dump "$MG_MONO"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  # Each row is "<matugen index>\t<the colour that palette is built around>",
  # which is tone 60 of its primary family — not the raw source colour, which can
  # be near-black and would say nothing as a swatch.
  [[ "${lines[0]}" == "0	#"* ]]
  [[ "${lines[1]}" == "1	#"* ]]
  [ "${lines[0]#*	}" != "${lines[1]#*	}" ]
}

@test "nearest: a theme reopens on its colour, not on its old position" {
  # Measured during design on a real photograph: the original image ranks
  # fire/sky/gold/teal, the theme's own re-encoded copy fire/sky/lilac/gold. A
  # theme built from the gold at position 2 must come back to the gold, wherever
  # it now sits.
  run python3 "$PALETTE" nearest --to "#ae8d10" "#ff553a" "#5a93dc" "#b57acb" "#ae8d10"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  # And when the ranking has not moved, it is a no-op.
  run python3 "$PALETTE" nearest --to "#ae8d10" "#ff553e" "#5993dc" "#ae8d10" "#00a1a4"
  [ "$output" = "2" ]

  # No recorded colour (a theme from before the settings line) starts at the top.
  run python3 "$PALETTE" nearest --to "" "#ff553a" "#5a93dc"
  [ "$output" = "0" ]
}
