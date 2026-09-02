// W Linux — an icon belonging to the shell's OWN chrome: a Hub tile, a settings
// row, a panel section. The counterpart is ShadedIcon used directly, which stays
// for artwork standing in for something EXTERNAL — an application, a tray item, a
// notification's sender — where the icon theme's own drawing is the point.
//
// ── Why chrome icons are glyphs and not theme icons ───────────────────────────
// The Hub used to draw Papirus icons through the duotone Tint shader. That shader
// maps each pixel's own luminance onto a ramp built from the tint, which means the
// OUTPUT TONE IS A FUNCTION OF THE SOURCE ARTWORK: a light Papirus-Dark glyph
// landed on the pale end of the ramp, a dark Papirus-Light one on the dark end,
// and a colour app tile somewhere in the middle with a fifth of its original
// colour still showing (strength 0.8). Three more paths ran alongside it — Solid
// for icons that happened to have a `-symbolic` twin, Original, and the Nerd Font
// fallback for icons the theme lacked. Four render paths, side by side in one
// list, is exactly what "some icons are pale blue, some blue, some almost white"
// looks like. Flipping the icon theme with the appearance then inverted half of
// them at once.
//
// The bar never had the problem because it draws Nerd Font glyphs as plain text in
// one ink. That is what this component does for everything else:
//
//   • the glyph is the artwork (glyphFirst) — one font, one weight, one ink, and
//     the tone cannot drift with the source, because there is no source;
//   • flat Solid tint, so no luminance ramp exists to drift along;
//   • independent of the icon theme entirely, so the Papirus-Dark↔Light flip and
//     its ~3.4s qt6ct settle (core/IconTheme.qml) stop mattering here;
//   • drawn in Colors.iconTint, which the theme engine holds at 4.5:1 against the
//     raised card — the old tint was a container pigment measuring 1.05:1 on a
//     light theme.
//
// Every Hub icon already carried a curated glyph as its fallback, so this changes
// which of the two the shell prefers, not what the icons are.
//
// Degradation is honest: give it an `icon` and no `glyph` and it draws the themed
// icon flat in the same ink — still one tone, just not a glyph.
import QtQuick
import qs.core

ShadedIcon {
    id: root

    // The Nerd Font codepoint this icon is. Named `glyph` (not `fallbackGlyph`)
    // because here it is the primary artwork; it feeds the base class's slot.
    property string glyph: ""

    glyphFirst: true
    fallbackGlyph: root.glyph
    // Flat silhouette: the mode that has no luminance ramp to drift along, and the
    // right one for monochrome glyphs whether they come from the font or the theme.
    mode: ShadedIcon.Solid
    preferSymbolic: true
    tint: Colors.iconTint
}
