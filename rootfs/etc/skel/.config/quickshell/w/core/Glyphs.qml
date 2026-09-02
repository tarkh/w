pragma Singleton

// W Linux — the shell's glyph vocabulary: one codepoint per CONCEPT, named once.
//
// Why it exists: the same thing was drawn with different glyphs in different
// places. Volume was nf-fa `volume-up` in the bar and nf-md `volume-high` on the
// Hub tile; brightness was nf-fa `sun` in the bar and nf-md `brightness-7` on the
// tile — so the bar's volume icon and the OSD that pops up right under it when you
// press the volume key came from two different icon families. Nothing enforced a
// choice because there was no place to make one. This is that place: a surface
// asks for a CONCEPT, not for a number.
//
// **nf-md (Material Design) is the canon.** Most of the shell was already on it,
// and it carries states nf-fa does not (volume levels, battery levels), so the
// two nf-fa holdouts in the bar were pulled onto it rather than the other way
// round.
//
// Codepoints are verified against the shipped JetBrainsMono Nerd Font's cmap, not
// copied from a cheat sheet — a merely plausible codepoint renders as tofu, and
// only on the target. They are written with String.fromCodePoint() so this file
// stays pure ASCII (the same rule bar.json follows with \uXXXX escapes: raw PUA
// characters do not survive every editor and pipeline intact).
//
// Scope: concepts drawn in more than one surface. A glyph used in exactly one
// place stays at its call site — this is a vocabulary, not a dumping ground.
import Quickshell

Singleton {
    id: root

    // ── Audio ─────────────────────────────────────────────────────────────────
    readonly property string volumeHigh:   String.fromCodePoint(0xf057e)  // md-volume_high
    readonly property string volumeMedium: String.fromCodePoint(0xf0580)  // md-volume_medium
    readonly property string volumeLow:    String.fromCodePoint(0xf057f)  // md-volume_low
    readonly property string volumeOff:    String.fromCodePoint(0xf0581)  // md-volume_off (muted)
    readonly property string micOn:        String.fromCodePoint(0xf036c)  // md-microphone
    readonly property string micOff:       String.fromCodePoint(0xf036d)  // md-microphone_off

    // ── Display ───────────────────────────────────────────────────────────────
    readonly property string brightness:   String.fromCodePoint(0xf00e0)  // md-brightness_7
    readonly property string kbdBacklight: String.fromCodePoint(0xf030c)  // md-keyboard

    // ── Session ───────────────────────────────────────────────────────────────
    // Session memory: the Hub's mode selector and the curtain shown while
    // `w-session restore` deals the windows back out — two surfaces for one
    // concept, which is what puts it here rather than at either call site.
    // Codepoints here are VERIFIED AGAINST THE SHIPPED FONT, not remembered: the
    // Nerd Font Material range is dense and adjacent code points are unrelated
    // pictures, so a wrong digit does not fail — it draws something else with full
    // confidence. All three glyphs below were mislabelled at first (0xf05d0 is a
    // sticker, 0xf1665 a heart-with-cog, 0xf0762 a taco), which is exactly how the
    // mistake presents: the comment says one thing and the screen shows another.
    // To check one: read the cmap of RobotoMonoNerdFont and compare the glyph NAME.
    readonly property string sessionRestore: String.fromCodePoint(0xf099b)  // md-restore
    // The layouts panel: one glyph per scope, because the badge and the row have
    // to agree about what a row IS at a glance.
    readonly property string layoutAll:       String.fromCodePoint(0xf0a1d)  // md-view_dashboard_outline
    readonly property string layoutWorkspace: String.fromCodePoint(0xf11d9)  // md-view_grid_outline

    // The speaker glyph for a level, so the OSD, the audio popup and the bar
    // cannot disagree about where the thresholds sit. Muted outranks any level.
    function volume(value, muted) {
        if (muted || value <= 0.0001) return root.volumeOff;
        if (value < 0.34) return root.volumeLow;
        if (value < 0.67) return root.volumeMedium;
        return root.volumeHigh;
    }

    function mic(muted) {
        return muted ? root.micOff : root.micOn;
    }
}
