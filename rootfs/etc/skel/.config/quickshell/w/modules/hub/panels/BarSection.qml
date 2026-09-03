// W Linux — Hub Appearance: the "Bar" tab.
//
// What the status bar shows, per monitor: one section per live output with a master
// "Bar" row (is there a bar on this output at all) and a row per addressable block.
// Above them sits the one bar setting that is NOT per monitor — its position — which
// used to live in the Settings tab; keeping it here means every bar control has one
// door (geometry itself stays theme-owned, see config-geometry.md).
//
// Reads and writes are deliberately asymmetric, and that is the whole design:
//   read  — straight off the BarConfig singleton, which already watches bar.json. No
//           process, no polling, and a write lands back here through the same
//           FileView the bar itself uses, so the rows and the bar can never disagree.
//   write — `w-bar` only (and `w-appearance bar-position` for the position row). One
//           writer per file, the same rule NotificationsPanel follows with w-notify.
//
// Kept in its own file (not inline in AppearancePanel.qml) for the same reason
// AppearanceSettingsSection/NightLightSection are: it shares no state with the theme
// grid, only the panel's dropdown overlay (`menuLayer`, handed in by the loader).
//
// Roving focus: AppearancePanel is the SOLE owner of the index across the Loader
// barrier (quickshell-hub.md Ф-Keyboard gotcha #8). Unlike the Settings tab the field
// list here is DYNAMIC (outputs × blocks), so the panel reads `fields` back from this
// file and drives `focusedField` in; `rowItem()` is what its scroll-into-view targets.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.bar
import qs.modules.hub

