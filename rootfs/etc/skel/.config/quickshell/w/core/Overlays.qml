pragma Singleton

// W Linux — overlay popup coordinator.
// A single source of truth for which full-screen popup is open (launcher, clipboard,
// power menu, calendar, volume control). Only ONE may be open at a time: each popup
// binds `active` to `current === "<name>"`, and its entry points (global shortcut,
// click-outside, Esc, launch/copy) route through toggle/open/close here. Opening one
// popup implicitly closes any other in the same frame, so the outgoing card fades out
// while the incoming fades in — a coordinated crossfade "morph" from the popups' own
// opacity/scale animations, no cross-surface plumbing needed.
//
// current = "" means nothing is open. Names are the popup namespaces:
// "launcher" | "clipboard" | "assistant" | "infobox" | "layouts" | "powermenu" | "hub"
// | "calendar" | "volumecontrol" | "brightnesscontrol".
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string current: ""

    // ── Cursor lease ──────────────────────────────────────────────────────────
    // While a modal-center popup (blurGroup below) is shown, Hyprland swaps the
    // session-wide cursor idle timeout for the shorter "menu" one, so the pointer
    // gets out of the way of keyboard-first navigation; any mouse movement brings
    // it back (native inactive_timeout behaviour).
    //
    // The swap itself is compositor-side and event-driven: hyprland.lua listens
    // for layer.opened/layer.closed on the shared Backdrop's namespace
    // (quickshell:overlay-scrim — mapped exactly while a modal popup is shown), so
    // it is applied and released instantly, INCLUDING on this shell's death (the
    // compositor unmaps a dead client's surfaces → layer.closed → restore). No
    // close/release call from here is needed or sent.
    //
    // What this side does is close the ONE gap events can't: `hyprctl reload`
    // while a popup is open rebuilds the compositor's Lua state (which re-applies
    // the system value) and the already-mapped scrim fires no layer.opened. A ~2s
    // heartbeat re-applies the menu value for as long as a popup is shown — and
    // carries the fresh number, read live from the pointer fragment below (the
    // same source of truth `w-pointer` reads), so a `w-pointer set` lands on the
    // next beat with no restart.
    property real cursorMenuTimeout: 0.1
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/hypr/pointer.lua"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = /menu_timeout\s*=\s*([0-9]*\.?[0-9]+)/.exec(text());
            if (m) root.cursorMenuTimeout = parseFloat(m[1]);
        }
    }
    Process { id: cursorProc }
    Timer {
        interval: 2000
        running: root.blurGroup.indexOf(root.current) >= 0 && !root.suspended
        repeat: true
        onTriggered: {
            cursorProc.command = ["hyprctl", "eval",
                "hl.config({cursor={inactive_timeout=" + root.cursorMenuTimeout + "}})"];
            cursorProc.running = true;
        }
    }

    // ── Cursor-idle mirror (drives core/HoverGate) ────────────────────────────
    // `inactive_timeout` only stops DRAWING the cursor: the pointer keeps its focus
    // and position and no wl_pointer.leave is sent, so every MouseArea under it stays
    // `containsMouse`. A menu opened from the keyboard therefore shows a SECOND,
    // stale highlight wherever the now-invisible pointer happens to rest. This
    // mirrors the compositor's own rule — no motion for menu_timeout ⇒ hidden — and
    // HoverGate uses it to take hover away for exactly as long as the cursor is
    // invisible. One mirror here rather than a `&& !idle` clause on ~50 hover
    // bindings; see HoverGate for why a mask is the cheaper lever.
    //
    // Armed on OPEN, not after a countdown: the pointer may have been still for
    // minutes already, and the lease swaps menu_timeout in that same frame, so the
    // cursor is hidden from the popup's first frame. Any real pointer motion wakes
    // it and restarts the countdown, exactly as it un-hides the cursor itself.
    property bool cursorIdle: false
    readonly property bool cursorHideEnabled: root.cursorMenuTimeout > 0
    function cursorWake() {
        root.cursorIdle = false;
        if (root.cursorHideEnabled && root.scrimActive) cursorIdleTimer.restart();
    }
    onScrimActiveChanged: root.cursorIdle = root.scrimActive && root.cursorHideEnabled
    Timer {
        id: cursorIdleTimer
        interval: Math.max(1, Math.round(root.cursorMenuTimeout * 1000))
        onTriggered: root.cursorIdle = true
    }

    // Generic content for the "infobox" popup (title/body-markdown/actions) — see
    // modules/infobox/Infobox.qml. Set by openInfobox() right before opening, so any
    // caller (assistant readiness gate today, future help/skill viewer later) can
    // drive the same reusable card with its own content.
    property var infoboxContent: null
    function openInfobox(content) { root.infoboxContent = content; root.open("infobox"); }

    // Deep-link route for the NEXT hub open, e.g. "appearance/theme". Set by
    // open(name, { route }); the Hub reads it on show to jump straight to a panel,
    // then it is consumed. Cleared on plain toggle/open so those land at the root.
    property var pendingRoute: null

    // Temporary self-eclipse for the CURRENT popup: it stays logically open (current
    // is unchanged, so its state/navigation persist) but hides its surface + scrim +
    // keyboard grab. The Hub uses this to step aside for a polkit auth prompt it just
    // triggered (via pkexec) so the prompt gets focus on a clean screen, then restores
    // itself when the pkexec process exits. Purely a visibility gate — not a state
    // change — so no popup is "closed" by suspending.
    property bool suspended: false

    // Shared card width for the modal-center popups. Single source of truth so the
    // launcher, clipboard viewer, Hub and power menu all read as one centered surface
    // (their search fields / cards line up). Individual popups may still be wider only
    // if they opt out explicitly.
    readonly property int cardWidth: 720

    // The vertical twin of cardWidth: every modal-center card puts its TOP edge where
    // a `cardPin`-tall card centred on the screen would start —
    // `y = round((H - Overlays.cardPin) / 2)` — so they all share one top edge and
    // morph downward instead of re-centring as their height changes. 480 is the
    // launcher's card height, the original reference the others were aligned to.
    readonly property int cardPin: 480

    // Popups sharing the tinted + blurred full-screen backdrop (the "modal center"
    // group). A single Backdrop surface owns the scrim/blur for all of them, so
    // switching WITHIN this group keeps the backdrop solid — no blur flicker. Calendar
    // and volume are transparent top-anchored glances and are deliberately excluded.
    readonly property var blurGroup: ["launcher", "clipboard", "assistant", "infobox", "layouts", "powermenu", "hub"]
    // Suspended → also drop the scrim, so a popup stepping aside for a polkit prompt
    // leaves a fully clean screen (the prompt would otherwise sit under the scrim).
    readonly property bool scrimActive: root.blurGroup.indexOf(root.current) >= 0 && !root.suspended

    function toggle(name) { root.suspended = false; root.pendingRoute = null; root.current = (root.current === name) ? "" : name; }
    // open("hub", { route: "appearance/theme" }) deep-links; opts is optional.
    function open(name, opts) { root.suspended = false; root.pendingRoute = (opts && opts.route !== undefined) ? opts.route : null; root.current = name; }
    function close(name)  { if (root.current === name) { root.suspended = false; root.current = ""; } }
}
