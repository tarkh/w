pragma Singleton

// W Linux — status-bar config for the Quickshell shell.
// Like NotifConfig (and unlike Colors/Motion/Fonts, which w-style renders from the
// active theme), this is a USER-OWNED config: w-style/w-theme never touch it. Edit
// config/bar.json and the running bar picks it up live via FileView{watchChanges} —
// no restart. Defaults below mirror the committed bar.json so the bar behaves
// sanely even if the file is missing or fails to parse.
//
// Colors are resolved through col(): the value is either a theme TOKEN name (looked
// up live in Colors, so the bar follows `w-theme set`) or a literal #RRGGBB hex,
// and opacity is always a separate field — see col() below.
//
// GEOMETRY, by contrast, is THEME-owned: position/height/radii/padding/gaps/borders
// come from the active theme's geometry.conf via the Geometry singleton, live. bar.json
// need not carry any of it; writing a key back in overrides just that element (a number,
// or a geometry token name). Hence the `*Cfg` raw properties below plus a readonly
// binding that resolves "override or theme" — assigning the resolved value eagerly in
// apply() would freeze it and `w-style apply geometry` would need a relogin to land.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // ── Bar geometry / shape (theme default ← bar.json override) ──────────────
    property var positionCfg                 // "top" | "bottom"
    property var heightCfg
    property var radiusCfg                   // number (px) | "pill" (half height) | 0 (sharp)
    property var marginCfg:  ({})            // { top, bottom, left, right }
    property var paddingCfg: ({})            // { top, bottom, left, right }
    property var gapCfg
    property var borderWidthCfg
    property var minSquareCfg                 // bool — min block width = height, content centered

    readonly property string position: (positionCfg === "top" || positionCfg === "bottom")
                                       ? positionCfg : Geometry.barPosition
    readonly property int    height:   geo(heightCfg, Geometry.barHeight)
    readonly property var    radius:   radiusCfg !== undefined ? radiusCfg : Geometry.barRadius

    // The anchored edge gets the theme's edge margin, the opposite one gets 0 — so
    // flipping `position` keeps the bar floating instead of gluing it to the far edge.
    readonly property int marginTop:    geo(marginCfg.top,    position === "top"    ? Geometry.barMarginEdge : 0)
    readonly property int marginBottom: geo(marginCfg.bottom, position === "bottom" ? Geometry.barMarginEdge : 0)
    readonly property int marginLeft:   geo(marginCfg.left,   Geometry.barMarginSide)
    readonly property int marginRight:  geo(marginCfg.right,  Geometry.barMarginSide)

    readonly property int padTop:    geo(paddingCfg.top,    Geometry.barPaddingV)
    readonly property int padBottom: geo(paddingCfg.bottom, Geometry.barPaddingV)
    readonly property int padLeft:   geo(paddingCfg.left,   Geometry.barPaddingH)
    readonly property int padRight:  geo(paddingCfg.right,  Geometry.barPaddingH)

    readonly property int gap: geo(gapCfg, Geometry.barGap)   // spacing between blocks within a zone

    // Boolean, not a px-or-token geometry value — resolved directly (no geo()/px()).
    readonly property bool minSquare: minSquareCfg !== undefined ? !!minSquareCfg : Geometry.barMinSquare

    // ── Per-block shape defaults (read by blocks/*.qml) ───────────────────────
    // Each block falls back to these when its own setting is absent from bar.json.
    // radiusZone/radiusButton may be "pill" — resolve them through elemRadius().
    readonly property var radiusZone:   Geometry.barRadiusZone
    readonly property var radiusButton: Geometry.barRadiusButton
    readonly property int padZoneV:     Geometry.barPaddingZoneV   // zone inset, top/bottom
    readonly property int padZoneH:     Geometry.barPaddingZoneH   // zone padding, left/right
    readonly property int padGroup:     Geometry.barPaddingGroup   // workspaces/apps/tray, all sides
    readonly property int gapItem:      Geometry.barGapItem
    readonly property int gapButton:    Geometry.barGapButton
    readonly property int borderZone:   Geometry.barBorderZone
    readonly property int borderButton: Geometry.barBorderButton

    // ── Bar background + border ───────────────────────────────────────────────
    property string bgColor:   "surface"
    // Raw overrides from bar.json (number 0..1, or a token name — "bar"/"barBorder" are the
    // bar's own chrome pair, "surface"/"scrim" the shared shell scale). Both opacities are
    // LIVE bindings through Effects.op so they track the token AND the theme — never resolve
    // one eagerly in apply() (that froze it to Effects' load-order default; the original bug).
    property var    bgOpacityCfg: "bar"
    readonly property real bgOpacity: Effects.op(bgOpacityCfg, Effects.barOpacity)

    readonly property int borderWidth: geo(borderWidthCfg, Geometry.barBorder)   // 0 = no border
    property string borderColor:   "border"
    property var    borderOpacityCfg: "barBorder"
    readonly property real borderOpacity: Effects.op(borderOpacityCfg, Effects.barBorderOpacity)

    // ── Blocks per zone (array of { type, id, settings }) ─────────────────────
    // Stored RAW (disabled blocks included): the composition is also what the W Hub
    // lists, and it can only offer to switch a block back on if it can still see it.
    // Filtering happens at read time, per monitor — blocksFor().
    property var rawBlocks: ({ start: [], center: [], end: [] })

    // ── Multi-monitor (optional `bar.json → monitors`) ────────────────────────
    // Maps output name -> { enabled, show, blocks } — see _comment_multimonitor in
    // bar.json. `enabled` answers "is there a bar here", `show` is the sparse per-block
    // visibility override the Hub writes, `blocks` the rarely-used full composition
    // replacement.
    property var monitorCfg: ({})

    // Whether the bar should render on monitor `name`. An explicit `enabled` in the
    // monitor's entry always wins — including on the primary monitor, whose bar the Hub
    // must be able to switch off like any other. With no explicit key the primary
    // monitor (Displays.isPrimary, itself falling back when primary is unset/stale) gets
    // a bar, and any other output gets one iff it has an entry here at all.
    function barOn(name) {
        const m = root.monitorCfg[name];
        if (m && m.enabled !== undefined) return m.enabled !== false;
        if (Displays.isPrimary(name)) return true;
        return !!m;
    }

    // Whether block `b` is shown on monitor `name`. The monitor's `show` map is a sparse
    // OVERRIDE keyed by block id: present -> it decides (so a globally disabled block can
    // be revived on one output); absent -> the block's own global `enabled`.
    function shownOn(name, b) {
        const def = !b || b.enabled !== false;
        if (!b || b.id === undefined) return def;
        const m = root.monitorCfg[name];
        const show = m && m.show;
        if (show && show[b.id] !== undefined) return !!show[b.id];
        return def;
    }

    // Blocks for a given monitor + zone: that monitor's own composition if the `monitors`
    // entry defines one, else the global zone blocks. Filtering is DEEP — a zone's nested
    // `items` are per-monitor too, and Zone.qml has no way to know which screen it is on
    // (its Loader only hands it settings), so they are resolved here and handed down
    // already filtered.
    function blocksFor(name, zone) {
        const m = root.monitorCfg[name];
        const blocks = (m && m.blocks && m.blocks[zone] !== undefined) ? m.blocks[zone] : root.rawBlocks[zone];
        return (blocks || []).filter(b => b && root.shownOn(name, b)).map(b => {
            if (!b.items) return b;             // leaf block: same object, no churn
            const copy = {};
            for (const k in b) copy[k] = b[k];
            copy.items = b.items.filter(it => it && root.shownOn(name, it));
            return copy;
        });
    }

    // ── Catalog: the flat, ordered block list the W Hub renders (Appearance -> Bar) ──
    // Document order (start -> center -> end, each zone's blocks with their nested items
    // right after their parent), disabled blocks included, blocks WITHOUT an id skipped:
    // with no id there is nothing for `monitors[...].show` to key on, so the Hub cannot
    // offer a switch for them (they still render on the bar normally).
    readonly property var catalog: {
        const out = [];
        for (const z of ["start", "center", "end"]) {
            for (const b of (root.rawBlocks[z] || [])) {
                if (!b || b.id === undefined) continue;
                out.push({ id: b.id, type: b.type, zone: z, parentId: "", block: b });
                for (const it of (b.items || [])) {
                    if (!it || it.id === undefined) continue;
                    out.push({ id: it.id, type: it.type, zone: z, parentId: b.id, block: it });
                }
            }
        }
        return out;
    }

    // The catalog entry for an id, or null — lets a nested row ask about its parent
    // without walking the list itself.
    function catalogEntry(id) {
        for (const c of root.catalog) if (c.id === id) return c;
        return null;
    }

    // Human name of a block for the Hub. Shipped blocks are named by id; a hand-added
    // block of a known type still gets a name for free through the type dictionary; a
    // custom `button` falls back to its own label, then to the bare type. Strings.t()
    // echoes the key back when it is missing, so presence is checked in the table first.
    function blockTitle(b) {
        if (!b) return "";
        if (b.id !== undefined && Strings.table["bar.block." + b.id] !== undefined)
            return Strings.t("bar.block." + b.id);
        if (b.type !== undefined && Strings.table["bar.type." + b.type] !== undefined)
            return Strings.t("bar.type." + b.type);
        const lbl = b.settings ? b.settings.label : undefined;
        if (typeof lbl === "string" && lbl.length > 0) return lbl;
        return b.type || "";
    }

    // Resolve a "<token-or-#hex>" + opacity into a color. A token name maps to the
    // live theme palette (Colors), so the bar recolors on `w-theme set`; a #hex (or
    // a named color like "transparent") is taken literally. opacity defaults to 1.
    function col(name, opacity) {
        var base = Colors.surface;
        if (typeof name === "string" && name.length > 0) {
            if (name.charAt(0) === "#") base = name;
            else if (Colors[name] !== undefined) base = Colors[name];
            else base = name;            // named color, e.g. "transparent"
        }
        // Qt.darker(c, 1.0) normalizes a string/color into a color exposing r/g/b.
        var c = Qt.darker(base, 1.0);
        var o = (opacity === undefined || opacity === null) ? 1.0 : opacity;
        return Qt.rgba(c.r, c.g, c.b, o);
    }

    // Resolve a block's "icon" setting to a single glyph. The icon config is either a
    // bare string (one glyph, used for every state) or an object mapping a state key to
    // a glyph (multi-glyph blocks: volume → normal/muted, battery → levels/charging).
    // A bare string ignores `key` and degrades gracefully to the same glyph everywhere;
    // a missing key falls back. Glyphs live in bar.json as \uXXXX escapes (JSON expands
    // them on parse) so raw Nerd Font PUA chars never get dropped on file write.
    // An empty string ("") counts as unset and falls back to the block's built-in
    // default glyph (to hide an icon, use the block's showIcon:false instead). This also
    // keeps the bar working if a glyph ever drops to "" when the config is edited.
    function glyph(iconCfg, key, fallback) {
        if (iconCfg === undefined || iconCfg === null) return fallback;
        if (typeof iconCfg === "string") return iconCfg.length > 0 ? iconCfg : fallback;
        if (key !== undefined && iconCfg[key] !== undefined && iconCfg[key] !== "") return iconCfg[key];
        return fallback;
    }

    // Resolve a friendly cursor name to a Qt.CursorShape for a block's "cursor"
    // setting. An empty/missing name (or an unknown one) falls back to `fallback`,
    // which each block sets to its own sensible default (pointer for interactive
    // elements, arrow otherwise) — so the current hover feedback is preserved with
    // no config, and "cursor" only overrides it.
    function cursor(name, fallback) {
        const fb = (fallback === undefined) ? Qt.ArrowCursor : fallback;
        if (typeof name !== "string" || name.length === 0) return fb;
        switch (name) {
        case "pointer":   return Qt.PointingHandCursor;
        case "default":
        case "arrow":     return Qt.ArrowCursor;
        case "text":      return Qt.IBeamCursor;
        case "crosshair": return Qt.CrossCursor;
        case "wait":      return Qt.WaitCursor;
        case "busy":      return Qt.BusyCursor;
        case "grab":      return Qt.OpenHandCursor;
        case "grabbing":  return Qt.ClosedHandCursor;
        case "none":      return Qt.BlankCursor;
        default:          return fb;
        }
    }

    // Whether the primary monitor actually carries a bar. The shell's popups (OSD,
    // notifications, calendar, volume, brightness, the tray menu) set no `screen:` and
    // are baselined off the reserved zone below — with the bar switched off they would
    // otherwise float down by the height of a bar that isn't there.
    readonly property bool onPrimary: {
        const s = Displays.primaryScreen();
        return !!s && root.barOn(s.name);
    }

    // Screen space the bar occupies from its anchored edge (outer margin + height).
    // 0 on the opposite edge, and 0 everywhere when there is no bar on the primary
    // screen. Reacts live to height/margin/position.
    readonly property int reservedTop:    (onPrimary && position === "top")    ? marginTop    + height : 0
    readonly property int reservedBottom: (onPrimary && position === "bottom") ? marginBottom + height : 0

    // The gap Hyprland leaves between the reserved bar zone and tiled windows. Same
    // theme source as hyprland.lua's `gaps_out` (W_GEO_GAPS_OUT), so the two cannot
    // drift apart. Used to align shell popups.
    readonly property int windowGap: Geometry.gapsOut

    // Y of the top edge of tiled windows in the workspace (below the bar + gap).
    // Top-anchored popups (volume / OSD / notifications) use this as their baseline
    // so, at offset 0, their top edge sits flush with the open windows' top.
    readonly property int contentTop: reservedTop + windowGap

    // Symmetric baseline for the bottom edge: distance from the screen's bottom to
    // the bottom edge of tiled windows. Bottom-anchored popups use this the way
    // top-anchored ones use contentTop.
    readonly property int contentBottom: reservedBottom + windowGap

    // Resolve a geometry value the same way col() resolves a color: a number is taken
    // as absolute px, a string is a geometry TOKEN looked up live in the Geometry scale
    // ("radius"/"sm"/"pad"/"gap"/"barGap"…, so the bar follows the theme), otherwise
    // `fallback` — which for every bar field is the theme's own value.
    function geo(value, fallback) { return Geometry.px(value, fallback); }

    // Effective corner radius for a bar of height h. radius may be "pill" (half height),
    // a number (px), or a geometry token name (resolved via Geometry).
    function cornerRadius(h) { return Geometry.shape(root.radius, h, 0); }

    // Per-element radius for inner zone/button rectangles. Mirrors cornerRadius() but
    // for an arbitrary element of height h: "pill" = half height (even rounding), a
    // number = px, a geometry token name resolves via Geometry, else `fallback`.
    function elemRadius(value, h, fallback) { return Geometry.shape(value, h, fallback); }

    // Resolve one side of a block's "zonePadding" ({ top, bottom, left, right }); an
    // absent side falls back to the theme default the block passes in (padZoneH /
    // padZoneV for leaf blocks, padGroup for the workspaces/apps/tray button strips).
    function padOf(padCfg, side, fallback) {
        return geo(padCfg !== undefined && padCfg !== null ? padCfg[side] : undefined, fallback);
    }

    // Zone outline for a block. Width follows the theme (W_GEO_BAR_BORDER_ZONE) unless
    // the block sets "zoneBorderWidth"; color/opacity default to the theme's `border`
    // token at full alpha, so raising the width in a theme is visible with no config.
    function zoneBorderWidth(s) { return geo(s ? s.zoneBorderWidth : undefined, root.borderZone); }
    function zoneBorderColor(s) {
        return col(s && s.zoneBorderColor   !== undefined ? s.zoneBorderColor   : "border",
                   s && s.zoneBorderOpacity !== undefined ? s.zoneBorderOpacity : 1.0);
    }

    // Same contract for the buttons inside workspaces/apps/tray ("buttonBorder*").
    function buttonBorderColor(s) {
        return col(s && s.buttonBorderColor   !== undefined ? s.buttonBorderColor   : "border",
                   s && s.buttonBorderOpacity !== undefined ? s.buttonBorderOpacity : 1.0);
    }

    // Map a block type to its QML file — the single block registry, shared by Bar.qml
    // and the Zone wrapper (which renders nested blocks the same way). Adding a block =
    // a file in blocks/ + a case here. "zone" is itself a block, so zones can nest
    // (works via Loader; don't overdo it). Unknown types load nothing.
    function blockSource(type) {
        switch (type) {
        case "workspaces":     return Qt.resolvedUrl("blocks/Workspaces.qml");
        case "apps":           return Qt.resolvedUrl("blocks/Apps.qml");
        case "clock":          return Qt.resolvedUrl("blocks/Clock.qml");
        case "button":         return Qt.resolvedUrl("blocks/Button.qml");
        case "volume":         return Qt.resolvedUrl("blocks/Volume.qml");
        case "battery":        return Qt.resolvedUrl("blocks/Battery.qml");
        case "brightness":     return Qt.resolvedUrl("blocks/Brightness.qml");
        case "kbdBacklight":   return Qt.resolvedUrl("blocks/KeyboardBacklight.qml");
        case "cpu":            return Qt.resolvedUrl("blocks/Cpu.qml");
        case "ram":            return Qt.resolvedUrl("blocks/Ram.qml");
        case "temp":           return Qt.resolvedUrl("blocks/Temp.qml");
        case "disk":           return Qt.resolvedUrl("blocks/Disk.qml");
        case "keyboardLayout": return Qt.resolvedUrl("blocks/KeyboardLayout.qml");
        case "network":        return Qt.resolvedUrl("blocks/Network.qml");
        case "updates":        return Qt.resolvedUrl("blocks/Updates.qml");
        case "notifications":  return Qt.resolvedUrl("blocks/Notifications.qml");
        case "tray":           return Qt.resolvedUrl("blocks/Tray.qml");
        case "zone":           return Qt.resolvedUrl("blocks/Zone.qml");
        default:               return "";
        }
    }

    // Keep only enabled blocks. A block with "enabled": false is dropped from the model
    // entirely, so its Loader is never created and none of its background work (Process,
    // FileView, UPower/Pipewire subscriptions) ever starts. Missing key = enabled. Used
    // both here for the three zones and by Zone.qml for its nested items.
    function enabledOnly(blocks) {
        return (blocks || []).filter(b => b && b.enabled !== false);
    }

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            // Geometry overrides are stored RAW and assigned unconditionally: dropping a
            // key from bar.json must hand the field back to the theme, which only works
            // if the absent key resets *Cfg to undefined.
            root.positionCfg    = c.position;
            root.heightCfg      = c.height;
            root.radiusCfg      = c.radius;
            root.marginCfg      = c.margin  || ({});
            root.paddingCfg     = c.padding || ({});
            root.gapCfg         = c.gap;
            root.borderWidthCfg = c.borderWidth;
            root.minSquareCfg   = c.minSquare;

            if (c.bgColor       !== undefined) root.bgColor       = c.bgColor;
            if (c.bgOpacity     !== undefined) root.bgOpacityCfg  = c.bgOpacity;  // raw; bgOpacity binding resolves live
            if (c.borderColor   !== undefined) root.borderColor   = c.borderColor;
            if (c.borderOpacity !== undefined) root.borderOpacityCfg = c.borderOpacity;  // raw, as above

            const b = c.blocks || {};
            root.rawBlocks = { start: b.start || [], center: b.center || [], end: b.end || [] };

            root.monitorCfg = c.monitors || {};
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/bar.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
