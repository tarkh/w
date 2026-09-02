pragma Singleton

// W Linux — notification & OSD behaviour config for the Quickshell shell.
// Unlike Colors/Motion/Fonts (rendered by w-style from the active theme), this is
// a USER-OWNED config: it is NOT touched by w-style/w-theme. Edit notifications.json
// and the running shell picks it up live via FileView{watchChanges} — no restart.
// Defaults below mirror the committed notifications.json, so the shell behaves
// sanely even if the file is missing or fails to parse.
//
// Two files feed this singleton, and the shell writes NEITHER of them — `w-notify` is
// the single writer of both, so the Hub panel, the bar block, a hotkey and the AI all
// go through one place and can never race each other on JSON:
//   ~/.config/quickshell/w/config/notifications.json   preferences (timeouts, mute…)
//   ~/.local/state/w/notifications.json                DND on/off state
// The split is deliberate: preferences are hand-editable config, DND is volatile
// runtime state that a bar click flips several times a day. (Quickshell's own stateDir
// is not used for it — it has no change watch, and w-notify/the AI must read it too.)
//
// A DND deadline needs no daemon: `w-notify dnd for/until` stores an ABSOLUTE epoch and
// every reader derives "is it still on?" from the clock, so an expired deadline can
// never leave two readers disagreeing.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    // ── Layout (all popups share one fixed width AND height for consistency) ──
    property int  cardWidth:   360
    property int  cardHeight:  96
    property int  gap:         8     // vertical gap between stacked notifications
    property int  maxVisible:  5     // hard cap of on-screen notifications
    property int  marginTop:   8     // stack offset from the top edge
    property int  marginRight: 8     // stack offset from the right edge
    // Fine-tune the vertical position relative to the bar-aware baseline (the open
    // windows' top edge). 0 = flush with that edge; +down / -up. marginTopOffset →
    // notification stack; osdMarginTopOffset → the center popups (OSD + Volume Control).
    property int  marginTopOffset:    0
    property int  osdMarginTopOffset: 0
    // Defaults follow the theme's Geometry scale (база); notifications.json may still
    // override per field with an absolute number OR a geometry token name (override).
    property int  padding:     Geometry.padding   // inner card padding
    property int  radius:      Geometry.radius     // card corner radius
    property int  imageRadius: 10                  // thumbnail corner radius (notif-specific)
    // Outer card border width (notif cards + OSD). borderCfg = raw json value (number or
    // token); border = live binding via Geometry.px (tracks json edit AND Geometry change).
    property var  borderCfg:    "border"
    readonly property int border: Geometry.px(borderCfg, Geometry.border)
    // Card background translucency (notif cards + OSD), from the effects axis (база);
    // notifications.json layout.surfaceOpacity may override (number or "surface"/"scrim").
    // Content (text/icons) stays opaque — only the card fill carries the alpha.
    // surfaceOpacityCfg = raw json value (number or token); surfaceOpacity is a LIVE binding via
    // Effects.op (tracks json edit AND theme) — never resolve eagerly (Effects load-order bug).
    property var  surfaceOpacityCfg: "surface"
    readonly property real surfaceOpacity: Effects.op(surfaceOpacityCfg, Effects.surfaceOpacity)

    // ── Text limits ──────────────────────────────────────────────────────────
    property int  titleMaxChars: 64
    property int  bodyMaxLines:  3
    property int  bodyMaxChars:  160

    // ── Timeouts (milliseconds; 0 = stay until manually dismissed) ───────────
    property int  timeoutLow:      4000
    property int  timeoutNormal:   6000
    property int  timeoutCritical: 0
    property int  timeoutOsd:      1600

    // ── Do Not Disturb ───────────────────────────────────────────────────────
    // Behaviour lives in the config; the on/off STATE lives in the state file below.
    property bool dndAllowCritical:  true    // let critical alerts through DND
    property bool dndAutoFullscreen: false   // auto-DND while a window is fullscreen
    // App names (Notification.appName) whose popups are dropped. Muting is absolute —
    // unlike DND it is an explicit per-app choice, so critical does NOT bypass it.
    property var  mutedApps: []

    function isMuted(appName) {
        const a = (appName || "").toLowerCase();
        if (a.length === 0) return false;
        for (let i = 0; i < root.mutedApps.length; i++)
            if (("" + root.mutedApps[i]).toLowerCase() === a) return true;
        return false;
    }

    // ── OSD (volume / mute / brightness) ─────────────────────────────────────
    // Brightness comes from the shared core.Backlight singleton (autodetected) —
    // no path config needed here.
    property bool   enableOsd: true

    function apply(jsonText) {
        try {
            const c = JSON.parse(jsonText);

            const l = c.layout;
            if (l) {
                if (l.cardWidth   !== undefined) root.cardWidth   = l.cardWidth;
                if (l.cardHeight  !== undefined) root.cardHeight  = l.cardHeight;
                if (l.gap         !== undefined) root.gap         = l.gap;
                if (l.maxVisible  !== undefined) root.maxVisible  = l.maxVisible;
                if (l.marginTop   !== undefined) root.marginTop   = l.marginTop;
                if (l.marginRight !== undefined) root.marginRight = l.marginRight;
                if (l.marginTopOffset    !== undefined) root.marginTopOffset    = l.marginTopOffset;
                if (l.osdMarginTopOffset !== undefined) root.osdMarginTopOffset = l.osdMarginTopOffset;
                if (l.padding     !== undefined) root.padding     = Geometry.px(l.padding,     root.padding);
                if (l.radius      !== undefined) root.radius      = Geometry.px(l.radius,      root.radius);
                if (l.imageRadius !== undefined) root.imageRadius = Geometry.px(l.imageRadius, root.imageRadius);
                if (l.border      !== undefined) root.borderCfg   = l.border;
                if (l.surfaceOpacity !== undefined) root.surfaceOpacityCfg = l.surfaceOpacity;  // raw; binding resolves live
            }

            const t = c.text;
            if (t) {
                if (t.titleMaxChars !== undefined) root.titleMaxChars = t.titleMaxChars;
                if (t.bodyMaxLines  !== undefined) root.bodyMaxLines  = t.bodyMaxLines;
                if (t.bodyMaxChars  !== undefined) root.bodyMaxChars  = t.bodyMaxChars;
            }

            const to = c.timeout;
            if (to) {
                if (to.low      !== undefined) root.timeoutLow      = to.low;
                if (to.normal   !== undefined) root.timeoutNormal   = to.normal;
                if (to.critical !== undefined) root.timeoutCritical = to.critical;
                if (to.osd      !== undefined) root.timeoutOsd      = to.osd;
            }

            const o = c.osd;
            if (o) {
                if (o.enable !== undefined) root.enableOsd = o.enable;
            }

            const d = c.dnd;
            if (d) {
                if (d.allowCritical  !== undefined) root.dndAllowCritical  = d.allowCritical;
                if (d.autoFullscreen !== undefined) root.dndAutoFullscreen = d.autoFullscreen;
            }

            root.mutedApps = Array.isArray(c.mute) ? c.mute : [];
        } catch (e) {
            // keep current/default config on parse error
        }
    }

    FileView {
        path: Qt.resolvedUrl("../../config/notifications.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    // ── DND state (~/.local/state/w/, written by w-notify) ───────────────────
    // Outside Quickshell's own stateDir so the CLI and the AI can read/write it —
    // resolved from the environment exactly like the bar's updates.json.
    readonly property string stateDir: {
        const x = Quickshell.env("XDG_STATE_HOME");
        return ((x && x.length > 0) ? x : (Quickshell.env("HOME") + "/.local/state")) + "/w";
    }
    readonly property string historyPath: root.stateDir + "/notification-history.json"

    property bool   dndStored:        false   // the stored flag, deadline not applied
    property double dndUntil:         0       // epoch seconds; 0 = no deadline
    property double historyClearedAt: 0       // watermark set by `w-notify history clear`
    property bool   stateLoaded:      false

    // Clock reference for the deadline. Only ever moved forward by the expiry timer,
    // so `dndActive` re-evaluates exactly once, when the deadline lapses.
    property double nowSec: Math.floor(Date.now() / 1000)

    readonly property bool dndActive: root.dndStored
        && (root.dndUntil <= 0 || root.nowSec < root.dndUntil)

    // Fires once, at the deadline — no polling loop for something that changes hourly.
    Timer {
        running: root.dndStored && root.dndUntil > 0 && root.nowSec < root.dndUntil
        interval: Math.max(1000, (root.dndUntil - root.nowSec) * 1000)
        repeat: false
        onTriggered: root.nowSec = Math.floor(Date.now() / 1000)
    }

    FileView {
        id: stateFile
        path: root.stateDir + "/notifications.json"
        watchChanges: true
        // Absent until the first `w-notify dnd` — a normal state, not a fault, and the
        // backstop below re-reads it on a timer; without this every poll logs a warning.
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.stateLoaded = true;
            try {
                const s = JSON.parse(stateFile.text() || "{}");
                root.dndStored        = !!s.dnd;
                root.dndUntil         = s.dndUntil         || 0;
                root.historyClearedAt = s.historyClearedAt || 0;
            } catch (e) {
                root.dndStored = false; root.dndUntil = 0;
            }
            root.nowSec = Math.floor(Date.now() / 1000);
        }
    }
    // Backstop: a watch on a path that does not exist yet can miss its creation (the
    // state file appears on the first `w-notify dnd`), and w-notify replaces the file
    // atomically on every write. Poll briskly until it first loads, then rarely.
    Timer {
        interval: root.stateLoaded ? 15000 : 2000
        running: true
        repeat: true
        onTriggered: stateFile.reload()
    }
}
