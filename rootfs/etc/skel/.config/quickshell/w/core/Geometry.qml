pragma Singleton

// W Linux — shared geometry scale for the Quickshell shell.
// Reads geometry.json (rendered by `w-style apply geometry` from the active theme's
// geometry.conf — default /etc/w/themes/w/geometry.conf — the same source that renders
// Hyprland's window gaps/border/rounding), so the shell's roundness/spacing stays in
// sync with the compositor. Live-reloads on change (like Motion).
//
// Two ways to use it:
//   • directly — `radius: Geometry.radius` (a component's own default).
//   • via px() — for USER-OWNED configs (bar.json, …) a geometry value may be either
//     an absolute number (px) OR a token name string ("radius"/"sm"/"pad"/"gap"),
//     resolved live so the value follows the theme. Mirrors BarConfig.col() for colors.
//
// The `bar*` block below is the status bar's shape (position/height/radii/padding/gaps/
// borders). It lives here — not in bar.json — because it is theme-owned: bar.json keeps
// the bar's composition and colors and may still override any single value per element.
// Radii are `var`, not `int`: they carry either a number or the keyword "pill" (half the
// element's height), resolved by shape() at the point of use.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Base scale (mirrors geometry.json). Pixels.
    property int radius:   14   // large surfaces: popups, menus, cards, notifications
    property int radiusSm:  8   // small/inner: buttons, pills, thumbnails
    property int padding:  12   // base inner padding of cards/popups
    property int gap:       6   // base spacing between elements
    property int border:    1   // outer border (outline) width of cards/popups
    property int gapsOut:   8   // Hyprland's window↔screen-edge gap; shell popups align to it

    // Status bar shape (mirrors geometry.json → "bar").
    property string barPosition:      "top"   // "top" | "bottom"
    property int    barHeight:         32
    property int    barMarginEdge:      6     // bar ↔ the screen edge it is anchored to
    property int    barMarginSide:      8     // bar ↔ left/right screen edges
    property var    barRadius:         "pill" // bar surface
    property var    barRadiusZone:     "pill" // a block's zone background
    property var    barRadiusButton:   "pill" // buttons inside workspaces/apps/tray
    property int    barPaddingV:        2     // bar inner padding, top/bottom
    property int    barPaddingH:        2     // bar inner padding, left/right
    property int    barPaddingZoneV:    0     // zone inset from the content band, top/bottom
    property int    barPaddingZoneH:    8     // zone inner padding, left/right
    property int    barPaddingGroup:    2     // button-strip zones, all four sides
    property int    barGap:             4     // between blocks inside a bar zone
    property int    barGapItem:         2     // between nested blocks inside a `zone` block
    property int    barGapButton:       4     // between buttons inside workspaces/apps/tray
    property int    barBorder:          0     // outline of the bar surface
    property int    barBorderZone:      0     // outline of a block's zone background
    property int    barBorderButton:    0     // outline of buttons inside workspaces/apps/tray
    property bool   barMinSquare:    true     // min block width = height, content centered

    // Token-name → value map for px()/shape() string resolution. Friendly aliases included
    // so configs can read naturally ("md"/"lg" = radius, "sm" = radiusSm, "pad" = padding).
    // The bar tokens let bar.json re-attach a single field to the theme after overriding it.
    readonly property var tokens: ({
        "radius":   radius,   "lg":  radius,   "md": radius,
        "radiusSm": radiusSm, "sm":  radiusSm,
        "padding":  padding,  "pad": padding,
        "gap":      gap,
        "border":   border,
        "gapsOut":  gapsOut,
        "barHeight":       barHeight,
        "barMarginEdge":   barMarginEdge,   "barMarginSide":   barMarginSide,
        "barRadius":       barRadius,
        "barRadiusZone":   barRadiusZone,   "barRadiusButton": barRadiusButton,
        "barPaddingV":     barPaddingV,     "barPaddingH":     barPaddingH,
        "barPaddingZoneV": barPaddingZoneV, "barPaddingZoneH": barPaddingZoneH,
        "barPaddingGroup": barPaddingGroup,
        "barGap":          barGap,          "barGapItem":      barGapItem,
        "barGapButton":    barGapButton,
        "barBorder":       barBorder,       "barBorderZone":   barBorderZone,
        "barBorderButton": barBorderButton
    })

    // Resolve a config geometry value to PIXELS: a number is taken as absolute px; a
    // string is a geometry token name looked up live (so it follows `w-theme set`);
    // anything else — an unknown token, or a token whose value is a keyword like "pill"
    // that only shape() can turn into a number — falls back to `fallback`.
    function px(value, fallback) {
        if (typeof value === "number") return value;
        if (typeof value === "string") {
            const t = root.tokens[value];
            if (typeof t === "number") return t;
        }
        return fallback;
    }

    // Resolve a corner radius for an element of height `h`. Same inputs as px() plus the
    // keyword "pill" (directly or via a token) = h/2, an even stadium rounding that tracks
    // the element's height. Used by the bar for its surface, zones and buttons.
    function shape(value, h, fallback) {
        var v = (typeof value === "string" && root.tokens[value] !== undefined) ? root.tokens[value] : value;
        if (v === "pill") return h / 2;
        if (typeof v === "number") return v;
        return fallback;
    }

    function apply(jsonText) {
        try {
            const g = JSON.parse(jsonText);
            if (g.radius   !== undefined) root.radius   = g.radius;
            if (g.radiusSm !== undefined) root.radiusSm = g.radiusSm;
            if (g.padding  !== undefined) root.padding  = g.padding;
            if (g.gap      !== undefined) root.gap      = g.gap;
            if (g.border   !== undefined) root.border   = g.border;
            if (g.gapsOut  !== undefined) root.gapsOut  = g.gapsOut;

            const b = g.bar;
            if (b) {
                if (b.position     !== undefined) root.barPosition     = b.position;
                if (b.height       !== undefined) root.barHeight       = b.height;
                if (b.marginEdge   !== undefined) root.barMarginEdge   = b.marginEdge;
                if (b.marginSide   !== undefined) root.barMarginSide   = b.marginSide;
                if (b.radius       !== undefined) root.barRadius       = b.radius;
                if (b.radiusZone   !== undefined) root.barRadiusZone   = b.radiusZone;
                if (b.radiusButton !== undefined) root.barRadiusButton = b.radiusButton;
                if (b.paddingV     !== undefined) root.barPaddingV     = b.paddingV;
                if (b.paddingH     !== undefined) root.barPaddingH     = b.paddingH;
                if (b.paddingZoneV !== undefined) root.barPaddingZoneV = b.paddingZoneV;
                if (b.paddingZoneH !== undefined) root.barPaddingZoneH = b.paddingZoneH;
                if (b.paddingGroup !== undefined) root.barPaddingGroup = b.paddingGroup;
                if (b.gap          !== undefined) root.barGap          = b.gap;
                if (b.gapItem      !== undefined) root.barGapItem      = b.gapItem;
                if (b.gapButton    !== undefined) root.barGapButton    = b.gapButton;
                if (b.border       !== undefined) root.barBorder       = b.border;
                if (b.borderZone   !== undefined) root.barBorderZone   = b.borderZone;
                if (b.borderButton !== undefined) root.barBorderButton = b.borderButton;
                if (b.minSquare    !== undefined) root.barMinSquare    = b.minSquare;
            }
        } catch (e) {
            // keep current/default geometry on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("geometry.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
