// W Linux — Hub Appearance: the "Settings" tab.
//
// Per-user overrides that beat the active theme without editing it — a pure
// front-end over `w-appearance` (see w-style.md / config-effects.md / w-style
// modules 100-effects/100-motion/600-rgb for what each override actually does
// downstream).
// The third override this file used to carry, the bar's position, moved to the Bar
// tab (BarSection.qml) so that every bar control has exactly one door; the CLI verb
// behind it is still `w-appearance bar-position`.
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
import qs.modules.shading

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
    // Flickable/scrollIntoView here — up to six rows (three once RGB is off) are
    // always well under the maxCardH−chrome floor (see Security/DateTime
    // precedent). `fields` is DYNAMIC (the three rgb-level:N entries only exist
    // while RGB is on), same contract as BarSection's own dynamic field list —
    // AppearancePanel reads it back into its "settings" region instead of a
    // fixed array. The three RGB swatches are each their OWN roving entry
    // (rgb-level:0/1/2) rather than one row that cycles on confirm — same idiom
    // as ThemeCreatePanel's seed-swatch Repeater, which is how a Hub control
    // gets real left/right-shaped keyboard choice out of an up/down-only roving
    // list: each choice is just the next "row".
    property string focusedField: ""
    readonly property var fields: root.rgb === "on"
        ? ["blur", "motion", "rgb", "rgb-level:0", "rgb-level:1", "rgb-level:2"]
        : ["blur", "motion", "rgb"]
    function activateField(field) {
        if (field === "blur") blurRow.activated();
        else if (field === "motion") motionRow.activated();
        else if (field === "rgb") rgbRow.activated();
        else {
            const m = /^rgb-level:(\d+)$/.exec(field);
            const item = m ? rgbLevelRepeater.itemAt(parseInt(m[1], 10)) : null;
            if (item) item.activated();
        }
    }

    spacing: 12

    // ── State (one porcelain read) ──────────────────────────────────────────────
    property string blur: "theme"
    property string motion: "theme"
    property string rgb: "on"
    property string rgbLevel: "medium"
    property string rgbSoftHex: ""
    property string rgbMediumHex: ""
    property string rgbCrispHex: ""

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
                root.blur = kv.BLUR || "theme";
                root.motion = kv.MOTION || "theme";
                root.rgb = kv.RGB || "on";
                root.rgbLevel = kv.RGB_LEVEL || "medium";
                root.rgbSoftHex = kv.RGB_SOFT_HEX || "";
                root.rgbMediumHex = kv.RGB_MEDIUM_HEX || "";
                root.rgbCrispHex = kv.RGB_CRISP_HEX || "";
            }
        }
    }

    Process { id: setProc; onExited: root.reload() }
    function run(cmd) { setProc.running = false; setProc.command = cmd; setProc.running = true; }

    readonly property var offOptions: [
        { id: "theme", label: Strings.t("appear.fromTheme") },
        { id: "off",   label: Strings.t("appear.off") },
    ]
    function offLabel(id) { for (const o of root.offOptions) if (o.id === id) return o.label; return id; }

    // RGB has no "From theme" slot: unset already means "follow the theme", so
    // the plain on/off pair is the whole vocabulary (w-appearance rgb).
    // Deliberately NOT named `onOff...` — names beginning with "on" collide with
    // QML signal-handler resolution and read back as undefined at runtime.
    readonly property var rgbOptions: [
        { id: "on",  label: Strings.t("appear.rgb.yes") },
        { id: "off", label: Strings.t("appear.rgb.no") },
    ]
    function rgbLabel(id) { for (const o of root.rgbOptions) if (o.id === id) return o.label; return id; }

    Text {
        width: parent.width
        text: Strings.t("appear.hint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
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

    SelectRow {
        id: rgbRow
        width: parent.width
        glyph: String.fromCodePoint(0xf07d6)   // nf-md-led-strip
        label: Strings.t("appear.rgb")
        currentId: root.rgb
        value: root.rgbLabel(root.rgb)
        options: root.rgbOptions
        focused: root.focusedField === "rgb"
        onActivated: if (root.menuLayer)
            root.menuLayer.openMenu(rgbRow, options, root.rgb,
                                    (id) => root.run(["w-appearance", "rgb", id]))
    }

    // Which of the theme's three RGB pigments (theme.conf's W_RGB_SOFT/MEDIUM/
    // CRISP) colors the hardware — swatches show the theme's own computed colour
    // (from `w-appearance status --porcelain`) rather than a fixed palette, same
    // idea as ThemeCreatePanel's palette-preview row. Meaningless while RGB
    // lighting is off, so it collapses out of both the layout and the roving
    // list (see `fields` above) exactly like ThemeCreatePanel's seed-swatch row
    // collapsing when an image offers only one candidate colour.
    readonly property var rgbLevels: [
        { id: "soft",   hex: root.rgbSoftHex,   label: Strings.t("appear.rgb.soft") },
        { id: "medium", hex: root.rgbMediumHex, label: Strings.t("appear.rgb.medium") },
        { id: "crisp",  hex: root.rgbCrispHex,  label: Strings.t("appear.rgb.crisp") },
    ]

    Column {
        width: parent.width
        spacing: 6
        visible: root.rgb === "on"
        // leftMargin 32 = ChromeIcon's 22 + SelectRow's 10 spacing — aligns with
        // the labels above though this block carries no icon of its own (a level
        // picker for the row right above it, not a new concept).
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 32
            text: Strings.t("appear.rgb.level")
            color: Colors.text
            font.family: Fonts.family
            font.pixelSize: 13
        }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 32
            spacing: 8
            Repeater {
                id: rgbLevelRepeater
                model: root.rgbLevels
                delegate: Rectangle {
                    id: swatch
                    required property var modelData
                    required property int index
                    readonly property bool on: root.rgbLevel === modelData.id
                    readonly property bool focused: root.focusedField === "rgb-level:" + swatch.index
                    // Same "give a bare Item the SelectRow/HubRow `activated()`
                    // contract" as ThemeCreatePanel's seed swatches, so the
                    // panel's confirm-dispatcher can drive it uniformly.
                    signal activated()
                    onActivated: root.run(["w-appearance", "rgb-level", modelData.id])
                    width: 26; height: 26
                    radius: Geometry.radiusSm
                    color: modelData.hex || Colors.muted
                    // Selection is the ring, keyboard focus adds a scale lift
                    // (both mirror ThemeCreatePanel's seed swatches) — a thin
                    // ring alone can vanish against a swatch close to the
                    // theme's own accent hue, the size change reads regardless.
                    scale: swatch.focused ? 1.15 : 1
                    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                    border.width: (swatch.on || swatch.focused) ? 3 : 1
                    border.color: (swatch.on || swatch.focused) ? Colors.accentInk : Colors.border
                    MouseArea {
                        id: swatchMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: swatch.activated()
                        WToolTip { text: modelData.label; visible: swatchMa.containsMouse }
                    }
                }
            }
        }
    }
}
