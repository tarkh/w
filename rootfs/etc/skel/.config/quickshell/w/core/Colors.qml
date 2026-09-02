pragma Singleton

// W Linux — design-system palette for the Quickshell shell.
// Reads colors.json (rendered by `w-style apply quickshell` from the active
// theme's theme.conf) and live-reloads on change via FileView{watchChanges}, so
// `w-theme set` recolors a running shell with no signal/restart. Defaults below
// match the committed colors.json (theme `w`) so the UI is themed even if the
// file is missing or fails to parse.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property color backdrop: "#140020"  // full-screen tint hue behind launcher
    property color surface:  "#2e0045"  // launcher card background
    property color inputBg:  "#200030"  // search field background
    property color text:     "#a197a4"  // primary text (app names)
    property color muted:    "#8a7a8e"  // secondary text / placeholder
    property color accent:   "#643670"  // FILL for a selected row / active tile
    property color accentFg: "#ffffff"  // text on that fill
    // The accent as INK — a button outline, a tab label, an icon. Held at 4.5:1
    // against the raised card by the theme engine. `accent` cannot do this job:
    // it is a container pigment, built to sit close to the surface it fills, and
    // on a light theme that measured 1.10:1 — an invisible button. Anything drawn
    // ON a surface uses this; anything that fills a shape uses `accent`.
    property color accentInk: "#91619b"
    property color border:   "#91619b"  // card border accent

    property color iconTint: "#c44bdf"      // brand color the shell's icons are drawn in
    // Not a colour: the icon theme the active W theme names (Papirus-Dark/-Light).
    // The shell watches it to notice that themed icons must be re-requested — see
    // core/IconTheme.qml for why that is not automatic.
    property string iconTheme: "Papirus-Dark"

    // Danger (critical alerts — red-shifted, stands apart from the brand purple).
    property color dangerBg:     "#3d0f1d"  // critical card background
    property color dangerFg:     "#ffd6dd"  // text on critical card
    property color dangerBorder: "#e34666"  // critical card border

    // Hover wash. Derived, not a theme token, so the relationship is guaranteed:
    // `accentInk` is the one colour the engine promises stands clear of the card,
    // so a low-alpha layer of it is visible in every theme by construction. The
    // old hover used `inputBg` — a neighbouring step of the surface ramp, which
    // measured 1.10:1 (dark) and 1.13:1 (light) against the card, i.e. no visible
    // feedback in either appearance.
    // The alphas are picked by measurement, not taste: over the raised card they
    // land at ΔL≈0.085 (hover) and ΔL≈0.13 (selection) in OKLCH, and — because the
    // ink is defined relative to the card — they measure the same in a dark theme
    // and a light one. The ramp step they replaced was ΔL 0.038, which is why
    // hovering a tile used to look like nothing happening.
    readonly property color hover: root.alpha(root.accentInk, 0.22)
    // The same wash, one step up: a row that is SELECTED or a dropdown that is
    // OPEN, i.e. a state that outranks hover but stops short of the solid accent
    // fill an active tile gets.
    readonly property color selection: root.alpha(root.accentInk, 0.34)

    // A colour at a different alpha. Chiefly for the REST state of anything that
    // animates its fill: `"transparent"` is rgba(0,0,0,0), and ColorAnimation
    // interpolates the channels straight, so a fade from it drags every colour
    // through black — the grey flash on a light theme's tiles and dropdowns. The
    // rest state must be the destination colour at alpha 0, never the literal.
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.backdrop) root.backdrop = c.backdrop;
            if (c.surface)  root.surface  = c.surface;
            if (c.inputBg)  root.inputBg  = c.inputBg;
            if (c.text)     root.text     = c.text;
            if (c.muted)    root.muted    = c.muted;
            if (c.accent)   root.accent   = c.accent;
            if (c.accentFg) root.accentFg = c.accentFg;
            if (c.accentInk) root.accentInk = c.accentInk;
            if (c.border)   root.border   = c.border;
            if (c.iconTint) root.iconTint = c.iconTint;
            if (c.iconTheme) root.iconTheme = c.iconTheme;
            if (c.dangerBg)     root.dangerBg     = c.dangerBg;
            if (c.dangerFg)     root.dangerFg     = c.dangerFg;
            if (c.dangerBorder) root.dangerBorder = c.dangerBorder;
        } catch (e) {
            // keep current/default colors on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("colors.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