Column {
    id: root

    // AppearancePanel's HubDropdown — one overlay per panel.
    property var menuLayer: null
    property string focusedField: ""

    spacing: 12

    // ── State ───────────────────────────────────────────────────────────────────
    // Everything per-monitor comes live from BarConfig; only the position override
    // needs a read (it is w-appearance's, in the layered-config sense, not the bar's).
    readonly property var screens: Quickshell.screens
    property string barPosition: "theme"

    function reload() { statusProc.running = false; statusProc.running = true; }
    Component.onCompleted: reload()

    Process {
        id: statusProc
        command: ["w-appearance", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = (this.text || "").match(/^BAR_POSITION=(.*)$/m);
                root.barPosition = m ? m[1] : "theme";
            }
        }
    }

    Process { id: setProc; onExited: root.reload() }
    function run(cmd) { setProc.running = false; setProc.command = cmd; setProc.running = true; }

    // ── Options ─────────────────────────────────────────────────────────────────
    readonly property var posOptions: [
        { id: "theme",  label: Strings.t("appear.fromTheme") },
        { id: "top",    label: Strings.t("appear.barPosition.top") },
        { id: "bottom", label: Strings.t("appear.barPosition.bottom") },
    ]
    readonly property var onOffOptions: [
        { id: "on",  label: Strings.t("bar.on") },
        { id: "off", label: Strings.t("bar.off") },
    ]
    function posLabel(id) { for (const o of root.posOptions) if (o.id === id) return o.label; return id; }
    function onOffLabel(on) { return Strings.t(on ? "bar.on" : "bar.off"); }

    // ── Roving-focus descriptors ────────────────────────────────────────────────
    // Flat, in render order: the position row, then per output its master row and one
    // row per catalog entry. Carrying the indices (rather than parsing the key back
    // apart) is what lets rowItem() reach into the two Repeaters without string work —
    // the same "positional descriptor" idiom DisplaysPanel uses for its output rows.
    readonly property var fieldDesc: {
        const out = [{ key: "position", kind: "pos" }];
        const cat = BarConfig.catalog;
        for (let i = 0; i < root.screens.length; i++) {
            const n = root.screens[i].name;
            out.push({ key: n + ":bar", kind: "bar", oi: i });
            for (let j = 0; j < cat.length; j++)
                out.push({ key: n + ":" + cat[j].id, kind: "block", oi: i, bi: j });
        }
        return out;
    }
    readonly property var fields: root.fieldDesc.map((d) => d.key)

    function rowItem(field) {
        const i = root.fields.indexOf(field);
        if (i < 0) return null;
        const d = root.fieldDesc[i];
        if (d.kind === "pos") return posRow;
        const sec = outRep.itemAt(d.oi);
        if (!sec) return null;
        return d.kind === "bar" ? sec.barRow : sec.blockRep.itemAt(d.bi);
    }
    function activateField(field) {
        const it = root.rowItem(field);
        if (it) it.activated();
    }

    // ── Hint + the one global (non per-monitor) bar setting ─────────────────────
    Text {
        width: parent.width
        text: Strings.t("bar.hint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    SelectRow {
        id: posRow
        width: parent.width
        glyph: String.fromCodePoint(0xf0a4a)   // nf-md-dock-top
        label: Strings.t("appear.barPosition")
        currentId: root.barPosition
        value: root.posLabel(root.barPosition)
        options: root.posOptions
        focused: root.focusedField === "position"
        onActivated: if (root.menuLayer)
            root.menuLayer.openMenu(posRow, options, root.barPosition,
                                    (id) => root.run(["w-appearance", "bar-position", id]))
    }

    Text {
        width: parent.width
        visible: root.screens.length === 0
        text: Strings.t("bar.noOutputs")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // ── One section per live output ─────────────────────────────────────────────
    Repeater {
        id: outRep
        model: root.screens

        Column {
            id: sec
            required property var modelData
            required property int index

            // Reached from rowItem() by index — the two handles AppearancePanel's
            // scroll-into-view and Enter dispatcher need.
            property alias barRow: masterRow
            property alias blockRep: blocks

            readonly property string outName: sec.modelData.name
            readonly property bool barEnabled: BarConfig.barOn(sec.outName)

            width: root.width
            spacing: 8

            HubSection {
                width: parent.width
                text: sec.outName + (Displays.isPrimary(sec.outName)
                                     ? " · " + Strings.t("bar.primary") : "")
            }

            SelectRow {
                id: masterRow
                width: parent.width
                glyph: String.fromCodePoint(0xf0a4a)   // nf-md-dock-top
                label: Strings.t("bar.enabled")
                currentId: sec.barEnabled ? "on" : "off"
                value: root.onOffLabel(sec.barEnabled)
                options: root.onOffOptions
                focused: root.focusedField === sec.outName + ":bar"
                onActivated: if (root.menuLayer)
                    root.menuLayer.openMenu(masterRow, options, currentId,
                                            (id) => root.run(["w-bar", "monitor", sec.outName, id]))
            }

            Repeater {
                id: blocks
                model: BarConfig.catalog

                SelectRow {
                    id: blockRow
                    required property var modelData
                    readonly property bool nested: blockRow.modelData.parentId !== ""
                    readonly property bool shown: BarConfig.shownOn(sec.outName, blockRow.modelData.block)
                    // A row is dead when what would contain it is switched off: no bar
                    // on this output, or the block sits inside a hidden zone. Dimmed
                    // rather than dropped — the value is still stored and comes back
                    // with its container, and a row that vanishes reads as data loss.
                    readonly property var parentEntry: blockRow.nested
                        ? BarConfig.catalogEntry(blockRow.modelData.parentId) : null
                    readonly property bool live: sec.barEnabled
                        && (!blockRow.parentEntry || BarConfig.shownOn(sec.outName, blockRow.parentEntry.block))

                    // Column only owns y, so x is free for the nesting indent.
                    x: blockRow.nested ? 18 : 0
                    width: sec.width - blockRow.x
                    glyph: String.fromCodePoint(0xf11d9)   // nf-md-view_grid_outline
                    label: BarConfig.blockTitle(blockRow.modelData.block)
                    enabled: blockRow.live
                    currentId: blockRow.shown ? "on" : "off"
                    value: root.onOffLabel(blockRow.shown)
                    options: root.onOffOptions
                    focused: root.focusedField === sec.outName + ":" + blockRow.modelData.id
                    onActivated: if (root.menuLayer)
                        root.menuLayer.openMenu(blockRow, options, currentId,
                                                (id) => root.run(["w-bar", "block", sec.outName,
                                                                  blockRow.modelData.id, id]))
                }
            }
        }
    }
}
