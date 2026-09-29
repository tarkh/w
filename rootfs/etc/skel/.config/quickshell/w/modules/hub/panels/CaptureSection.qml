// W Linux — Hub Displays: the "Screen capture" scope.
//
// The fourth segment of DisplaysPanel's scope switch: how recordings are encoded
// and which editor a screenshot opens in. Like NightLightSection it shares no data
// with the output rows, so it is a sibling file the panel loads on demand, and it
// borrows only the panel's dropdown overlay.
//
// A pure front-end over two CLIs: `w-record get|set` and `w-screenshot get|set`.
// Every key is user-scope and read when the NEXT capture starts, so a pick here is
// both the save and the whole effect — nothing live to preview or undo. The only
// cross-key rule (no hardware WebM) is the CLI's: `w-record set` refuses the pair,
// and this file merely never offers it — vaapi drops out of Encoder while the
// format is WebM, and WebM out of Format while the encoder is vaapi.
//
// Policy locks come from `w-conf list <subsys> --porcelain`, the same source and
// shape as NightLightSection/PowerPanel.
import QtQuick
import Quickshell.Io
import qs.core
import qs.modules.hub

Column {
    id: root

    // DisplaysPanel's HubDropdown (one overlay per panel).
    property var menuLayer: null

    // ── Keyboard roving-focus (owned by DisplaysPanel, see NightLightSection) ─────
    // Field names match DisplaysPanel.buildContent(); `fields` is the visible,
    // ordered list the panel roves over — RECORDER only exists as a choice once
    // more than one backend is installed.
    property string focusedField: ""
    readonly property var fields: (root.backends.length > 1 ? ["recorder"] : [])
        .concat(["encoder", "audio", "format", "framerate", "mask", "annotator", "shadow"])
    function rowItem(field) {
        return ({ recorder: recorderRow, encoder: encoderRow, audio: audioRow, format: formatRow,
                  framerate: rateRow, mask: maskRow, annotator: annotatorRow, shadow: shadowRow })[field] || null;
    }
    function activateField(field) { const r = root.rowItem(field); if (r) r.activated(); }

    spacing: 12

    // ── State ──────────────────────────────────────────────────────────────────────
    property var rec: ({ RECORDER: "wf", ENCODER: "auto", AUDIO: "system", FORMAT: "mp4", FRAMERATE: "30", WINDOW_MASK: "no" })
    property var backends: ["wf"]
    property string annotator: "flameshot"
    property string shadow: "yes"
    property var locked: ({})             // "record/KEY" | "screenshot/KEY" -> true

    function parseKv(text) {
        const kv = {};
        for (const line of (text || "").split("\n")) {
            const m = line.match(/^([A-Z_]+)=(.*)$/);
            if (m) kv[m[1]] = m[2];
        }
        return kv;
    }
    Process {
        id: recProc
        running: true
        command: ["w-record", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = root.parseKv(this.text);
                root.backends = (kv.BACKENDS || "").split(",").filter(x => x);
                delete kv.BACKENDS;
                root.rec = kv;
            }
        }
    }
    Process {
        id: shotProc
        running: true
        command: ["w-screenshot", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = root.parseKv(this.text);
                root.annotator = kv.ANNOTATOR || "flameshot";
                root.shadow = kv.WINDOW_SHADOW || "yes";
            }
        }
    }
    // One read per layer — `w-conf list` takes a single subsystem.
    function takeLocks(subsys, text) {
        const locked = Object.assign({}, root.locked);
        for (const line of (text || "").split("\n")) {
            const f = line.split("\t");
            if (f.length >= 5) locked[subsys + "/" + f[0]] = f[3] === "locked";
        }
        root.locked = locked;
    }
    Process {
        id: recConfProc
        running: true
        command: ["w-conf", "list", "record", "--porcelain"]
        stdout: StdioCollector { onStreamFinished: root.takeLocks("record", this.text) }
    }
    Process {
        id: shotConfProc
        running: true
        command: ["w-conf", "list", "screenshot", "--porcelain"]
        stdout: StdioCollector { onStreamFinished: root.takeLocks("screenshot", this.text) }
    }
    function reloadAll() {
        recProc.running = false;      recProc.running = true;
        shotProc.running = false;     shotProc.running = true;
        recConfProc.running = false;  recConfProc.running = true;
        shotConfProc.running = false; shotConfProc.running = true;
    }

    Process { id: setProc; onExited: root.reloadAll() }
    function run(cmd) { setProc.running = false; setProc.command = cmd; setProc.running = true; }
    function pick(row, key, options, current, cmd) {
        if (root.menuLayer)
            root.menuLayer.openMenu(row, options, current, (id) => root.run(cmd.concat([key, id])));
    }

    // ── Options ────────────────────────────────────────────────────────────────────
    function opts(prefix, ids) { return ids.map(id => ({ id: id, label: Strings.t(prefix + id) })); }
    function label(prefix, id) { return id ? Strings.t(prefix + id) : "—"; }
    function fpsLabel(v) { return v + " " + Strings.t("cap.fps"); }

    readonly property var encoderOptions: root.opts("cap.encoder.",
        root.rec.FORMAT === "webm" ? ["auto", "cpu"] : ["auto", "cpu", "vaapi"])
    readonly property var formatOptions: root.opts("cap.format.",
        root.rec.ENCODER === "vaapi" ? ["mp4", "mkv"] : ["mp4", "mkv", "webm"])
    // A rate set from the CLI outside the list still shows as itself (same idea as
    // DisplaysPanel's scale options) rather than snapping to a neighbour.
    readonly property var rateOptions: {
        const ids = ["15", "24", "30", "60", "120"];
        const cur = root.rec.FRAMERATE;
        if (cur && ids.indexOf(cur) < 0) ids.push(cur);
        ids.sort((a, b) => parseInt(a) - parseInt(b));
        return ids.map(id => ({ id: id, label: root.fpsLabel(id) }));
    }

    // ── Rows ───────────────────────────────────────────────────────────────────────
    Text {
        width: parent.width
        text: Strings.t("cap.hint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    HubSection { width: parent.width; text: Strings.t("cap.sectionRecord") }

    SelectRow {
        id: recorderRow
        width: parent.width
        visible: root.backends.length > 1
        focused: root.focusedField === "recorder"
        glyph: String.fromCodePoint(0xf0567)   // nf-md-video
        label: Strings.t("cap.recorder")
        currentId: root.rec.RECORDER || ""
        value: root.label("cap.recorder.", root.rec.RECORDER)
        options: root.opts("cap.recorder.", root.backends)
        locked: root.locked["record/RECORDER"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(recorderRow, "RECORDER", options, currentId, ["w-record", "set"])
    }
    SelectRow {
        id: encoderRow
        width: parent.width
        focused: root.focusedField === "encoder"
        glyph: String.fromCodePoint(0xf061a)   // nf-md-chip
        label: Strings.t("cap.encoder")
        currentId: root.rec.ENCODER || ""
        value: root.label("cap.encoder.", root.rec.ENCODER)
        options: root.encoderOptions
        locked: root.locked["record/ENCODER"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(encoderRow, "ENCODER", options, currentId, ["w-record", "set"])
    }
    SelectRow {
        id: audioRow
        width: parent.width
        focused: root.focusedField === "audio"
        glyph: String.fromCodePoint(0xf057e)   // nf-md-volume_high
        label: Strings.t("cap.audio")
        currentId: root.rec.AUDIO || ""
        value: root.label("cap.audio.", root.rec.AUDIO)
        options: root.opts("cap.audio.", ["system", "mic", "none"])
        locked: root.locked["record/AUDIO"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(audioRow, "AUDIO", options, currentId, ["w-record", "set"])
    }
    SelectRow {
        id: formatRow
        width: parent.width
        focused: root.focusedField === "format"
        glyph: String.fromCodePoint(0xf022b)   // nf-md-file_video
        label: Strings.t("cap.format")
        currentId: root.rec.FORMAT || ""
        value: root.label("cap.format.", root.rec.FORMAT)
        options: root.formatOptions
        locked: root.locked["record/FORMAT"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(formatRow, "FORMAT", options, currentId, ["w-record", "set"])
    }
    // Why vaapi or WebM just went missing from the other list.
    Text {
        width: parent.width
        visible: root.rec.FORMAT === "webm" || root.rec.ENCODER === "vaapi"
        text: Strings.t("cap.webmCpu")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    SelectRow {
        id: rateRow
        width: parent.width
        focused: root.focusedField === "framerate"
        glyph: String.fromCodePoint(0xf04c5)   // nf-md-speedometer
        label: Strings.t("cap.framerate")
        currentId: root.rec.FRAMERATE || ""
        value: root.rec.FRAMERATE ? root.fpsLabel(root.rec.FRAMERATE) : "—"
        options: root.rateOptions
        locked: root.locked["record/FRAMERATE"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(rateRow, "FRAMERATE", options, currentId, ["w-record", "set"])
    }
    SelectRow {
        id: maskRow
        width: parent.width
        focused: root.focusedField === "mask"
        glyph: String.fromCodePoint(0xf0ca4)   // nf-md-rounded_corner
        label: Strings.t("cap.mask")
        currentId: root.rec.WINDOW_MASK || ""
        value: root.label("cap.yesno.", root.rec.WINDOW_MASK)
        options: root.opts("cap.yesno.", ["yes", "no"])
        locked: root.locked["record/WINDOW_MASK"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(maskRow, "WINDOW_MASK", options, currentId, ["w-record", "set"])
    }
    // Why "window" ignores the encoder pick while the mask is on.
    Text {
        width: parent.width
        visible: root.rec.WINDOW_MASK === "yes"
        text: Strings.t("cap.maskCpu")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    HubSection { width: parent.width; text: Strings.t("cap.sectionShots") }

    SelectRow {
        id: annotatorRow
        width: parent.width
        focused: root.focusedField === "annotator"
        glyph: String.fromCodePoint(0xf0f49)   // nf-md-draw
        label: Strings.t("cap.annotator")
        currentId: root.annotator
        value: root.label("cap.annotator.", root.annotator)
        options: root.opts("cap.annotator.", ["flameshot", "satty"])
        locked: root.locked["screenshot/ANNOTATOR"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(annotatorRow, "ANNOTATOR", options, currentId, ["w-screenshot", "set"])
    }
    SelectRow {
        id: shadowRow
        width: parent.width
        focused: root.focusedField === "shadow"
        glyph: String.fromCodePoint(0xf0637)   // nf-md-box_shadow
        label: Strings.t("cap.shadow")
        currentId: root.shadow
        value: root.label("cap.yesno.", root.shadow)
        options: root.opts("cap.yesno.", ["yes", "no"])
        locked: root.locked["screenshot/WINDOW_SHADOW"] === true
        lockedHint: Strings.t("hub.lockedByPolicy")
        onActivated: root.pick(shadowRow, "WINDOW_SHADOW", options, currentId, ["w-screenshot", "set"])
    }
    Text {
        width: parent.width
        text: Strings.t("cap.shadowHint")
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
