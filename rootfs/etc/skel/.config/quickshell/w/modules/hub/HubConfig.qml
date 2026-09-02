pragma Singleton

// W Linux — Hub behaviour config.
// USER-OWNED config (like LauncherConfig): w-style/w-theme never touch it. Edit
// config/hub.json and the running shell picks it up live via FileView{watchChanges}.
// Defaults below mirror the committed hub.json, so the Hub behaves sanely even if the
// file is missing or fails to parse. Later phases add the root-grid tile
// composition/order here too.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // Outer card border (outline) width. `borderCfg` holds the raw hub.json value (a
    // number OR a geometry token name like "border"/"sm"); `border` re-resolves it via
    // Geometry.px so it tracks BOTH a hub.json edit AND a Geometry change. Must stay a
    // binding (see LauncherConfig for the rationale).
    property var borderCfg: "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)

    // NOTE: the tile icon-shading knobs (iconMode/iconStrength/iconShade/iconLift)
    // are gone. Hub icons are no longer themed artwork run through the duotone
    // shader — they are the curated Nerd Font glyph, flat, in one ink (see
    // modules/shading/ChromeIcon.qml), which is what made every icon in the Hub
    // read at the same tone. There is no duotone left here to tune. A stale
    // hub.json keeping the old keys is harmless: unknown keys are ignored.

    // Appearance panel — how a theme switch transitions relative to the Hub while
    // `w-theme set` runs its (w-windowblind) crossfade:
    //   "live"   — the Hub STAYS open; the crossfade plays in place, you watch the whole
    //              theme morph A→B (the Hub is part of the frozen frame).
    //   "reveal" — the Hub steps aside (hides) first, so the full-screen crossfade shows
    //              on a clean screen, then the Hub restores itself.
    property string themeSwitch: "live"

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);
            if (c.border !== undefined)       root.borderCfg    = c.border;
            if (c.themeSwitch !== undefined)  root.themeSwitch  = c.themeSwitch;
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/hub.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
