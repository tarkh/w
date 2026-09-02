pragma Singleton

// W Linux — XKB layout name registry.
// One shared home for turning XKB layout/variant codes into human names and back,
// so the bar's keyboard block and the Hub's Input panel display layouts identically.
// It parses the canonical registry (/usr/share/X11/xkb/rules/evdev.lst) once — both
// its "! layout" section (code ↔ base name) and its "! variant" section (a variant's
// full name + the layout it belongs to) — and exposes:
//   • label(code, variant) → the full human name of a ring slot, e.g. "ru"+"mac" →
//     "Russian (Macintosh)" (falls back to the base layout name, then the code).
//   • codeOf(fullName)      → the layout code for a full XKB name as Hyprland reports
//     it in `active_keymap` / the `activelayout` event, e.g. "Russian (Macintosh)" →
//     "ru". Variant names resolve too (the reason the bar used to show "MACINTOSH").
// Consumers `import qs.core` and use `Xkb` like Colors/Fonts.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var codeToName: ({})     // "us" → "English (US)"
    property var nameToCode: ({})     // "English (US)"|"Russian (Macintosh)" → "us"|"ru"
    property var variantName: ({})    // "ru\tmac" → "Russian (Macintosh)"

    // Full human name for a (layout, variant) ring slot. Empty variant → base layout
    // name; unknown → the code itself, so something sensible always shows.
    function label(code, variant) {
        if (variant && variant.length > 0) {
            const v = root.variantName[code + "\t" + variant];
            if (v !== undefined) return v;
        }
        return root.codeToName[code] !== undefined ? root.codeToName[code] : code;
    }

    // Layout code for a full XKB name (Hyprland's active_keymap). Falls back to the
    // parenthesised text / first token when a name isn't in the registry.
    function codeOf(fullName) {
        if (!fullName) return "";
        const c = root.nameToCode[fullName];
        if (c !== undefined) return c;
        const m = fullName.match(/\(([^)]+)\)/);
        return (m ? m[1] : fullName).split(/[ ,]/)[0].toLowerCase();
    }

    FileView {
        path: "/usr/share/X11/xkb/rules/evdev.lst"
        onLoaded: {
            const c2n = {}, n2c = {}, vn = {};
            let section = "";
            for (const ln of (text() || "").split("\n")) {
                if (ln.charAt(0) === "!") {
                    section = ln.indexOf("! layout") === 0 ? "layout"
                            : ln.indexOf("! variant") === 0 ? "variant" : "";
                    continue;
                }
                if (section === "layout") {
                    const m = ln.trim().match(/^(\S+)\s+(.+)$/);
                    if (m) {
                        const code = m[1], name = m[2].trim();
                        if (c2n[code] === undefined) c2n[code] = name;
                        n2c[name] = code;
                    }
                } else if (section === "variant") {
                    // "<variant> <layout>: <full name>"
                    const m = ln.trim().match(/^(\S+)\s+(\S+):\s*(.+)$/);
                    if (m) {
                        const varn = m[1], lay = m[2], name = m[3].trim();
                        vn[lay + "\t" + varn] = name;
                        n2c[name] = lay;   // full variant name resolves to its layout code
                    }
                }
            }
            root.codeToName = c2n; root.nameToCode = n2c; root.variantName = vn;
        }
    }
}
