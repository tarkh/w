// W Linux — the curtain `w-session restore` raises while it deals the windows back
// out (see w-session.md).
//
// WHY A CURTAIN AT ALL. Phase 2 places each window by focusing an anchor first, and
// focusing a window that lives on another workspace switches to that workspace —
// there is no way around it, so the desktop visibly flicks through the workspaces
// for the second or two the restore takes. Animations are already off for the
// duration; what is left is the flicker itself, and only something opaque covers it.
//
// This side is only the card: the ordinary infobox over the ordinary backdrop, with
// the same tint, blur and fade as the launcher or the Hub. What makes that possible
// while the desktop is churning is w-session's half — a grim freeze frame held up by
// `w-windowblind`, mapped BEFORE this card (layer surfaces on one level stack in map
// order, measured) so the backdrop's blur has a still image behind it instead of the
// live desktop. An opaque backdrop was tried first and rejected: it is a flat wash of
// colour where every other W surface shows blurred wallpaper, and it would have been
// the only surface in the shell that ignores the user's own tint/blur settings.
//
// THE HANDSHAKE. w-session must not start moving windows until the card has finished
// fading in, and that duration is Motion.fast — a number this side owns and the script
// has no business guessing (the same reasoning as w-windowblind's readiness fifo, see
// w-theme, which covers the freeze's own fade). So the shell waits out its own fade
// and then touches a file the script is polling for. Everything else is fire-and-forget over two global
// shortcuts, which is also what makes the restore work when the shell is NOT up yet:
// w-session waits for the shortcut to appear in `hyprctl globalshortcuts` for a beat
// and otherwise restores bare, exactly as it did before this existed.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.core

Scope {
    id: root

    // Next to session.json / session.restoring, and cleared by w-session before every
    // raise, so a leftover from a killed restore can never be read as "ready".
    readonly property string readyFile:
        (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
        + "/w/session.curtain-ready"

    // A curtain nobody lowers is an unusable desktop, so it lowers itself. The cap is
    // the restore unit's own ceiling with room to spare — this is a safety net for a
    // w-session that died mid-phase, not a schedule.
    readonly property int safetyMs: 120000

    // `passive` is load-bearing, not cosmetic: a card that takes keyboard focus
    // freezes which window is active, and phase 2 places every window by focusing
    // an anchor first. With focus frozen, `splitratio` has no window to act on and
    // every restore came back with default 50/50 splits — see Infobox.qml. There
    // is nothing to type at here anyway; w-session lowers the card itself, and the
    // freeze behind it stays up regardless.
    function show() {
        Overlays.openInfobox({ glyph: Glyphs.sessionRestore, title: Strings.t("sess.curtain"),
                               passive: true });
        settle.restart();
        safety.restart();
    }

    function hide() {
        settle.stop();
        safety.stop();
        Overlays.close("infobox");
    }

    // bind = SUPER, …, global, quickshell:session-curtain-on — no keybind exists or is
    // wanted; `hyprctl dispatch hl.dsp.global(...)` from w-session is the caller.
    GlobalShortcut {
        appid: "quickshell"
        name: "session-curtain-on"
        onPressed: root.show()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "session-curtain-off"
        onPressed: root.hide()
    }

    // The fade this waits out is the backdrop's and the card's — both Motion.fast. The
    // margin covers the Wayland round trip between "committed" and "the compositor
    // started drawing it", the same 50 ms w-theme allows.
    Timer {
        id: settle
        interval: Motion.fast + 50
        onTriggered: ready.running = true
    }

    Process { id: ready; command: ["touch", root.readyFile] }

    Timer {
        id: safety
        interval: root.safetyMs
        onTriggered: root.hide()
    }
}
