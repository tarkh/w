// W Linux — Hub Displays: the "Night light" scope.
//
// The third segment of DisplaysPanel's scope switch, kept in its own file because
// the panel is already long and this scope shares none of its data: no outputs, no
// staged edits, no polkit. It is a plain front-end over `w-nightlight`, whose keys
// are all user-scope — every mutation is an ordinary Process, and the only reason
// a control is ever disabled here is a fleet policy lock (w-conf policy.d), never
// a missing privilege.
//
// State is one porcelain read (`w-nightlight status --porcelain`); the layered-config
// declaration comes from `w-conf list nightlight --porcelain`, exactly as PowerPanel
// does it, so a key re-scoped or locked in the config changes this panel with no QML edit.
//
// Every control here applies LIVE and smoothly on its own: `w-nightlight` pushes the
// new value to the running daemon over IPC rather than restarting it, and Hyprland
// fades the colour-transform change (render:ctm_animation). So this file has no
// preview/undo dance — committing a field is both the save and the visible result.
//
// Loaded by DisplaysPanel through a Loader (sibling file, not a module type), which
// hands in the panel's shared dropdown overlay via `menuLayer`.
import QtQuick
import Quickshell.Io
import qs.core
import qs.modules.hub

Column {
    id: root

    // DisplaysPanel's HubDropdown — one overlay per panel, shared so an open menu
    // here closes the same way it does over the output rows.
    property var menuLayer: null

    // ── Keyboard roving-focus (owned by DisplaysPanel, not this file) ────────────────
    // DisplaysPanel is the sole owner of the roving index (see its framework comment);
    // this file only renders whichever field name it's told, and exposes a small
    // remote-control surface (rowItem/activateField/focusFieldInput) for the parent
    // to drive without needing its own copy of the roving state. "mode"/"temp"/"day"/
    // "ramp"/"start"/"end" — the same field names DisplaysPanel.buildContent() uses.
    property string focusedField: ""
    // Tab/Esc out of one of the fields below hands real Qt focus back to
    // DisplaysPanel — same "child signals, panel calls forceActiveFocus()" contract
    // as PowerPanel's IdleRow.exitField().
    signal requestFocusReturn()

    // True while any of this section's own text fields holds real Qt focus — lets
    // DisplaysPanel guard Up/Down from stealing the roving index mid-edit (same
    // reasoning as PowerPanel.editingText), forwarded across the Loader boundary.
    readonly property bool editingText: {
        if (tempField.input.activeFocus || dayField.input.activeFocus || rampField.input.activeFocus) return true;
        for (let i = 0; i < timeRepeater.count; i++) {
            const it = timeRepeater.itemAt(i);
            if (it && it.timeInput.activeFocus) return true;
        }
        return false;
    }
    // The Item DisplaysPanel scrolls into view for a given field name.
    function rowItem(field) {
        if (field === "mode") return modeRow;
        if (field === "temp") return tempWrap;
        if (field === "day") return dayWrap;
        if (field === "ramp") return rampWrap;
        if (field === "start") return timeRepeater.itemAt(0);
        if (field === "end") return timeRepeater.itemAt(1);
        return null;
    }
    // Enter on the mode row — mirrors the row's own click (opens the dropdown).
    function activateField(field) { if (field === "mode") modeRow.activated(); }
    // Enter on a text-field row — mirrors PowerPanel's IdleRow entering edit mode.
    function focusFieldInput(field) {
        if (field === "temp") tempField.input.forceActiveFocus();
        else if (field === "day") dayField.input.forceActiveFocus();
        else if (field === "ramp") rampField.input.forceActiveFocus();
        else if (field === "start") { const it = timeRepeater.itemAt(0); if (it) it.timeInput.forceActiveFocus(); }
        else if (field === "end")   { const it = timeRepeater.itemAt(1); if (it) it.timeInput.forceActiveFocus(); }
    }

    spacing: 12

    // ── State (one porcelain read) ────────────────────────────────────────────────
    property string mode: "off"
    property string temp: "4300"
    property string dayTemp: "6600"        // the other end of the ramp
    property string nightStart: "21:00"
    property string nightEnd: "07:00"
    property bool   active: false          // is the filter in effect right now
    property bool   running: false         // is there a daemon to preview against
    property int    ramp: 30               // transition length, minutes (0 = instant)
    property string current: "identity"    // what is on screen NOW (kelvin, or identity)
    property int    tempMin: 1000
    property int    tempMax: 20000
    // The kelvin value that leaves the screen untouched. Comes from the backend
    // rather than being hardcoded here: it is a property of hyprsunset's own
    // conversion, and the hint below is only honest if the two agree.
    property int    identityK: 6600

    Process {
        id: statusProc
        running: true
        command: ["w-nightlight", "status", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const line of (this.text || "").split("\n")) {
                    const m = line.match(/^([A-Z_]+)=(.*)$/);
                    if (m) kv[m[1]] = m[2];
                }
                root.mode = kv.MODE || "off";
                root.temp = kv.NIGHT_TEMP || "4300";
                root.dayTemp = kv.DAY_TEMP || "6600";
                root.identityK = parseInt(kv.IDENTITY_K || "6600");
                root.nightStart = kv.NIGHT_START || "21:00";
                root.nightEnd = kv.NIGHT_END || "07:00";
                root.active = kv.ACTIVE === "1";
                root.running = kv.RUNNING === "1";
                root.ramp = parseInt(kv.RAMP_MINUTES || "30");
                root.current = kv.CURRENT || "identity";
                root.tempMin = parseInt(kv.TEMP_MIN || "1000");
                root.tempMax = parseInt(kv.TEMP_MAX || "20000");
            }
        }
    }

    // The layered-config declaration: which keys a fleet policy has taken out of
    // local hands. Same source and same shape as PowerPanel's confProc.
    property var confLocked: ({})
    Process {
        id: confProc
        running: true
        command: ["w-conf", "list", "nightlight", "--porcelain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const locked = {};
                for (const line of (this.text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 5) continue;
                    if (f[3] === "locked") locked[f[0]] = true;
                }
                root.confLocked = locked;
            }
        }
    }
    function isLocked(key) { return root.confLocked[key] === true; }

    function reloadAll() {
        statusProc.running = false; statusProc.running = true;
        confProc.running = false;   confProc.running = true;
    }

    Process { id: setProc; onExited: root.reloadAll() }
    function run(cmd) { setProc.running = false; setProc.command = cmd; setProc.running = true; }

    // ── Labels ────────────────────────────────────────────────────────────────────
    function modeLabel(id) { return id ? Strings.t("nl.mode." + id) : "—"; }
    readonly property var modeOptions: [
        { id: "off",      label: Strings.t("nl.mode.off") },
        { id: "schedule", label: Strings.t("nl.mode.schedule") },
        { id: "always",   label: Strings.t("nl.mode.always") },
    ]

    // ── Rows ──────────────────────────────────────────────────────────────────────
    Text {
        width: parent.width
        text: Strings.t("nl.hint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    HubSection { width: parent.width; text: Strings.t("nl.section") }

    SelectRow {
        id: modeRow
        width: parent.width
        focused: root.focusedField === "mode"
        icon: "weather-clear-night"; glyph: String.fromCodePoint(0xf0594)   // nf-md-weather-night
        label: Strings.t("nl.modeLabel")
        currentId: root.mode
        value: root.modeLabel(root.mode)
        options: root.modeOptions
        locked: root.isLocked("MODE")
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: if (root.menuLayer)
            root.menuLayer.openMenu(modeRow, options, root.mode,
                                    (id) => root.run(["w-nightlight", "mode", id]))
    }

    // Current effect, stated plainly. "Scheduled" alone does not answer "so is my
    // screen warm right now or not", and at 3pm with a 21:00 window the answer is
    // the opposite of what the mode name suggests. Mid-transition it reports the
    // value actually on screen — claiming the destination would be visibly false.
    Text {
        width: parent.width
        text: {
            if (root.mode === "off") return Strings.t("nl.stateOff");
            if (!root.active) return Strings.t("nl.stateWaiting") + " " + root.nightStart;
            if (root.current !== "identity" && root.current !== root.temp)
                return Strings.t("nl.stateRamping") + " " + root.current + " K";
            return Strings.t("nl.stateOn");
        }
        color: root.active ? Colors.accentInk : Colors.muted
        font.family: Fonts.family; font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    // Temperature. Free-form (not a preset dropdown) for the same reason as
    // PowerPanel's idle timers: a value set from the CLI or the AI tool must show
    // exactly, not snap to the nearest listed option.
    Item {
        id: tempWrap
        width: parent.width
        implicitHeight: 38
        visible: root.mode !== "off"
        opacity: root.isLocked("NIGHT_TEMP") ? 0.45 : 1

        // Full-row focus wash, same bleed contract as SelectRow/HubRow — hidden
        // while the field itself holds real Qt focus (its own border already shows
        // that), same idiom as PowerPanel's IdleRow.
        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: root.focusedField === "temp" && !tempField.input.activeFocus
            color: Colors.hover
        }

        Column {
            anchors { left: parent.left; right: tempField.left; rightMargin: 10
                      verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                text: Strings.t("nl.tempLabel")
                color: Colors.text
                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: Strings.t("nl.tempHint")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
        WSettingsField {
            id: tempField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fixedWidth: 64
            numeric: true
            suffix: Strings.t("nl.kelvin")
            value: root.temp
            validator: (text) => !root.isLocked("NIGHT_TEMP") && /^[0-9]+$/.test(text)
                                 && parseInt(text) >= root.tempMin && parseInt(text) <= root.tempMax
            borderWidth: HubConfig.border
            // Applies live on its own: the setter pushes the new value to the
            // running daemon over IPC, which Hyprland fades. No preview call and
            // nothing to undo on the way out.
            onApplied: (text) => root.run(["w-nightlight", "temp", text])
            input.Keys.onTabPressed: root.requestFocusReturn()
            input.Keys.onEscapePressed: root.requestFocusReturn()
        }
    }

    // The other end of the ramp. Two things make this worth exposing: panels
    // differ in what "no tint" looks like, so a fixed anchor shows up as a step
    // at the start of a transition; and some people want a deliberately warmer or
    // cooler day. At identityK the screen is left completely alone.
    Item {
        id: dayWrap
        width: parent.width
        implicitHeight: 38
        // `always` never leaves the night temperature and `off` never applies
        // anything, so a day anchor is only a real setting under `schedule`.
        visible: root.mode === "schedule"
        opacity: root.isLocked("DAY_TEMP") ? 0.45 : 1

        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: root.focusedField === "day" && !dayField.input.activeFocus
            color: Colors.hover
        }

        Column {
            anchors { left: parent.left; right: dayField.left; rightMargin: 10
                      verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                text: Strings.t("nl.dayLabel")
                color: Colors.text
                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: parseInt(root.dayTemp) === root.identityK
                      ? Strings.t("nl.dayHintNeutral")
                      : Strings.t("nl.dayHint") + " " + root.identityK + " K"
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
        WSettingsField {
            id: dayField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fixedWidth: 64
            numeric: true
            suffix: Strings.t("nl.kelvin")
            value: root.dayTemp
            validator: (text) => !root.isLocked("DAY_TEMP") && /^[0-9]+$/.test(text)
                                 && parseInt(text) >= root.tempMin && parseInt(text) <= root.tempMax
            borderWidth: HubConfig.border
            onApplied: (text) => root.run(["w-nightlight", "day", text])
            input.Keys.onTabPressed: root.requestFocusReturn()
            input.Keys.onEscapePressed: root.requestFocusReturn()
        }
    }

    // How long the change takes. Only meaningful with a window to ease across —
    // `always` has no boundary to transition at, and `off` never changes at all.
    Item {
        id: rampWrap
        width: parent.width
        implicitHeight: 38
        visible: root.mode === "schedule"
        opacity: root.isLocked("RAMP_MINUTES") ? 0.45 : 1

        Rectangle {
            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
            radius: Geometry.radiusSm
            visible: root.focusedField === "ramp" && !rampField.input.activeFocus
            color: Colors.hover
        }

        Column {
            anchors { left: parent.left; right: rampField.left; rightMargin: 10
                      verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                text: Strings.t("nl.rampLabel")
                color: Colors.text
                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: root.ramp > 0 ? Strings.t("nl.rampHint") : Strings.t("nl.rampInstant")
                color: Colors.muted
                font.family: Fonts.family; font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
        WSettingsField {
            id: rampField
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fixedWidth: 56
            numeric: true
            suffix: Strings.t("power.min")
            value: "" + root.ramp
            validator: (text) => !root.isLocked("RAMP_MINUTES") && /^[0-9]+$/.test(text)
                                 && parseInt(text) <= 720
            borderWidth: HubConfig.border
            onApplied: (text) => root.run(["w-nightlight", "transition", text])
            input.Keys.onTabPressed: root.requestFocusReturn()
            input.Keys.onEscapePressed: root.requestFocusReturn()
        }
    }

    // The window. Two independent fields rather than one combined control: they are
    // set independently in the CLI too, and a single "21:00-07:00" string field would
    // need its own parser for no gain.
    HubSection { width: parent.width; text: Strings.t("nl.window"); visible: root.mode === "schedule" }

    Repeater {
        id: timeRepeater
        model: root.mode === "schedule"
               ? [{ key: "NIGHT_START", field: "start", label: Strings.t("nl.startLabel"), value: root.nightStart },
                  { key: "NIGHT_END",   field: "end",   label: Strings.t("nl.endLabel"),   value: root.nightEnd }]
               : []
        Item {
            id: timeRow
            required property var modelData
            // Exposed for DisplaysPanel's editingText/focusFieldInput reach-through
            // (a Repeater delegate's own ids aren't visible from outside it). A
            // plain property, not `alias` — WSettingsField.input is itself a
            // two-hop alias (WTextBox.input -> TextField), and stacking a third
            // alias hop on top is what PowerPanel.qml:125's known qmllint
            // unresolved-alias finding comes from; a JS-expression property
            // sidesteps qmllint's alias resolver entirely for the same runtime effect.
            property var timeInput: timeField.input
            width: root.width
            implicitHeight: 38
            opacity: root.isLocked(timeRow.modelData.key) ? 0.45 : 1

            Rectangle {
                anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                radius: Geometry.radiusSm
                visible: root.focusedField === timeRow.modelData.field && !timeField.input.activeFocus
                color: Colors.hover
            }

            Text {
                anchors { left: parent.left; right: timeField.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                text: timeRow.modelData.label
                color: Colors.text
                elide: Text.ElideRight
                font.family: Fonts.family; font.pixelSize: 14; font.weight: Font.Medium
            }
            WSettingsField {
                id: timeField
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                fixedWidth: 72
                value: timeRow.modelData.value
                // HH:MM, and a real time — the backend refuses 25:00 anyway, but a
                // field that accepts input it cannot commit is worse than one that
                // simply keeps the Change button dim.
                validator: (text) => {
                    if (root.isLocked(timeRow.modelData.key)) return false;
                    const m = text.match(/^([0-9]{1,2}):([0-9]{2})$/);
                    if (!m) return false;
                    return parseInt(m[1]) <= 23 && parseInt(m[2]) <= 59;
                }
                borderWidth: HubConfig.border
                onApplied: (text) => {
                    // `schedule` takes both ends at once; send the unchanged one alongside.
                    const s = timeRow.modelData.key === "NIGHT_START" ? text : root.nightStart;
                    const e = timeRow.modelData.key === "NIGHT_END"   ? text : root.nightEnd;
                    root.run(["w-nightlight", "schedule", s, e]);
                }
                input.Keys.onTabPressed: root.requestFocusReturn()
                input.Keys.onEscapePressed: root.requestFocusReturn()
            }
        }
    }

    // Why there is no "night light on the login screen" control here.
    Text {
        width: parent.width
        text: Strings.t("nl.greeterNote")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
