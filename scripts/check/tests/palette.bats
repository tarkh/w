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

# ── Surface tone and tint ─────────────────────────────────────────────────────
# The surfaces (canvas, cards, text) may wear a colour of their own while the
# accents keep the base colour's: graphite with amber, slate with gold. Both axes
# default to the single-hue theme the engine always made, which the calibrated
# ramp test above already pins.

# Render <appearance> <tint> [surface] and dump its tokens to <out>.
render_tone() { # <out> <appearance> <tint> [surface]
  python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit --appearance "$2" --tint "$3" \
    ${4:+--surface "$4"} >"$BATS_TEST_TMPDIR/t.conf"
  dump_theme "$BATS_TEST_TMPDIR/t.conf" >"$1"
}

@test "tint: neutral is graphite with a trace of the tone, the accents keep their colour" {
  render_tone "$BATS_TEST_TMPDIR/full.dump" dark full
  render_tone "$BATS_TEST_TMPDIR/neutral.dump" dark neutral
  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR/full.dump" "$BATS_TEST_TMPDIR/neutral.dump" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
def tokens(path):
    return dict(l.split("=", 1) for l in open(path).read().splitlines() if "=" in l)
full, neutral = tokens(sys.argv[2]), tokens(sys.argv[3])
lch = lambda tok, t: palette.rgb_to_oklch(palette.hex_to_rgb(tok[t]))
problems = []
for t in ("W_PALETTE_SURFACE_3", "W_PALETTE_TEXT", "W_PALETTE_TEXT_BRIGHT"):
    _, c, h = lch(neutral, t)
    # Near-grey — but not chroma zero: an absolute grey beside a saturated accent
    # reads as the accent's complement (grey among magenta looks green).
    if not 0.003 < c < 0.02:
        problems.append(f"{t} chroma {c:.3f} is not a tinted neutral")
    elif palette._hue_distance(h, lch(full, "W_PALETTE_SURFACE_3")[2]) > 15:
        problems.append(f"{t} hue {h:.0f} left the tone")
problems += [f"{t} changed with the tint" for t in ("W_PALETTE_ACCENT", "W_PALETTE_VIVID", "W_PALETTE_ACCENT_CONTAINER")
             if full[t] != neutral[t]]
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "tint: subtle stays visibly between neutral and full at every contrast level" {
  # Scaled before the soft level's chroma cap, subtle reached the same cap as full
  # and the two rendered almost identically — a three-step control with two steps.
  run python3 - "$PALETTE" "$MG" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
mg = json.load(open(sys.argv[2]))
problems = []
for appearance in ("dark", "light"):
    for level in palette.CONTRAST_LEVELS:
        c = {tint: palette.rgb_to_oklch(palette.hex_to_rgb(
                 palette.build_pigments(mg, appearance, contrast=level, tint=tint)["SURFACE_3"]))[1]
             for tint in palette.TINT_LEVELS}
        if not c["neutral"] < c["subtle"] < 0.8 * c["full"]:
            problems.append(f"{appearance}/{level}: " + ", ".join(f"{k} {v:.3f}" for k, v in c.items()))
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "surface: the surfaces take the tone's hue, the accents keep the base colour's" {
  render_tone "$BATS_TEST_TMPDIR/accent.dump" dark full
  render_tone "$BATS_TEST_TMPDIR/sky.dump" dark full "#3f7fc4"
  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR/accent.dump" "$BATS_TEST_TMPDIR/sky.dump" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
def tokens(path):
    return dict(l.split("=", 1) for l in open(path).read().splitlines() if "=" in l)
accent, sky = tokens(sys.argv[2]), tokens(sys.argv[3])
hue = lambda tok, t: palette.rgb_to_oklch(palette.hex_to_rgb(tok[t]))[2]
want = palette.rgb_to_oklch(palette.hex_to_rgb("#3f7fc4"))[2]
problems = [f"{t} hue {hue(sky, t):.0f} is not the tone's {want:.0f}"
            for t in ("W_PALETTE_SURFACE_3", "W_PALETTE_TEXT_FAINT")
            if palette._hue_distance(hue(sky, t), want) > 10]
problems += [f"{t} followed the surface tone" for t in ("W_PALETTE_ACCENT", "W_PALETTE_VIVID")
             if accent[t] != sky[t]]
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "surface: every tone and tint clears the contrast targets" {
  for appearance in dark light; do
    for tint in neutral subtle full; do
      render_tone "$BATS_TEST_TMPDIR/$appearance-$tint.dump" "$appearance" "$tint" "#4f9d3a"
    done
  done
  run python3 - "$PALETTE" "$BATS_TEST_TMPDIR" <<'PY'
import glob, importlib.util, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
pairs = [("W_TERM_FG", "W_TERM_BG", 4.5), ("W_QS_TEXT", "W_QS_SURFACE", 4.5),
         ("W_QS_ACCENT_FG", "W_QS_ACCENT", 4.5), ("W_QS_ACCENT_INK", "W_QS_SURFACE", 4.5),
         ("W_QS_ICON_TINT", "W_QS_SURFACE", 4.5), ("W_QS_MUTED", "W_QS_SURFACE", 3.0)]
problems = []
for path in sorted(glob.glob(f"{sys.argv[2]}/*.dump")):
    tok = dict(l.split("=", 1) for l in open(path).read().splitlines() if "=" in l)
    for fg, bg, target in pairs:
        ratio = palette.contrast_ratio(tok[fg], tok[bg])
        if ratio < target:
            problems.append(f"{path.rsplit('/', 1)[1]}: {fg} on {bg} is {ratio:.2f} < {target}")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

@test "render: records the tone, tint and the verdicts a rebuild must not re-decide" {
  run python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit --surface "#1e1f23" --tint subtle \
    --scheme scheme-content
  [ "$status" -eq 0 ]
  [[ "$output" == *" surface=#1e1f23 tint=subtle scheme=scheme-content mono=0"* ]]
  # Without them a theme is the single-hue one, and says so.
  run python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit
  [[ "$output" == *" surface=accent tint=full"* ]]
}

@test "dominant: reports the ground the image is painted in, not a grey or a speck" {
  # A graphite night, faintly slate in places, with one small amber moon.
  cat >"$BATS_TEST_TMPDIR/night.txt" <<'HIST'
   45874: ( 18, 18, 18) #121212 srgb(18,18,18)
   38971: ( 45, 45, 45) #2D2D2D srgb(45,45,45)
    3331: ( 30, 31, 35) #1E1F23 srgb(30,31,35)
     102: (227,156, 24) #E39C18 srgb(227,156,24)
HIST
  run python3 "$PALETTE" dominant "$BATS_TEST_TMPDIR/night.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"color=#E39C18"* ]]
  [[ "$output" == *"ground=#1e1f23"* ]]
  # The same night re-encoded as a theme's own wallpaper: one level of blue less
  # (chroma 0.0048). It is the same ground and has to survive `w-theme edit`.
  sed -i 's/( 30, 31, 35) #1E1F23 srgb(30,31,35)/( 30, 32, 34) #1E2022 srgb(30,32,34)/' \
    "$BATS_TEST_TMPDIR/night.txt"
  run python3 "$PALETTE" dominant "$BATS_TEST_TMPDIR/night.txt"
  [[ "$output" == *"ground=#1e2022"* ]]
  # A pure grey picture has no ground tone to offer.
  printf '  900: (20,20,20) #141414 srgb(20,20,20)\n' >"$BATS_TEST_TMPDIR/grey.txt"
  run python3 "$PALETTE" dominant "$BATS_TEST_TMPDIR/grey.txt"
  [ "${lines[-1]}" = "ground=" ]
}

@test "json: every seed offers its tones × every tint" {
  run python3 "$PALETTE" json "$MG" "$MG_MONO" --seed "#c967e1" --seed "#3f7fc4" --ground "#4f9d3a" \
    --current-seed-index 0 --current-surface "#e0a92c" --current-tint subtle
  [ "$status" -eq 0 ]
  echo "$output" >"$BATS_TEST_TMPDIR/matrix.json"
  run python3 - "$BATS_TEST_TMPDIR/matrix.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
problems = []
first, second = d["seeds"]
# The ground first, then the other base colour; a recorded tone the image no
# longer offers is kept rather than dropped.
if [t["id"] for t in first["tones"]] != ["#4f9d3a", "#3f7fc4", "#e0a92c"]:
    problems.append(f"seed 0 tones: {first['tones']}")
if "#3f7fc4" in [t["id"] for t in second["tones"]]:
    problems.append("a seed offers its own colour as a separate tone")
for seed in d["seeds"]:
    # The accent tone at full tint is the plain `appearance` matrix.
    cells = [seed["appearance"], seed["tinted"]["accent"]["neutral"], seed["tinted"]["accent"]["subtle"]]
    cells += [seed["tinted"][t["id"]][tint] for t in seed["tones"] for tint in ("neutral", "subtle", "full")]
    for cell in cells:
        for appearance in ("dark", "light"):
            for level in ("low", "medium", "high"):
                if not cell[appearance][level].get("SURFACE_0"):
                    problems.append(f"seed {seed['index']}: a cell lacks {appearance}/{level}")
if d["current"].get("surface") != "#e0a92c" or d["current"].get("tint") != "subtle":
    problems.append(f"current tone not echoed: {d['current']}")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}

# The saturation axis, across hues whose gamut differs wildly at the accent's
# lightness: the purple fixture, plus the same dump re-centred on amber, teal and
# yellow (only `palettes.primary.60` and the error hue are read by the engine).
saturation_py() { # <python body>; `palette`, `dumps`, `lch`, `problems` are in scope
  python3 - "$PALETTE" "$MG" <<PY
import copy, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
base = json.load(open(sys.argv[2]))
dumps = {"purple": base}
for name, colour in (("amber", "#e39c18"), ("teal", "#2aa198"), ("yellow", "#c5c32b")):
    mg = copy.deepcopy(base); mg["palettes"]["primary"]["60"]["color"] = colour; dumps[name] = mg
lch = lambda c: palette.rgb_to_oklch(palette.hex_to_rgb(c))
problems = []
$1
print("\n".join(problems[:20]))
sys.exit(1 if problems else 0)
PY
}

@test "saturation: balanced is the theme the engine always made" {
  run diff <(python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit) \
           <(python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit --saturation balanced)
  [ "$status" -eq 0 ]
  # A balanced theme's header is the one it always had; another step is recorded.
  [[ "$(python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit)" != *"saturation="* ]]
  run python3 "$PALETTE" render "$MG" "$TEMPLATE" --name unit --tint subtle --saturation vivid
  [[ "$output" == *" tint=subtle saturation=vivid"* ]]
}

@test "saturation: muted scales every family, vivid takes a share of each slot's own room" {
  # Per slot, not per family: one family-wide ceiling once gave a dark amber
  # container the same colour on two different steps.
  run saturation_py '
fills = [s for s in palette.SATURATION_SLOTS if not s.startswith("ON_") and not s.endswith("_INK")]
for hue, mg in dumps.items():
    for appearance in ("dark", "light"):
        for level in palette.CONTRAST_LEVELS:
            pig = {s: palette.build_pigments(mg, appearance, contrast=level, saturation=s)
                   for s in palette.SATURATION_LEVELS}
            for slot in fills:
                (l, b, h), m, v = lch(pig["balanced"][slot]), lch(pig["muted"][slot])[1], lch(pig["vivid"][slot])[1]
                room = palette.fit_chroma(l, 1.0, h) - b
                where = f"{hue}/{appearance}/{level}/{slot}"
                if not m < 0.72 * b + 0.004:
                    problems.append(f"{where}: muted {m:.3f} vs balanced {b:.3f}")
                if v < b + 0.5 * palette.VIVID_GAIN * room - 0.004:
                    problems.append(f"{where}: vivid {v:.3f} from {b:.3f} with room {room:.3f}")
            for s in palette.SATURATION_LEVELS:
                # The accent never turns into the error colour.
                if not lch(pig[s]["ACCENT"])[1] < lch(pig[s]["VIVID"])[1]:
                    problems.append(f"{hue}/{appearance}/{level}/{s}: ACCENT reached VIVID")'
  [ "$status" -eq 0 ]
}

@test "saturation: only the chromatic families move, and every step clears its contrast" {
  run saturation_py '
for hue, mg in dumps.items():
    for appearance in ("dark", "light"):
        for level in palette.CONTRAST_LEVELS:
            for tint in palette.TINT_LEVELS:
                pig = {}
                for s in ("balanced", "muted", "vivid"):
                    pig[s] = palette.build_pigments(mg, appearance, contrast=level, tint=tint, saturation=s)
                    palette.enforce_contrast(pig[s], appearance, level)
                    where = f"{hue}/{appearance}/{level}/{tint}/{s}"
                    # A step clears every floor balanced clears. (Balanced itself misses
                    # ON_ACCENT on a dark high-contrast theme: the on-colour is picked
                    # before the pass lightens ACCENT. A known gap of the engine.)
                    for fg, bg, target in palette.CONTRAST_PAIRS:
                        if fg not in palette.SATURATION_SLOTS:
                            continue
                        was = palette.contrast_ratio(pig["balanced"][fg], pig["balanced"][bg])
                        need = target if was >= target else was - 0.05
                        if palette.contrast_ratio(pig[s][fg], pig[s][bg]) < need:
                            problems.append(f"{where}: {fg} on {bg} < {need:.2f}")
                    moved = [k for k in pig[s] if k not in palette.SATURATION_SLOTS and pig[s][k] != pig["balanced"][k]]
                    if moved:
                        problems.append(f"{where}: {moved} followed the saturation")
mono = json.load(open(sys.argv[2].replace("purple", "mono")))
for s in ("muted", "vivid"):
    if palette.build_pigments(mono, "dark", mono=True, saturation=s) != palette.build_pigments(mono, "dark", mono=True):
        problems.append(f"a black-and-white theme changed at {s}")'
  [ "$status" -eq 0 ]
}

@test "json: the saturation overlay is exactly what a full render makes" {
  python3 "$PALETTE" json "$MG" --seed "#c967e1" --ground "#4f9d3a" \
    --current-seed-index 0 --current-saturation vivid >"$BATS_TEST_TMPDIR/matrix.json"
  python3 "$PALETTE" json "$MG_MONO" --mono >"$BATS_TEST_TMPDIR/mono.json"
  run python3 - "$PALETTE" "$MG" "$BATS_TEST_TMPDIR/matrix.json" "$BATS_TEST_TMPDIR/mono.json" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("palette", sys.argv[1])
palette = importlib.util.module_from_spec(spec); spec.loader.exec_module(palette)
mg, d = json.load(open(sys.argv[2])), json.load(open(sys.argv[3]))
problems = []
seed = d["seeds"][0]
if sorted(seed["saturated"]) != sorted(["accent"] + [t["id"] for t in seed["tones"]]):
    problems.append(f"overlay tones: {sorted(seed['saturated'])}")
for tone, by_tint in seed["saturated"].items():
    for tint, by_sat in by_tint.items():
        if sorted(by_sat) != ["muted", "vivid"]:
            problems.append(f"{tone}/{tint}: steps {sorted(by_sat)}")
        for saturation, cells in by_sat.items():
            for appearance, levels in cells.items():
                for level, slots in levels.items():
                    full = palette.build_pigments(mg, appearance, contrast=level, surface="" if tone == "accent" else tone,
                                                  tint=tint, saturation=saturation)
                    palette.enforce_contrast(full, appearance, level)
                    if slots != {s: full[s] for s in palette.SATURATION_PREVIEW}:
                        problems.append(f"{tone}/{tint}/{saturation}/{appearance}/{level} differs from a full render")
if d["current"].get("saturation") != "vivid":
    problems.append(f"current saturation not echoed: {d['current']}")
if json.load(open(sys.argv[4]))["seeds"][0]["saturated"]:
    problems.append("a black-and-white image offers saturation steps")
print("\n".join(problems[:10]))
sys.exit(1 if problems else 0)
PY
  [ "$status" -eq 0 ]
}
