#!/usr/bin/env python3
"""Wallpaper palette engine for `w-theme new` — matugen JSON → a W theme.conf.

Pipeline (see w-theme.md):

    wallpaper → matugen (HCT extraction, Material Color Utilities)
              → THIS FILE: OKLCH model → semantic mapping → contrast pass
              → theme.conf rendered from the baseline `w` template

Why a layer of our own on top of matugen instead of consuming its roles
directly: matugen answers "what colours does this image contain", W asks "what
pigments does a W theme need". The two disagree in three places that matter.

  1. Ramp shape. W surfaces are tinted with the brand hue (the `w` surface ramp
     carries chroma 0.05 → 0.12), while matugen's neutral palette is nearly
     achromatic. So the ramp is built here, from the primary hue, at lightness
     stops calibrated against the hand-authored `w` theme.
  2. Fixed tones. matugen exposes 18 tones per family; W needs stops between
     them. In OKLCH any stop is just a lightness, so the tonal palettes serve as
     the source of hue/chroma character and the stops are synthesised.
  3. Contrast. Material role pairs are contrast-designed only within Material's
     own role set; W has its own pairs (terminal fg on terminal bg, text on the
     accent fill, ANSI colours on the canvas). Those are enforced here, by
     moving lightness in OKLCH until the WCAG ratio is met.

Everything is stdlib — the OKLab transform is 20 lines of arithmetic and pulling
numpy/Pillow into the base system for a colour conversion would be absurd.

Commands:
    dominant <histogram>                  read an ImageMagick histogram, report the
                                          colour that should seed the theme
    seeds <hex>... | --dump <mg.json>...  keep the candidate base colours that are
                                          genuinely different colours
    render <matugen.json> <template.conf> emit a theme.conf on stdout
    json   <matugen.json>...              emit the pigment matrix as JSON: every
                                          candidate seed × dark/light × every
                                          contrast level (the Hub previews the
                                          whole thing from one process)
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys

# ── OKLab / OKLCH ─────────────────────────────────────────────────────────────
# Björn Ottosson's OKLab (2020). Perceptually uniform: equal lightness steps look
# equal, and chroma is independent of hue — which is exactly why the mapping
# below can talk about "the same ramp in another hue" and mean it.


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c: float) -> float:
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def hex_to_rgb(value: str) -> tuple[float, float, float]:
    h = value.lstrip("#")
    if len(h) == 8:  # matugen may emit #rrggbbaa; the alpha is not ours to keep
        h = h[:6]
    if len(h) != 6:
        raise ValueError(f"not a #rrggbb colour: {value}")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def rgb_to_hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{round(max(0.0, min(1.0, c)) * 255):02x}" for c in rgb)


def rgb_to_oklch(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = (_srgb_to_linear(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (v ** (1 / 3) if v > 0 else -((-v) ** (1 / 3)) for v in (l, m, s))
    lightness = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return lightness, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def oklch_to_rgb(lch: tuple[float, float, float]) -> tuple[float, float, float]:
    lightness, chroma, hue = lch
    a = chroma * math.cos(math.radians(hue))
    b = chroma * math.sin(math.radians(hue))
    l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = (v**3 for v in (l_, m_, s_))
    r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return tuple(_linear_to_srgb(c) for c in (r, g, bl))  # type: ignore[return-value]


def _in_gamut(rgb: tuple[float, float, float]) -> bool:
    return all(-1e-4 <= c <= 1 + 1e-4 for c in rgb)


def oklch_to_hex(lightness: float, chroma: float, hue: float) -> str:
    """Convert to sRGB, reducing chroma until the colour actually fits the gamut.

    Clipping channels instead would shift hue — a saturated blue clips to purple.
    Chroma reduction keeps hue and lightness, which is what the mapping promised.
    """
    lightness = max(0.0, min(1.0, lightness))
    lo, hi = 0.0, max(0.0, chroma)
    if _in_gamut(oklch_to_rgb((lightness, hi, hue))):
        return rgb_to_hex(oklch_to_rgb((lightness, hi, hue)))
    for _ in range(24):
        mid = (lo + hi) / 2
        if _in_gamut(oklch_to_rgb((lightness, mid, hue))):
            lo = mid
        else:
            hi = mid
    return rgb_to_hex(oklch_to_rgb((lightness, lo, hue)))


# ── WCAG contrast ─────────────────────────────────────────────────────────────


def _relative_luminance(rgb: tuple[float, float, float]) -> float:
    r, g, b = (_srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: str, bg: str) -> float:
    a = _relative_luminance(hex_to_rgb(fg))
    b = _relative_luminance(hex_to_rgb(bg))
    lo, hi = sorted((a, b))
    return (hi + 0.05) / (lo + 0.05)


def _push_to_contrast(fg: str, bg: str, target: float, lighten: bool) -> str:
    """Move a foreground's lightness until it clears `target` against `bg`.

    Binary search on OKLCH lightness: hue and chroma stay put, so a nudged colour
    is still recognisably the colour the mapping chose. Direction is decided by
    the theme's appearance (dark themes brighten their foregrounds, light ones
    darken them), not per-colour, so the palette keeps a consistent feel.
    """
    if contrast_ratio(fg, bg) >= target:
        return fg
    lightness, chroma, hue = rgb_to_oklch(hex_to_rgb(fg))
    lo, hi = (lightness, 1.0) if lighten else (0.0, lightness)
    best = fg
    for _ in range(20):
        mid = (lo + hi) / 2
        candidate = oklch_to_hex(mid, chroma, hue)
        if contrast_ratio(candidate, bg) >= target:
            best = candidate
            if lighten:
                hi = mid
            else:
                lo = mid
        elif lighten:
            lo = mid
        else:
            hi = mid
    return best


# ── Appearance-dependent targets ──────────────────────────────────────────────
# Lightness stops are calibrated against the hand-authored `w` theme: feeding
# W's own wallpaper through this engine lands within a few thousandths of the
# pigments a human picked. The chroma factors are relative to the source colour,
# so a grey wallpaper yields a muted theme and a vivid one a punchy theme,
# without either falling outside the floors below.

CANONICAL_HUES = {  # OKLCH hue angles of the ANSI wheel
    "RED": 15.0,
    "YELLOW": 77.0,
    "GREEN": 134.0,
    "CYAN": 203.0,
    "BLUE": 273.0,
}
# How far an ANSI hue may be pulled toward the theme's accent, in degrees. Enough
# for the wheel to feel part of the theme, far too little to turn green into cyan
# — ANSI slots carry meaning (red = error) and must survive the tint.
HUE_PULL_FACTOR = 0.15
HUE_PULL_MAX_DEG = 12.0

TARGETS = {
    "dark": {
        "surface_l": (0.100, 0.145, 0.185, 0.230),
        "accent_l": {"container": 0.415, "base": 0.565, "soft": 0.655},
        "vivid_l": {"container": 0.420, "base": 0.540, "soft": 0.790},
        "text_l": {"bright": 0.920, "base": 0.689, "dim": 0.601, "faint": 0.435},
        "danger_l": {"container": 0.252, "base": 0.625, "soft": 0.913},
        "hue_l": {"normal": 0.640, "bright": 0.740},
        "lighten_fg": True,
    },
    "light": {
        # Elevation runs the other way: the canvas is the brightest surface and
        # raised containers step down, matching Material's light containers.
        "surface_l": (0.990, 0.962, 0.930, 0.892),
        "accent_l": {"container": 0.860, "base": 0.520, "soft": 0.640},
        "vivid_l": {"container": 0.880, "base": 0.500, "soft": 0.330},
        "text_l": {"bright": 0.180, "base": 0.330, "dim": 0.450, "faint": 0.600},
        "danger_l": {"container": 0.900, "base": 0.520, "soft": 0.300},
        "hue_l": {"normal": 0.520, "bright": 0.430},
        "lighten_fg": False,
    },
}

ICON_THEME = {"dark": "Papirus-Dark", "light": "Papirus-Light"}
# papirus-folders variant: folders must contrast with the file manager's canvas,
# so the choice flips with the appearance exactly like the icon theme does.
ICON_FOLDER = {"dark": "white", "light": "black"}


# ── Contrast levels ───────────────────────────────────────────────────────────
# One knob, three stops, because "pastel" and "contrast" are the same axis seen
# from two sides: a light theme reads as harsh precisely because its canvas is
# pure white with no tint left in it (the ramp above puts SURFACE_0 at lightness
# 0.990, where the chroma factor collapses to near zero), and softening it is the
# same operation as lowering contrast.
#
# What a level may NOT do is trade away legibility: the WCAG pass below still
# enforces its floors at every level, so `low` changes the CHARACTER of the theme
# (tinted paper instead of white paper) rather than its readability. `high` goes
# the other way and raises the floors toward AAA.
#
#   surface_l   where the four surfaces sit; None = keep the calibrated ramp
#   surface_c   (floor, gain, cap) for the ramp's chroma, as a fraction of accent
#               chroma: chroma = accent_c * (floor + gain * ramp) * 1.10. The
#               calibrated ramp is (0.0, 1.0) — chroma proportional to distance
#               from the canvas — so a floor is what keeps the canvas tinted.
#               `cap` is an absolute OKLCH ceiling and it is not optional at the
#               soft end: what fits in sRGB varies wildly by hue (at lightness
#               0.84 a purple tops out near chroma 0.13 but a green near 0.24),
#               so without it every colourful wallpaper would pin its surfaces to
#               the gamut boundary — a neon-green "pastel" theme, and the same
#               saturation for a washed-out image as for a vivid one.
#   canvas_l    lightness of CANVAS, the root background. 0.0/1.0 collapse to
#               black/white after gamut reduction, which is what medium and high
#               want; low lifts it so the desktop's own background belongs to the
#               palette rather than being an absolute.
#   text_shift  moves every text stop toward the canvas (negative) or away from
#               it (positive), in the direction the appearance implies.
#   ratio       multiplier on every WCAG target in CONTRAST_PAIRS.
CONTRAST_LEVELS = ("low", "medium", "high")
DEFAULT_CONTRAST = "medium"

CONTRAST = {
    "dark": {
        # Lifting the canvas off absolute black is what makes a dark theme feel
        # soft; the surfaces move with it so the elevation steps stay readable.
        "low": {
            "surface_l": (0.170, 0.208, 0.248, 0.292),
            "surface_c": (0.80, 1.00, 0.150),
            "canvas_l": 0.145,
            "text_shift": -0.040,
            "ratio": 1.00,
        },
        "medium": {
            "surface_l": None,
            "surface_c": (0.00, 1.00, None),
            "canvas_l": 0.000,
            "text_shift": 0.000,
            "ratio": 1.00,
        },
        "high": {
            "surface_l": (0.045, 0.095, 0.140, 0.185),
            "surface_c": (0.00, 0.65, None),
            "canvas_l": 0.000,
            "text_shift": +0.055,
            "ratio": 1.55,
        },
    },
    "light": {
        # The pastel end. The canvas drops off white and keeps most of the brand
        # tint, so terminals and file managers read as tinted paper — the thing a
        # light W theme could not do before.
        "low": {
            "surface_l": (0.945, 0.910, 0.874, 0.836),
            "surface_c": (0.90, 0.60, 0.065),
            "canvas_l": 0.955,
            "text_shift": -0.030,
            "ratio": 1.00,
        },
        "medium": {
            "surface_l": None,
            "surface_c": (0.00, 1.00, None),
            "canvas_l": 1.000,
            "text_shift": 0.000,
            "ratio": 1.00,
        },
        "high": {
            "surface_l": (1.000, 0.975, 0.947, 0.912),
            "surface_c": (0.00, 0.65, None),
            "canvas_l": 1.000,
            "text_shift": +0.045,
            "ratio": 1.55,
        },
    },
}


def resolve_targets(appearance: str, contrast: str) -> dict:
    """The calibrated targets with the contrast level folded in.

    `medium` must come out of here identical to the hand-calibrated table above
    — the dark theme it produces is the reference every other level is judged
    against, and it may not drift because a knob was added next to it.
    """
    if contrast not in CONTRAST_LEVELS:
        raise ValueError(f"unknown contrast level: {contrast}")
    base = TARGETS[appearance]
    mod = CONTRAST[appearance][contrast]
    t = dict(base)
    if mod["surface_l"] is not None:
        t["surface_l"] = mod["surface_l"]
    shift = mod["text_shift"] * (1 if base["lighten_fg"] else -1)
    if shift:
        t["text_l"] = {k: max(0.0, min(1.0, v + shift)) for k, v in base["text_l"].items()}
    t["surface_c"] = mod["surface_c"]
    t["canvas_l"] = mod["canvas_l"]
    t["ratio"] = mod["ratio"]
    return t


def _hue_pull(hue: float, accent_hue: float) -> float:
    arc = (accent_hue - hue + 180) % 360 - 180
    shift = max(-HUE_PULL_MAX_DEG, min(HUE_PULL_MAX_DEG, arc * HUE_PULL_FACTOR))
    return (hue + shift) % 360


# ── Reading the image itself ──────────────────────────────────────────────────
# matugen decides on its own that an image has "no good colour" and silently
# substitutes the Material baseline blue — so every greyscale wallpaper would
# produce the same unrelated blue theme. W measures the image first and tells
# matugen what to seed with, which keeps the theme tied to the picture and lets
# a genuinely achromatic wallpaper produce a genuinely neutral theme.

# Below this chroma an image carries no usable hue at all (greyscale, ink, fog).
MONO_CHROMA = 0.020
# Below this it has a hue but almost no saturation — faithful extraction would
# return mud, so the scheme that synthesises chroma is used instead.
LOW_CHROMA = 0.080

_HISTOGRAM = re.compile(r"^\s*(\d+):.*?(#[0-9A-Fa-f]{6})")


def dominant_colour(histogram: str) -> tuple[str, float]:
    """Pick the colour a theme should be built from, and report its chroma.

    An ImageMagick histogram of the quantised image gives (count, colour) pairs.
    The most frequent colour is usually the background and often near-neutral, so
    the pick is scored by share × chroma: the colour that carries the image's
    character rather than its area. Chroma is reported from that same colour, so
    a photo of a grey wall scores every cluster near zero and is called
    achromatic — which is the honest answer.
    """
    entries = []
    for line in histogram.splitlines():
        m = _HISTOGRAM.match(line)
        if m:
            entries.append((int(m.group(1)), m.group(2)))
    if not entries:
        return "#808080", 0.0
    total = sum(c for c, _ in entries) or 1
    best_hex, best_score, best_chroma = entries[0][1], -1.0, 0.0
    for count, colour in entries:
        _, chroma, _ = rgb_to_oklch(hex_to_rgb(colour))
        score = (count / total) ** 0.5 * chroma
        if score > best_score:
            best_hex, best_score, best_chroma = colour, score, chroma
    return best_hex, best_chroma


# How far apart two candidate base colours must be, in OKLCH hue degrees, to be
# offered as separate choices. matugen already de-duplicates its ranked source
# colours (Material's Score keeps them ~15° apart), but 15° is "not the same
# swatch", not "a different colour" — at that distance a user is picking between
# two shades of the same sky. This floor is what keeps the row honest: it offers
# the garden, the sky and the fountain, not three greens.
SEED_MIN_HUE_DISTANCE = 28.0
# Material's Score returns at most four ranked colours and matugen's
# --source-color-index accepts 0..3, so four is the ceiling the whole pipeline
# agrees on; images that carry fewer distinct hues yield fewer, which is the
# honest answer rather than a padded row.
SEED_MAX = 4


def filter_seeds(colours: list[str], max_count: int = SEED_MAX) -> list[tuple[int, str]]:
    """Keep the candidates that are genuinely different colours, with their index.

    The index is matugen's own ranking position, which is what
    --source-color-index addresses, so it has to survive the filtering — the list
    the user sees is a subset of matugen's, not a renumbering of it.
    """
    kept: list[tuple[int, str]] = []
    for i, colour in enumerate(colours):
        try:
            _, chroma, hue = rgb_to_oklch(hex_to_rgb(colour))
        except ValueError:
            continue
        if chroma < MONO_CHROMA:
            continue  # a grey is not a base colour to build a theme from
        if any(
            abs((hue - rgb_to_oklch(hex_to_rgb(c))[2] - 180) % 360 - 180) < SEED_MIN_HUE_DISTANCE
            for _, c in kept
        ):
            continue
        kept.append((i, colour))
        if len(kept) >= max_count:
            break
    return kept


def nearest_seed(target: str, colours: list[str]) -> int:
    """Which candidate is the colour a theme was built from, by hue.

    Reopening a generated theme cannot trust the position its settings recorded:
    matugen ranks its source colours from the image it is given, and a theme's
    stored wallpaper is a re-encode of the crop the original extraction saw, so
    the same picture can legitimately rank as fire/sky/gold/teal one time and
    fire/sky/lilac/gold the next — position 3 would then silently mean a
    different colour. The recorded hex is the stable identity, so it is matched
    against the candidates actually on offer. Hue alone, because lightness and
    chroma are exactly what the ranking and the encoder perturb.
    """
    if not colours:
        return 0
    try:
        _, _, want = rgb_to_oklch(hex_to_rgb(target))
    except ValueError:
        return 0
    def distance(colour: str) -> float:
        _, _, hue = rgb_to_oklch(hex_to_rgb(colour))
        return abs((hue - want + 180) % 360 - 180)
    return min(range(len(colours)), key=lambda i: distance(colours[i]))


def seed_colour(mg: dict) -> str:
    """The colour a dump was built around, as the swatch for that candidate.

    Tone 60 of the primary family for the same reason source_character uses it:
    it is the stop that reads the source's character most honestly across
    schemes. Not the raw source colour — that can be near-black or near-white,
    which says nothing to someone picking between swatches.
    """
    return mg["palettes"]["primary"]["60"]["color"][:7]


def scheme_for(chroma: float) -> str:
    if chroma < MONO_CHROMA:
        return "scheme-monochrome"
    if chroma < LOW_CHROMA:
        return "scheme-tonal-spot"
    return "scheme-content"


def source_character(mg: dict) -> tuple[float, float, float]:
    """(hue, chroma, error hue) of the extracted source, in OKLCH.

    Tone 60 of the primary family is the most saturated stop matugen keeps
    in-gamut across schemes, so it reads the image's character most honestly.
    """
    primary = mg["palettes"]["primary"]["60"]["color"]
    _, chroma, hue = rgb_to_oklch(hex_to_rgb(primary))
    error = mg["palettes"]["error"]["60"]["color"]
    _, _, error_hue = rgb_to_oklch(hex_to_rgb(error))
    return hue, chroma, error_hue


def build_pigments(
    mg: dict, appearance: str, mono: bool = False, contrast: str = DEFAULT_CONTRAST
) -> dict[str, str]:
    t = resolve_targets(appearance, contrast)
    hue, src_chroma, error_hue = source_character(mg)

    accent_c = max(0.055, min(0.130, src_chroma * 0.45))
    vivid_c = max(0.120, min(0.260, src_chroma * 0.95))
    wheel_c = max(0.050, min(0.150, accent_c * 0.90))
    danger_scale = min(1.0, max(0.55, src_chroma / 0.20))
    # RGB (soft/medium/crisp): chroma requests for the hardware-lighting pigments
    # below. Floors are deliberately high — an LED has no legibility floor to
    # respect (unlike ACCENT/VIVID above), so "soft" still needs to read as a
    # colour rather than a pastel wash. `crisp` asks for far more chroma than
    # sRGB has at any lightness — oklch_to_hex clamps it to the gamut edge, i.e.
    # the single most saturated colour that hue can produce.
    rgb_c = (max(0.090, min(0.160, src_chroma * 0.75)), max(0.160, min(0.230, src_chroma * 1.20)), 0.500)
    if mono:
        # A black-and-white wallpaper gets a black-and-white interface: forcing a
        # tint on it would be inventing a colour the picture does not have. What
        # stays chromatic is what carries MEANING rather than style — the danger
        # axis has to alarm, and the ANSI wheel has to keep red/green/blue apart
        # for tool output. Legibility comes from the lightness ramp either way.
        accent_c, vivid_c = 0.012, 0.030
        rgb_c = (0.025, 0.060, 0.100)

    # CANVAS is the end of the ramp — the root background behind everything. It
    # is the one "absolute" that has to flip with the appearance, whereas BLACK
    # stays black in both (shadows do not invert) and WHITE stays white (it is a
    # foreground on chromatic fills). At the calibrated contrast its lightness is
    # 0 or 1, where the gamut reduction collapses any chroma back to black or
    # white; the low-contrast levels lift it into the palette instead.
    c_floor, c_gain, c_cap = t["surface_c"]

    def surface_chroma(ramp: float) -> float:
        c = accent_c * (c_floor + c_gain * ramp) * 1.10
        return c if c_cap is None else min(c, c_cap)

    pig: dict[str, str] = {
        "BLACK": "#000000",
        "WHITE": "#ffffff",
        "CANVAS": oklch_to_hex(t["canvas_l"], surface_chroma(0.0), hue),
    }

    # Surfaces: the brand hue, chroma growing with lightness so the canvas stays
    # near-neutral while raised cards read as tinted — unless the contrast level
    # puts a floor under the chroma, which is what makes a soft theme read as
    # tinted paper rather than as a white sheet.
    top = t["surface_l"][3]
    for i, lightness in enumerate(t["surface_l"]):
        ramp = lightness / top if appearance == "dark" else (1 - lightness) / (1 - top)
        pig[f"SURFACE_{i}"] = oklch_to_hex(lightness, surface_chroma(ramp), hue)

    for slot, key in (("ACCENT_CONTAINER", "container"), ("ACCENT", "base"), ("ACCENT_SOFT", "soft")):
        chroma = accent_c * (0.56 if key == "soft" else 1.0)
        pig[slot] = oklch_to_hex(t["accent_l"][key], chroma, hue)

    for slot, key, factor in (
        ("VIVID_CONTAINER", "container", 0.75),
        ("VIVID", "base", 1.0),
        ("VIVID_SOFT", "soft", 0.92),
    ):
        pig[slot] = oklch_to_hex(t["vivid_l"][key], vivid_c * factor, hue)

    for slot, key in (("TEXT_BRIGHT", "bright"), ("TEXT", "base"), ("TEXT_DIM", "dim"), ("TEXT_FAINT", "faint")):
        lightness = t["text_l"][key]
        distance = 1 - lightness if appearance == "dark" else lightness
        pig[slot] = oklch_to_hex(lightness, min(accent_c, distance * 0.08), hue)

    for slot, key, chroma in (
        ("DANGER_CONTAINER", "container", 0.073),
        ("DANGER", "base", 0.193),
        ("DANGER_SOFT", "soft", 0.047),
    ):
        pig[slot] = oklch_to_hex(t["danger_l"][key], chroma * danger_scale, error_hue)

    for name, canonical in CANONICAL_HUES.items():
        tinted = _hue_pull(canonical, hue)
        pig[f"HUE_{name}"] = oklch_to_hex(t["hue_l"]["normal"], wheel_c, tinted)
        pig[f"HUE_{name}_BRIGHT"] = oklch_to_hex(t["hue_l"]["bright"], wheel_c, tinted)
    # Magenta is the theme's own hue — the brand tie the `w` theme makes by hand.
    pig["HUE_MAGENTA"] = oklch_to_hex(t["hue_l"]["normal"], max(wheel_c, vivid_c * 0.6), hue)
    pig["HUE_MAGENTA_BRIGHT"] = oklch_to_hex(t["hue_l"]["bright"], max(wheel_c, vivid_c * 0.6), hue)

    # RGB lighting (Hub -> Appearance -> Settings -> RGB level): a THIRD
    # calibration, deliberately separate from ACCENT/VIVID above. Those two are
    # tuned for a screen — legible as a fill or ink against a surface, and their
    # lightness rides the appearance's dark/light targets. An RGB device has
    # neither a surface to sit on nor a light/dark mode: it just needs to look
    # like the theme's colour, as vividly as the hue can go. So all three ignore
    # `t` (appearance/contrast) entirely and sit at one fixed lightness that reads
    # as a strong colour across the hue wheel — a dark theme and its light twin
    # (same wallpaper, same hue) light the keyboard identically. 0.62 sits near
    # where sRGB's gamut peaks for most hues (higher lightness narrows the gamut
    # and caps how saturated ANY chroma request can land, which is what made an
    # earlier 0.70 read as washed out on `soft` even at its chroma ceiling).
    led_l = 0.62
    pig["RGB_SOFT"] = oklch_to_hex(led_l, rgb_c[0], hue)
    pig["RGB_MEDIUM"] = oklch_to_hex(led_l, rgb_c[1], hue)
    pig["RGB_CRISP"] = oklch_to_hex(led_l, rgb_c[2], hue)

    # Foregrounds that sit ON a chromatic fill cannot be a fixed pigment: a pale
    # yellow accent needs dark text, a deep indigo one needs light text, and the
    # same is true of every light theme. Pick per fill, by contrast.
    for slot, fill in (
        ("ON_ACCENT", "ACCENT"),
        ("ON_ACCENT_CONTAINER", "ACCENT_CONTAINER"),
        ("ON_VIVID", "VIVID"),
    ):
        pig[slot] = _best_foreground(pig[fill], pig)

    # Inks: the brand hues as something DRAWN ON a surface (an outline, a label,
    # an icon) rather than as a fill. They start as their family's base tone and
    # the contrast pass below pulls them clear of SURFACE_3 — the raised card,
    # which is the hardest background in BOTH appearances (foregrounds move away
    # from the canvas, so the surface nearest them is the top of the ramp).
    #
    # This split exists because a container pigment cannot do both jobs: it is
    # built to sit close to the surface so that a fill reads as a gentle wash, and
    # that is exactly what makes it illegible as a line. Using one token for both
    # measured 1.94:1 on the dark card and 1.10:1 on the light one — invisible.
    for slot, family in (("ACCENT_INK", "ACCENT"), ("VIVID_INK", "VIVID")):
        pig[slot] = pig[family]

    return pig


def _best_foreground(fill: str, pig: dict[str, str]) -> str:
    """Pick the readable text colour for a fill: the theme's own light or dark end.

    The theme's extremes are preferred over pure white/black so the result still
    belongs to the palette; the absolutes are there for fills that neither end
    can carry (a mid-lightness accent), where legibility beats cohesion.
    """
    candidates = (pig["TEXT_BRIGHT"], pig["SURFACE_0"], "#ffffff", "#000000")
    return max(candidates, key=lambda c: contrast_ratio(c, fill))


# Pairs W actually renders. Each is (foreground pigment, background pigment,
# minimum WCAG ratio) — body text at AA 4.5, decorative/secondary at 3.0, and
# the deliberately recessive comment tone at 2.0 (it is meant to fade).
CONTRAST_PAIRS = [
    ("TEXT", "SURFACE_0", 4.5),
    ("TEXT", "SURFACE_2", 4.5),
    ("TEXT_BRIGHT", "SURFACE_0", 4.5),
    ("TEXT_DIM", "SURFACE_2", 3.0),
    ("TEXT_FAINT", "SURFACE_0", 2.0),
    ("ACCENT", "SURFACE_2", 3.0),
    ("ACCENT", "SURFACE_3", 3.0),
    ("VIVID", "SURFACE_2", 3.0),
    ("DANGER", "SURFACE_2", 3.0),
    # The inks are text-grade against the raised card: they carry button outlines,
    # tab labels and shell icons, all of which are read, not merely noticed.
    ("ACCENT_INK", "SURFACE_3", 4.5),
    ("VIVID_INK", "SURFACE_3", 4.5),
    ("DANGER_SOFT", "DANGER_CONTAINER", 4.5),
    ("VIVID_SOFT", "SURFACE_0", 4.5),
    ("ON_ACCENT", "ACCENT", 4.5),
    ("ON_ACCENT_CONTAINER", "ACCENT_CONTAINER", 4.5),
    ("ON_VIVID", "VIVID", 4.5),
] + [
    (f"HUE_{name}{variant}", "SURFACE_0", 4.5)
    for name in list(CANONICAL_HUES) + ["MAGENTA"]
    for variant in ("", "_BRIGHT")
]


def enforce_contrast(
    pig: dict[str, str], appearance: str, contrast: str = DEFAULT_CONTRAST
) -> list[str]:
    """Nudge foregrounds until every declared pair clears its ratio.

    Returns a human-readable list of what moved — the CLI surfaces it so a theme
    that needed heavy correction is not silently different from what was asked.

    The contrast level scales the targets but never below them: `low` keeps the
    same floors (AA body text stays AA — softening a theme is about its surfaces,
    not about making it harder to read), `high` raises them toward AAA.
    """
    lighten = TARGETS[appearance]["lighten_fg"]
    scale = CONTRAST[appearance][contrast]["ratio"]
    notes = []
    for fg, bg, base_target in CONTRAST_PAIRS:
        target = base_target * scale
        before = pig[fg]
        # The "on fill" foregrounds may go either way — they are chosen by
        # contrast in the first place, so keep pushing them away from the fill.
        direction = lighten
        if fg.startswith("ON_"):
            direction = rgb_to_oklch(hex_to_rgb(before))[0] > rgb_to_oklch(hex_to_rgb(pig[bg]))[0]
        after = _push_to_contrast(before, pig[bg], target, direction)
        if after != before:
            pig[fg] = after
            notes.append(f"{fg} {before}→{after} (vs {bg}, target {target:g}:1)")
    return notes


# ── theme.conf rendering ──────────────────────────────────────────────────────
# The baseline `w` theme is the structural template: its comments, tier layout
# and every Tier 2/3 wire are kept verbatim, and only the pigment values are
# swapped. Anything added to the baseline therefore reaches generated themes
# for free, and the two can never drift into different token sets.

_ASSIGN = re.compile(r'^(W_[A-Z0-9_]+)="([^"]*)"(\s*#.*)?$')

# Tier 2 roles the engine owns outright, because their correct value depends on
# the generated palette rather than on the template's choice.
ROLE_OVERRIDES = {
    "W_ON_PRIMARY": "$W_PALETTE_ON_ACCENT",
    "W_ON_PRIMARY_CONTAINER": "$W_PALETTE_ON_ACCENT_CONTAINER",
    "W_ON_ERROR": "$W_PALETTE_ON_VIVID",
    # The baseline points its root background at the absolute black, which is
    # correct for a dark theme and wrong for a light one — CANVAS carries that
    # decision instead. W_SHADOW deliberately keeps the template's black.
    "W_BG": "$W_PALETTE_CANVAS",
}

# Boot marks — the brand glyph alone on the splash / menu canvas. The dark
# container is the mark's own look (theme `w` paints it #643670 on black); the
# light container is a pale plaque, ~1.6:1 against the canvas, in which a lone
# glyph all but vanishes — so a light theme draws the mark in the accent itself.
LIGHT_OVERRIDES = {
    "W_PLYMOUTH_LOGO": "$W_PRIMARY",
    "W_GRUB_LOGO": "$W_PRIMARY",
}


class TemplateMismatch(RuntimeError):
    """The template asks for pigments this engine does not produce."""


def _verify(lines: list[str]) -> None:
    """Refuse to emit a theme whose references do not all resolve.

    The failure this guards against is quiet and nasty: a template from another W
    version names a pigment the engine no longer produces, the reference expands
    to an empty string when the theme is sourced, and the axis renders a config
    with blank colours instead of erroring. Nothing downstream notices — the
    desktop just comes up wrong. So the rendered text is checked here, before it
    is ever written, with the same rule the shipped themes are gated by.
    """
    defined: set[str] = set()
    for line in lines:
        m = _ASSIGN.match(line)
        if not m:
            continue
        token, value = m.group(1), m.group(2)
        for referenced in re.findall(r"\$\{?(W_[A-Z0-9_]+)", value):
            if referenced not in defined:
                raise TemplateMismatch(
                    f"{token} references {referenced}, which the template never defines "
                    "— the theme template and the palette engine are out of sync"
                )
        defined.add(token)


def render(
    template: str,
    pig: dict[str, str],
    appearance: str,
    name: str,
    wallpaper: str,
    contrast: str = DEFAULT_CONTRAST,
    seed: str = "",
    seed_index: int = 0,
) -> str:
    out, seen = [], set()
    for line in template.splitlines():
        m = _ASSIGN.match(line)
        if not m:
            out.append(line)
            continue
        token, _value, comment = m.group(1), m.group(2), m.group(3) or ""
        if token == "W_APPEARANCE":
            out.append(f'W_APPEARANCE="{appearance}"{comment}')
        elif token == "W_ICON_THEME":
            out.append(f'W_ICON_THEME="{ICON_THEME[appearance]}"{comment}')
        elif token == "W_ICON_FOLDER":
            out.append(f'W_ICON_FOLDER="{ICON_FOLDER[appearance]}"{comment}')
        elif token in ROLE_OVERRIDES:
            out.append(f'{token}="{ROLE_OVERRIDES[token]}"{comment}')
        elif appearance == "light" and token in LIGHT_OVERRIDES:
            out.append(f'{token}="{LIGHT_OVERRIDES[token]}"{comment}')
        elif token.startswith("W_PALETTE_"):
            slot = token[len("W_PALETTE_") :]
            seen.add(slot)
            out.append(f'{token}="{pig[slot]}"{comment}' if slot in pig else line)
        else:
            out.append(line)

    # A slot the template names but the engine cannot make means the two come
    # from different W versions. The render would still "work" — the unknown
    # pigment keeps the baseline's own value — and the result is a theme that is
    # half the wallpaper's palette and half the shipped purple. That is worse
    # than an error, so it is one.
    unknown = sorted(seen - set(pig))
    if unknown:
        raise TemplateMismatch(
            "template defines pigment(s) this engine does not produce: "
            + ", ".join("W_PALETTE_" + u for u in unknown)
        )

    missing = [s for s in pig if s not in seen]
    if missing:  # pigments the engine adds on top of the template's roster
        block = ["", "# ── Foregrounds picked by contrast against their fill ─────────────────────────"]
        block += [f'W_PALETTE_{s}="{pig[s]}"' for s in missing]
        idx = max(i for i, ln in enumerate(out) if ln.startswith("W_PALETTE_"))
        out[idx + 1 : idx + 1] = block

    _verify(out)

    # The last header line is machine-readable on purpose: `w-theme edit` reads
    # the parameters back out of it to seed its form, and rebuilding a theme from
    # its own recorded settings is the difference between "change the contrast"
    # and "make the whole thing again from scratch". It is also the marker that
    # says a theme.conf is generated at all — hand-authored themes have no such
    # line and `edit` refuses them rather than overwriting somebody's work.
    header = [
        f"# Generated by `w-theme new {name}` — do not hand-edit expecting it to survive",
        f"# a regeneration. Source wallpaper: {wallpaper}",
        "# Palette extracted with matugen (Material HCT) and mapped in OKLCH; every",
        "# foreground below clears its WCAG target against the surface it sits on.",
        f"# w-theme: seed-index={seed_index} seed={seed or 'auto'} contrast={contrast}",
        "#",
    ]
    return "\n".join(header + out) + "\n"


# ── CLI ───────────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(prog="palette.py", description="W wallpaper palette engine")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("dominant", help="pick the seed colour from an ImageMagick histogram")
    p.add_argument("histogram")

    s = sub.add_parser("seeds", help="keep the candidate base colours that differ in hue")
    s.add_argument("colour", nargs="*", help="matugen's ranked source colours, in order")
    # matugen can SELECT its Nth ranked colour but (in the shipped 4.x) cannot
    # list them, so callers discover the candidates by extracting each index and
    # hand the dumps here rather than the colours.
    s.add_argument("--dump", action="append", default=[], help="matugen dumps, ranked")
    s.add_argument("--max", type=int, default=SEED_MAX)

    n = sub.add_parser("nearest", help="which candidate is closest in hue to a colour")
    n.add_argument("--to", required=True, metavar="HEX")
    n.add_argument("colour", nargs="*")

    r = sub.add_parser("render", help="emit theme.conf")
    r.add_argument("matugen")
    r.add_argument("template")
    r.add_argument("--name", default="custom")
    r.add_argument("--wallpaper", default="")
    r.add_argument("--seed", default="", help="the source colour this palette was built from")
    r.add_argument("--seed-index", type=int, default=0, help="which candidate the seed was")

    # One process emits the whole matrix a GUI needs: every candidate seed the
    # image offers, dark and light, at every contrast level. Doing it per-cell
    # instead would mean re-cropping the image and re-running matugen on every
    # click, which is the difference between a preview that reacts and one that
    # stalls. Both appearances fit in the same run because matugen's `palettes`
    # (the only part this engine reads) are identical for -m dark and -m light —
    # the light/dark difference is entirely ours, in TARGETS.
    j = sub.add_parser("json", help="emit the pigment matrix (seeds × appearances × contrast)")
    j.add_argument("matugen", nargs="+", help="one matugen dump per candidate seed")
    j.add_argument("--seed", action="append", default=[], help="source colour of each dump, in order")
    # Echoed back untouched, so a GUI editing an existing theme learns which cell
    # of the matrix that theme currently sits in without a second query.
    j.add_argument("--current-contrast", default="")
    j.add_argument("--current-seed-index", default="")

    for q in (r, j):
        q.add_argument("--mono", action="store_true", help="the source image carries no hue")
    r.add_argument("--appearance", choices=("dark", "light"), default="dark")
    r.add_argument("--contrast", choices=CONTRAST_LEVELS, default=DEFAULT_CONTRAST)
    j.add_argument("--current-appearance", default="")

    args = ap.parse_args()

    def load(path: str) -> dict:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)

    if args.cmd == "dominant":
        with open(args.histogram, encoding="utf-8") as fh:
            colour, chroma = dominant_colour(fh.read())
        print(f"color={colour}")
        print(f"chroma={chroma:.4f}")
        print(f"scheme={scheme_for(chroma)}")
        print(f"mono={'1' if chroma < MONO_CHROMA else '0'}")
        return 0

    if args.cmd == "seeds":
        colours = [seed_colour(load(p)) for p in args.dump] if args.dump else args.colour
        for index, colour in filter_seeds(colours, args.max):
            print(f"{index}\t{colour}")
        return 0

    if args.cmd == "nearest":
        print(nearest_seed(args.to, args.colour))
        return 0

    if args.cmd == "json":
        seeds = []
        for i, path in enumerate(args.matugen):
            mg = load(path)
            cells = {}
            for appearance in ("dark", "light"):
                levels = {}
                for level in CONTRAST_LEVELS:
                    pig = build_pigments(mg, appearance, args.mono, level)
                    enforce_contrast(pig, appearance, level)
                    levels[level] = pig
                cells[appearance] = levels
            seeds.append({
                "index": i,
                # What the swatch shows: the colour this candidate's palette is
                # built around, not the raw source (which may be near-black).
                "source": args.seed[i] if i < len(args.seed) else seed_colour(mg),
                "appearance": cells,
            })
        out: dict = {"seeds": seeds}
        if args.current_contrast or args.current_seed_index or args.current_appearance:
            out["current"] = {
                "appearance": args.current_appearance or "dark",
                "contrast": args.current_contrast or DEFAULT_CONTRAST,
                "seed_index": int(args.current_seed_index or 0),
            }
        print(json.dumps(out, indent=2))
        return 0

    pig = build_pigments(load(args.matugen), args.appearance, args.mono, args.contrast)
    notes = enforce_contrast(pig, args.appearance, args.contrast)

    with open(args.template, encoding="utf-8") as fh:
        template = fh.read()
    try:
        rendered = render(template, pig, args.appearance, args.name, args.wallpaper,
                          args.contrast, args.seed, args.seed_index)
    except TemplateMismatch as exc:
        print(f"palette: {exc}", file=sys.stderr)
        return 1
    sys.stdout.write(rendered)
    for note in notes:
        print(f"palette: contrast fix — {note}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
