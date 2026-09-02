// W Linux — ShadedIcon: the one place that recolors themed icons into the brand.
//
// Why this exists: our Quickshell surfaces draw themed icons (Papirus) as raw
// textures, and Qt (unlike GTK) does NOT recolor them to a foreground/accent — so a
// theme's full-color or monochrome glyphs render at their baked fill and clash with
// the brand. This wraps an Image in a GPU recolor pass so any consumer (volume,
// power menu, OSD, launcher,
// future bar tray) recolors icons through one shared component instead of each
// reinventing it. It is the home of the brand icon-shading system: new modes and
// effects land here and every surface inherits them.
//
// Modes:
//   Original — raw icon, no recolor. For recognizable app logos (Telegram, Firefox).
//   Tint     — premium duotone (shaders/icontint.frag): luminance is mapped onto a
//              brand gradient (darkened-accent shadows → accent mids → soft-white
//              highlights) so depth survives instead of a flat wash. `strength`
//              (0..1) mixes original ↔ duotone. macOS-like, "expensive" look.
//   Solid    — flat brand silhouette (brighten→colorize, keeps alpha). The right
//              mode for symbolic/monochrome system glyphs (power/volume/OSD).
//
// `preferSymbolic` swaps in the "<name>-symbolic" variant when present.
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.core

Item {
    id: root

    enum Mode { Original, Tint, Solid }

    property string icon: ""
    // Optional raw image source. When set, it overrides the themed-icon lookup so
    // non-theme icons (e.g. tray SNI pixmaps / image:// sources) can be shaded too —
    // the Tint/Solid passes operate on the loaded texture regardless of its origin.
    property string source: ""
    property int size: 24
    property bool preferSymbolic: false
    property int mode: ShadedIcon.Original
    property color tint: "#ffffff"
    property real strength: 1.0
    // Duotone ramp shape (Tint mode): shadow end (×tint) and highlight lift→white.
    property real shade: 0.45
    property real lift: 0.20
    property alias status: img.status

    // Default glyph rendered when no themed icon (and no raw source) resolves — the
    // single fallback for every consumer (bar taskbar, launcher, …) so a missing
    // icon never leaves an empty hole. Pass a Nerd Font codepoint via
    // String.fromCodePoint(); empty disables the fallback. Colored with the brand
    // tint by default, drawn in the mono (Nerd Font) family.
    property string fallbackGlyph: ""
    property color fallbackColor: tint
    property string fallbackFont: Fonts.mono

    // Draw the glyph even when a themed icon WOULD resolve — i.e. treat the glyph
    // as the primary artwork and the icon theme as the thing that is not wanted.
    // This is the shell-chrome policy; see ChromeIcon.qml for why the Hub uses it.
    property bool glyphFirst: false

    implicitWidth: size
    implicitHeight: size

    // Prefer the symbolic variant when asked and available; otherwise the plain name.
    //
    // The lookups go through IconTheme rather than Quickshell directly: they are
    // plain function calls with no notify signal, so these bindings would never
    // re-evaluate when the icon theme changes underneath a running shell (see
    // core/IconTheme.qml — this is what left tray icons on the old theme until a
    // restart).
    readonly property string _name: (preferSymbolic && icon.length > 0
                                     && IconTheme.has(icon + "-symbolic"))
                                    ? icon + "-symbolic" : icon
    readonly property bool _has: _name.length > 0 && IconTheme.has(_name)

    // Glyph-only: the consumer asked for the glyph and supplied one, and there is
    // no raw source to honour. Deliberately independent of img.status — deriving
    // it from the load state would make the Image's own source depend on it.
    readonly property bool _glyphOnly: root.glyphFirst && root.fallbackGlyph.length > 0
                                       && root.source.length === 0
    // The icon this component draws, before cache-busting: a consumer's raw source
    // (tray SNI images) wins over the themed lookup.
    readonly property string _url: root._glyphOnly ? ""
                                   : (root.source.length > 0 ? root.source
                                      : (root._has ? IconTheme.path(root._name) : ""))
    // No real icon to draw (or none wanted) → show the fallback glyph.
    readonly property bool _fallback: fallbackGlyph.length > 0 && source.length === 0
                                      && (_glyphOnly || !_has || img.status === Image.Error)

    Image {
        id: img
        anchors.fill: parent
        sourceSize.width: root.size
        sourceSize.height: root.size
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        // Quickshell resolves themed icons to the provider URL image://icon/<name>,
        // which is identical before and after a theme switch — so the pixmap cache,
        // keyed by URL, would keep serving the old theme's icon forever. bust()
        // varies the URL per icon-theme change; the few URLs it cannot vary skip the
        // cache instead and are reloaded explicitly below.
        source: IconTheme.bust(root._url)
        cache: !IconTheme.needsUncached(root._url)
        // Shown directly only in Original mode; otherwise it stays a hidden texture
        // provider for the effect below.
        visible: root.mode === ShadedIcon.Original
    }

    // The uncacheable case: same URL, so nothing above re-evaluates. Drop the source
    // and restore the binding (not a bare assignment — the item's icon may still
    // change later, e.g. a tray applet swapping its glyph, and a broken binding
    // would freeze it).
    Connections {
        target: IconTheme
        enabled: IconTheme.needsUncached(root._url)
        function onRevisionChanged() {
            img.source = "";
            img.source = Qt.binding(() => IconTheme.bust(root._url));
        }
    }

    // Tint: premium duotone via the brand fragment shader.
    ShaderEffect {
        anchors.fill: parent
        visible: root.mode === ShadedIcon.Tint && img.status === Image.Ready
        property var source: img
        property color tintColor: root.tint
        property real strength: root.strength
        property real shade: root.shade
        property real lift: root.lift
        fragmentShader: "shaders/icontint.frag.qsb"
    }

    // Solid: flat brand silhouette for symbolic/monochrome glyphs.
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: root.mode === ShadedIcon.Solid && img.status === Image.Ready
        // Brighten the source to white first so colorization yields a flat brand
        // silhouette (recolors monochrome/symbolic glyphs cleanly, keeps alpha).
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.tint
    }

    // Fallback glyph: shown only when nothing else resolves to a drawable icon.
    // Nerd Font icon glyphs carry asymmetric side bearings AND vertical offset (the
    // ink sits off-centre inside its layout box), so plain centering drifts. Center
    // the layout box (anchors.centerIn) and then nudge by the delta between the
    // layout box center and the real ink center (tightBoundingRect) — both metrics
    // share the same baseline origin, so the offset is origin-independent per axis.
    TextMetrics {
        id: glyphMetrics
        font: glyphText.font
        text: root.fallbackGlyph
    }
    Text {
        id: glyphText
        anchors.centerIn: parent
        anchors.horizontalCenterOffset:
            (glyphMetrics.boundingRect.x + glyphMetrics.boundingRect.width / 2)
            - (glyphMetrics.tightBoundingRect.x + glyphMetrics.tightBoundingRect.width / 2)
        anchors.verticalCenterOffset:
            (glyphMetrics.boundingRect.y + glyphMetrics.boundingRect.height / 2)
            - (glyphMetrics.tightBoundingRect.y + glyphMetrics.tightBoundingRect.height / 2)
        visible: root._fallback
        text: root.fallbackGlyph
        color: root.fallbackColor
        font.family: root.fallbackFont
        font.pixelSize: root.size
    }
}
