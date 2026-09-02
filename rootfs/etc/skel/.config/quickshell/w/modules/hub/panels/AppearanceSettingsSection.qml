// W Linux — Hub Appearance: the "Settings" tab.
//
// Three per-user overrides that beat the active theme without editing it — a pure
// front-end over `w-appearance` (see w-style.md / config-effects.md / w-style
// modules 100-effects/100-motion for what each override actually does downstream).
// Every key here is user-scope and unprivileged: no polkit anywhere in this file.
//
// Kept in its own file (not inline in AppearancePanel.qml) for the same reason
// NightLightSection.qml is split out of DisplaysPanel — it shares no state with
// the theme grid, only the panel's dropdown overlay (`menuLayer`, handed in by
// the loader).
import QtQuick
import Quickshell.Io
import qs.core
import qs.modules.hub

Column {
    id: root

    // AppearancePanel's HubDropdown — one overlay per panel, shared so an open
    // menu here closes the same way it does everywhere else in the Hub.
    property var menuLayer: null

    // ── Keyboard roving-focus (Loader-child; AppearancePanel is the SOLE owner of
    // the index — quickshell-hub.md's Ф-Keyboard gotcha #8) ────────────────────
    // The panel drives `focusedField` in through a Binding (its `item` is
    // recreated on every Settings-tab re-activation); this file only reads it
    // back and exposes activateField() for the panel's confirm-dispatcher. No
    // Flickable/scrollIntoView here — three rows are always well under the
    // maxCardH−chrome floor (see Security/DateTime precedent).
    property string focusedField: ""
    function activateField(field) {
        if (field === "bar") barRow.activated();
        else if (field === "blur") blurRow.activated();
        else if (field === "motion") motionRow.activated();
    }

    spacing: 12

    // ── State (one porcelain read) ──────────────────────────────────────────────
    property string barPosition: "theme"
    property string blur: "theme"
    property string motion: "theme"

    function reload() { statusProc.running = false; statusProc.running = true; }
    Component.onCompleted: reload()

    Process {
        id: statusProc
        command: ["w-appearance", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const line of (this.text || "").split("\n")) {
                    const m = line.match(/^([A-Z_]+)=(.*)$/);
                    if (m) kv[m[1]] = m[2];
                }
                root.barPosition = kv.BAR_POSITION || "theme";
                root.blur = kv.BLUR || "theme";
                root.motion = kv.MOTION || "theme";
            }
        }
    }

    Process { id: setProc; onExited: root.reload() }
    function run(cmd) { setProc.running = false; setProc.command = cmd; setProc.running = true; }

    readonly property var barOptions: [
        { id: "theme",  label: Strings.t("appear.fromTheme") },
        { id: "top",    label: Strings.t("appear.barPosition.top") },
        { id: "bottom", label: Strings.t("appear.barPosition.bottom") },
    ]
    readonly property var offOptions: [
        { id: "theme", label: Strings.t("appear.fromTheme") },
        { id: "off",   label: Strings.t("appear.off") },
    ]
    function barLabel(id) { for (const o of root.barOptions) if (o.id === id) return o.label; return id; }
    function offLabel(id) { for (const o of root.offOptions) if (o.id === id) return o.label; return id; }

    Text {
        width: parent.width
        text: Strings.t("appear.hint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    SelectRow {
        id: barRow
        width: parent.width
        glyph: String.fromCodePoint(0xf0a4a)   // nf-md-dock-top
        label: Strings.t("appear.barPosition")
        currentId: root.barPosition
        value: root.barLabel(root.barPosition)
        options: root.barOptions
        focused: root.focusedField === "bar"
        onActivated: if (root.menuLayer)
            root.menuLayer.openMenu(barRow, options, root.barPosition,
                                    (id) => root.run(["w-appearance", "bar-position", id]))
    }

    SelectRow {
        id: blurRow
        width: parent.width
        glyph: String.fromCodePoint(0xf00e5)   // nf-md-blur
        label: Strings.t("appear.blur")
        currentId: root.blur
        value: root.offLabel(root.blur)
        options: root.offOptions
        focused: root.focusedField === "blur"
        onActivated: if (root.menuLayer)
            root.menuLayer.openMenu(blurRow, options, root.blur,
                                    (id) => root.run(["w-appearance", "blur", id]))
    }

    SelectRow {
        id: motionRow
        width: parent.width
        glyph: String.fromCodePoint(0xf05d4)   // nf-md-motion-outline
        label: Strings.t("appear.animations")
        currentId: root.motion
        value: root.offLabel(root.motion)
        options: root.offOptions
        focused: root.focusedField === "motion"
        onActivated: if (root.menuLayer)
            root.menuLayer.openMenu(motionRow, options, root.motion,
                                    (id) => root.run(["w-appearance", "motion", id]))
    }
}
