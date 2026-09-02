pragma Singleton

// W Linux — shared surface translucency scale for the Quickshell shell.
// Reads effects.json (rendered by `w-style apply effects` from the active theme's
// effects.conf — default /etc/w/themes/w/effects.conf — the same source that drives
// Hyprland's window opacity + blur), so the shell's translucency stays in sync with
// the compositor. Live-reloads on change (like Geometry / Motion).
//
// Two ways to use it:
//   • directly — `surfaceOpacity: Effects.surfaceOpacity` (a component's own default).
//   • via op() — for USER-OWNED configs (bar.json, …) an opacity value may be either
//     an absolute number (0..1) OR a token name string ("surface"/"scrim"/"bar"/
//     "barBorder"), resolved live so it follows the theme. Mirrors Geometry.px() for
//     geometry / col() for color.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Base scale (mirrors effects.json). 0..1.
    property real surfaceOpacity: 0.75    // translucent card/menu backgrounds
    property real scrimOpacity:   0.45   // dim tint of full-screen overlays

    // The bar's own chrome, held apart from the cards above: the blocks carry their
    // own zone background, so a theme that drops both of these to 0 turns the bar
    // into floating islands without thinning any other surface. Baseline themes
    // alias them to surfaceOpacity, so the bar tracks the cards until split.
    property real barOpacity:       0.75  // the bar's background plaque
    property real barBorderOpacity: 1.0  // the bar's outline (width comes from Geometry)

    // The theme's blur, as Hyprland units — mirrors effects.json, which mirrors the
    // same W_FX_BLUR_* tokens the compositor gets (including the Hub's per-user
    // Blur=off override, which w-style folds in before rendering).
    property bool blurEnabled: true
    property int  blurSize:    4
    property int  blurPasses:  3

    // In-scene blur radius for a surface the COMPOSITOR cannot frost: a modal opened
    // inside one of our own layers (the Hub's file picker) has nothing behind it but
    // its own siblings, so the shell blurs them itself with MultiEffect.
    //
    // Hyprland's dual-kawase and MultiEffect's gaussian are different algorithms, so
    // this is a deliberate approximation rather than a conversion: the radius scales
    // linearly with `size` and doubles with every `pass` (kawase halves the resolution
    // once per pass), calibrated so the baseline theme's 4/3 lands on the strength the
    // in-scene blur was designed against. Clamped to MultiEffect's useful range.
    readonly property int blurRadius:
        Math.max(4, Math.min(64, Math.round(root.blurSize * Math.pow(2, root.blurPasses - 1) * 2.5)))

    // Token-name → value map for op() string resolution.
    readonly property var tokens: ({
        "surface":   surfaceOpacity,
        "scrim":     scrimOpacity,
        "bar":       barOpacity,
        "barBorder": barBorderOpacity
    })

    // Resolve a config opacity value: a number is taken as absolute (clamped 0..1); a
    // string is a token name looked up live (so it follows `w-theme set`); anything
    // else (or an unknown token) falls back to `fallback`.
    function op(value, fallback) {
        if (typeof value === "number") return Math.max(0, Math.min(1, value));
        if (typeof value === "string" && root.tokens[value] !== undefined) return root.tokens[value];
        return fallback;
    }

    function apply(jsonText) {
        try {
            const e = JSON.parse(jsonText);
            if (e.surfaceOpacity !== undefined) root.surfaceOpacity = e.surfaceOpacity;
            if (e.scrimOpacity   !== undefined) root.scrimOpacity   = e.scrimOpacity;
            if (e.barOpacity       !== undefined) root.barOpacity       = e.barOpacity;
            if (e.barBorderOpacity !== undefined) root.barBorderOpacity = e.barBorderOpacity;
            if (e.blurEnabled    !== undefined) root.blurEnabled    = e.blurEnabled;
            if (e.blurSize       !== undefined) root.blurSize       = e.blurSize;
            if (e.blurPasses     !== undefined) root.blurPasses     = e.blurPasses;
        } catch (e) {
            // keep current/default effects on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("effects.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
