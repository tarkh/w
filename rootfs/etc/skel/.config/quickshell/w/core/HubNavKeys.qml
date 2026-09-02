pragma Singleton

// W Linux — menu-navigation key resolver for every Quickshell surface.
// Up/Down/Left/Right/Return/Escape/Delete were hardcoded Qt.Key_* literals in every
// roving-focus surface (RootGrid, HubMenu/HubDropdown, and the Network/Power/Appearance/
// System/Input panels) — the `i3-vim` hotkeys profile (the rest of Hyprland on hjkl, see
// [[w-hotkeys]]) got no HJKL navigation inside the Hub, only the built-in `default`
// profile's arrows. Fixed via a Quickshell-local "menu" token category in catalog.tokens
// (menu_up/down/left/right/confirm/back/delete — NOT bound in Hyprland; see
// hotkeys-catalog.lua's comment on why) that rebinds through the same `w-hotkeys` profile
// machinery as any other action. This singleton is the single place that resolves
// `w-hotkeys status --porcelain`'s chord strings into Qt.Key_* codes; every Keys.onPressed
// switches on `HubNavKeys.up/down/left/right/confirm/back/del` instead of a literal
// Qt.Key_Up/Down/Left/Right/Return/Escape/Delete.
//
// confirm/back keep Space+keypad-Enter / Backspace as permanent hardcoded aliases at their
// call sites (universal software idioms, unrelated to the arrows→hjkl ergonomics story —
// see quickshell-hub.md); `del` does NOT get one, on purpose, matching the arrows'
// single-key-per-profile contract.
//
// ── THE CONTRACT: three modes, one token set ───────────────────────────────────────
// Every keyboard-driven W surface is in exactly one of these. The mode follows from who
// owns the Qt keyboard focus, not from taste, and picking the wrong one is what makes a
// panel feel inconsistent:
//
//   A — roving surface (no live text field): the card holds focus and reads the chords
//       BARE — `switch (e.key) { case HubNavKeys.down: … }` — plus the fixed aliases
//       (Space/keypad-Enter for confirm, Backspace for back). Hub + its panels,
//       VolumeControl, BrightnessControl, Calendar, Infobox, WFilePicker.
//   B — palette surface: a TextField owns the keyboard for as long as the surface is
//       open, and a list lives next to it. Bare chords are impossible here (a profile may
//       put menu_back on a letter, and taking that letter would close the panel instead
//       of typing it), so the whole set moves behind Ctrl — resolve with fieldAction()
//       below, never by hand. Launcher, Clipboard, Assistant, Layouts, the Hub's three
//       searchable pickers, AuthPrompt's password field.
//   C — inline field inside a roving surface (Hub panels' settings fields): navigation is
//       suspended entirely while `input.activeFocus`, Enter/Escape leave the field. No
//       resolver needed — the panels' own `activeFocus` guards are the whole mechanism.
//
// Two surfaces are deliberately outside all three and must stay that way: PowerMenu
// (self-contained letter mnemonics — `Qt.Key_L` for Lock would be a duplicate case value
// against menu_right on i3-vim) and the greeter (a separate Quickshell config that cannot
// read a user profile at all). TrayMenu is mouse-entry-only by design. See
// quickshell-hub.md.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int up: Qt.Key_Up
    property int down: Qt.Key_Down
    property int left: Qt.Key_Left
    property int right: Qt.Key_Right
    property int confirm: Qt.Key_Return
    property int back: Qt.Key_Escape
    property int del: Qt.Key_Delete

    // Chord string ("up" / "Return" / "H" / …) → Qt.Key_* code. Menu-nav chords are always
    // bare (no modifier — the Hub reads them directly, not through a Hyprland bind), so this
    // only needs the named keysyms above plus any single letter/digit — the same range
    // HotkeysPanel's own keysym() capture can produce for a hand-typed rebind.
    function keyFor(chord) {
        const c = String(chord || "").trim();
        if (c.length === 0) return -1;
        const named = {
            up: Qt.Key_Up, down: Qt.Key_Down, left: Qt.Key_Left, right: Qt.Key_Right,
            return: Qt.Key_Return, escape: Qt.Key_Escape, delete: Qt.Key_Delete, backspace: Qt.Key_Backspace
        };
        const named_hit = named[c.toLowerCase()];
        if (named_hit !== undefined) return named_hit;
        if (c.length === 1) {
            const ch = c.toUpperCase();
            if (ch >= "A" && ch <= "Z") return Qt.Key_A + (ch.charCodeAt(0) - "A".charCodeAt(0));
            if (ch >= "0" && ch <= "9") return Qt.Key_0 + (ch.charCodeAt(0) - "0".charCodeAt(0));
        }
        return -1;
    }

    // ── Mode B resolver ─────────────────────────────────────────────────────────────
    // Menu action for a key event on a surface whose TextField owns the keyboard, or ""
    // when the event is not one. The caller switches on the returned name and sets
    // `event.accepted` itself:
    //
    //     input.Keys.onPressed: (e) => {
    //         switch (HubNavKeys.fieldAction(e)) {
    //         case "down": list.incrementCurrentIndex(); e.accepted = true; return;
    //         …
    //         }
    //     }
    //
    // What it accepts, in this order — the order IS the contract, because a profile chord
    // may coincide with a fixed alias (on `default`, menu_back is Escape) and matching the
    // alias first makes that resolve once instead of depending on switch-case order:
    //   1. bare ↑ ↓ Enter Esc     — every profile, always; these keys cannot be typed
    //   2. Shift+Del / Shift+Backspace — delete, fixed alias (bare Backspace still edits)
    //   3. Ctrl + <profile chord> — the whole set, delete included
    //
    // Bare ← → are deliberately NOT resolved: in a one-line field they belong to the text
    // cursor. A surface that can spare them (Layouts) wires its own Keys.onLeftPressed/
    // onRightPressed and hands the cursor back whatever it declines.
    //
    // Ctrl is fixed, not configurable: Ctrl+<letter> is the only prefix that provably
    // never reaches the field as text (Alt composes, Super is the WM's). Its cost is that
    // a menu chord on X/A/C/V shadows the field's own cut/select-all/copy/paste — accepted
    // deliberately (i3-vim ships menu_delete on X, and Layouts has shipped exactly this
    // since its keyboard pass): palette text is a throwaway query, and Shift+Del still
    // deletes without touching the clipboard.
    //
    // Callers with their own Ctrl+Shift combo (Clipboard's wipe-all) must test it BEFORE
    // calling this — with menu_delete on Delete, Ctrl+Shift+Del also satisfies rule 3.
    function fieldAction(e) {
        const mods = e.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods === Qt.NoModifier) {
            switch (e.key) {
            case Qt.Key_Up:     return "up";
            case Qt.Key_Down:   return "down";
            case Qt.Key_Return:
            case Qt.Key_Enter:  return "confirm";
            case Qt.Key_Escape: return "back";
            }
            return "";
        }
        if (mods === Qt.ShiftModifier)
            return (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) ? "delete" : "";
        if (!(mods & Qt.ControlModifier)) return "";
        switch (e.key) {
        case root.up:      return "up";
        case root.down:    return "down";
        case root.left:    return "left";
        case root.right:   return "right";
        case root.confirm: return "confirm";
        case root.back:    return "back";
        case root.del:     return "delete";
        }
        return "";
    }

    // Re-probe the active profile's effective chords. Called on every real Hub open
    // (Hub.qml) and right after a hotkeys mutation that could touch these tokens
    // (HotkeysPanel.qml) — cheap enough (one short-lived process) to just always run
    // rather than filter by which token actually changed.
    function refresh() { statusProc.running = true; }

    readonly property var _tokenProp: ({
        menu_up: "up", menu_down: "down", menu_left: "left", menu_right: "right",
        menu_confirm: "confirm", menu_back: "back", menu_delete: "del"
    })

    Process {
        id: statusProc
        command: ["w-hotkeys", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const chords = {};
                for (const ln of (this.text || "").split("\n")) {
                    const f = ln.split("\t");
                    if (f.length >= 2 && f[0].indexOf("menu_") === 0) chords[f[0]] = f[1];
                }
                // Unresolvable/missing chords keep the previous (default-seeded) value —
                // a headless probe or a `w-hotkeys` without the "menu" tokens yet degrades
                // to plain arrow/Return/Escape/Delete navigation instead of breaking it.
                for (const tok in root._tokenProp) {
                    if (chords[tok] === undefined) continue;
                    const k = root.keyFor(chords[tok]);
                    if (k !== -1) root[root._tokenProp[tok]] = k;
                }
            }
        }
    }

    // Every mutation — a Hub rebind, `w-hotkeys use` from a terminal or an AI actuation —
    // rewrites the active fragment, so watching it keeps EVERY surface current, including
    // the ones that never call refresh() themselves (Launcher/Clipboard/Assistant/
    // Calendar/Infobox/WFilePicker: they have no "opened" hook worth wiring one into).
    // The content is never parsed here — the file is purely a change signal for the
    // `w-hotkeys` probe above, which resolves profile + overrides properly. The
    // reload()-in-onFileChanged/act-in-onLoaded shape is not ceremony: the watch is armed
    // by the load, so a FileView that never reads its file never fires either (measured
    // with a headless probe — the chords stayed on the old profile).
    FileView {
        path: (Quickshell.env("HOME") || "") + "/.config/hypr/hotkeys.lua"
        watchChanges: true
        printErrors: false   // absent on an account that predates the hotkeys seed
        onFileChanged: reload()
        onLoaded: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
