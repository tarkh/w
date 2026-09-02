// W Linux — clipboard-history viewer.
// A search popup over a tinted, compositor-blurred full-screen backdrop — the same
// layer-shell overlay pattern as the Launcher (grab keyboard focus, scrim + blur,
// scale-in card, height-morph). Toggled by a Hyprland global shortcut ($mod+V).
//
// The store is cliphist (fed by two `wl-paste --watch w-cliphist-store` daemons in
// hyprland.lua — the gate honours the manager on/off + password-filter toggles): a
// persistent db that survives closing the source app and reboots. Image rows show a
// lazily-decoded thumbnail (bounded to visible rows) in a fixed square media cell, so
// rows stay one height. cliphist is "pipes only, no picker", so this IS the picker:
//   • open  → `cliphist list`            → rows `<id>\t<preview>` (images: a
//                                            `[[ binary data … ]]` descriptor)
//   • copy  → `echo <id> | cliphist decode | wl-copy`  (decode recalls the entry
//                                            byte-for-byte from the leading id)
//   • del   → `echo <id> | cliphist delete`            (Shift+Del, Ctrl+menu_delete
//                                            or the row ✕)
//   • wipe  → `cliphist wipe`                           (Ctrl+Shift+Del)
// Theme colors/motion/geometry/effects/fonts all come from the shared singletons and
// live-reload. See quickshell-clipboard.md.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import qs.core

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any
    // other popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "clipboard"

    // Visually shown: open AND not suspended. Suspended = stepped aside for a higher-
    // priority modal (the auth prompt): the card hides + releases keyboard focus but
    // stays logically open, restoring when the modal closes (same contract as the Hub).
    readonly property bool shown: root.active && !Overlays.suspended

    // All history entries: [{ id: "42", preview: "…", isImage: bool }]. Rebuilt from
    // `cliphist list` on every open and after a delete/wipe.
    property var entries: []

    // Thumbnail cache: image entries are decoded to a private cache dir on demand
    // (per visible row). `thumbTag` is a fresh per-open nonce baked into each file
    // name so a decode never collides with a stale file from a previous session and
    // cleanup can prune everything not tagged with the current open — no race with the
    // in-flight decodes writing the current tag.
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/w/clip-thumb"
    property string thumbTag: ""

    // Last pointer position in SCENE coords — hover-select only on genuine mouse
    // movement, so rows scrolling under a stationary cursor (open / keyboard nav)
    // don't hijack the selection. Reset on open. Same guard as the Launcher.
    property var lastPointer: null

    // Card geometry. Width is the shared Overlays.cardWidth so launcher/clipboard/hub
    // read as one centered surface (clipboard text elides a touch sooner as a result).
    readonly property int cardW: Overlays.cardWidth
    readonly property int rowH: 44
    readonly property int maxCardH: 520
    // Vertical pin reference: the card top is pinned as if the card were `pinRef` tall
    // (top-pinned so the search field never moves as the list morphs). Deliberately
    // equal to the Launcher's card height (480), NOT our own maxCardH (520), so the two
    // popups' search fields land at the exact same screen Y — they read as one center.
    readonly property int pinRef: 480
    // margins(12+12) + header(48) + footer(18) + spacing×2(24) = 114
    readonly property int chrome: 114

    // Toggle from Hyprland:  bind = SUPER, V, global, quickshell:clipboard
    GlobalShortcut {
        appid: "quickshell"
        name: "clipboard"
        // Manager disabled → the viewer won't open (history is also not recorded, gated
        // in w-cliphist-store). One toggle, both sides.
        onPressed: {
            if (ClipboardConfig.enabled) Overlays.toggle("clipboard");
            else Overlays.close("clipboard");
        }
    }

    // ── History source ──────────────────────────────────────────────────────────
    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = (this.text || "").split("\n");
                for (const line of lines) {
                    if (line.length === 0) continue;
                    const t = line.indexOf("\t");
                    if (t < 0) continue;
                    const id = line.substring(0, t);
                    const preview = line.substring(t + 1);
                    out.push({
                        id: id,
                        preview: preview,
                        isImage: /^\s*\[\[\s*binary data/.test(preview),
                    });
                }
                root.entries = out;
                list.currentIndex = 0;
            }
        }
    }

    // Delete / wipe run here; on exit the list is refreshed so the view stays honest.
    Process {
        id: mutateProc
        onExited: listProc.running = true
    }

    // Ensure the cache dir exists and drop any file not tagged with the current open.
    Process { id: cleanupProc }

    function reload()  { listProc.running = true; }

    // New open: pick a fresh thumb nonce and prune stale files. Current-tag decodes
    // are written after this runs, so the `! -name <tag>-*` prune can't hit them.
    function prepThumbs() {
        thumbTag = "t" + Date.now();
        cleanupProc.command = ["sh", "-c",
            "mkdir -p '" + thumbDir + "' && find '" + thumbDir
            + "' -maxdepth 1 -type f ! -name '" + thumbTag + "-*' -delete"];
        cleanupProc.running = true;
    }

    // cliphist's image descriptor `[[ binary data 42 KiB png 1920x1080 ]]` → a tidy
    // "PNG · 1920×1080 · 42 KiB". Falls back to the cleaned descriptor if it doesn't
    // match the expected shape.
    function imageLabel(preview) {
        const m = String(preview).match(/binary data\s+(.+?)\s+(\S+)\s+(\d+)x(\d+)/i);
        if (!m)
            return String(preview).replace(/[\[\]]/g, "").replace("binary data", "").trim();
        return m[2].toUpperCase() + " · " + m[3] + "×" + m[4] + " · " + m[1].trim();
    }

    // Filtered view: empty query → full history; else case-insensitive substring on
    // the preview. Referenced properties (search.text, root.entries) make `model:
    // root.view()` recompute reactively, mirroring the launcher.
    function view() {
        const q = search.text.trim().toLowerCase();
        if (q === "")
            return root.entries;
        return root.entries.filter(e => e.preview.toLowerCase().indexOf(q) >= 0);
    }

    // id is a pure integer from cliphist → safe to embed in sh -c. decode/delete read
    // the leading id from stdin and split on the TAB (cliphist's `<id>\t<preview>`
    // row format), so the id must be fed with a trailing tab — a bare `echo <id>`
    // hands them "<id>\n" and they abort ("parsing … invalid syntax"). printf '%s\t'.
    function copyEntry(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t' " + e.id + " | cliphist decode | wl-copy"]);
        Overlays.close("clipboard");
    }
    function deleteEntry(e) {
        if (!e) return;
        mutateProc.command = ["sh", "-c", "printf '%s\\t' " + e.id + " | cliphist delete"];
        mutateProc.running = true;
    }
    function wipeAll() {
        mutateProc.command = ["cliphist", "wipe"];
        mutateProc.running = true;
    }

    PanelWindow {
        id: win

        visible: root.shown || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                root.prepThumbs();      // fresh thumb nonce + prune stale cache
                root.reload();          // fresh snapshot on every open
                list.currentIndex = 0;
                root.lastPointer = null;
                search.input.forceActiveFocus();
            } else if (!root.active) {
                search.text = "";       // reset only on a real close, not a suspend
            }
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Click outside the card to dismiss. Tint + blur come from the shared
            // Backdrop surface (modules/overlay), so this layer is input-only.
            MouseArea { anchors.fill: parent; onClicked: Overlays.close("clipboard") }

            Rectangle {
                id: card
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - root.pinRef) / 2)
                width: root.cardW
                height: Math.min(root.maxCardH, root.chrome + Math.max(1, list.count) * root.rowH)
                radius: Geometry.radius
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: ClipboardConfig.border
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                transformOrigin: Item.Top
                scale: root.shown ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // ── Search field ──────────────────────────────────────────
                    WQueryField {
                        id: search
                        width: parent.width
                        placeholder: Strings.t("clipboard.searchPlaceholder")

                        onTextChanged: list.currentIndex = 0

                        // Mode B: the field owns the keyboard the whole time the palette
                        // is open, so bare ↑↓/Enter/Esc plus Ctrl+<profile chord> — one
                        // resolver for every W palette, see core/HubNavKeys.qml. Removal
                        // rides its "delete" action (Shift+Del/Shift+Backspace fixed,
                        // Ctrl+menu_delete profile-aware).
                        input.Keys.onPressed: (e) => {
                            // Wipe-all first, and not for tidiness: with menu_delete on
                            // Delete (the default profile) Ctrl+Shift+Del also satisfies
                            // the resolver's Ctrl rule, so testing it afterwards would
                            // clear one entry instead of the history.
                            if (e.key === Qt.Key_Delete
                                && (e.modifiers & Qt.ShiftModifier) && (e.modifiers & Qt.ControlModifier)) {
                                root.wipeAll();
                                e.accepted = true;
                                return;
                            }
                            switch (HubNavKeys.fieldAction(e)) {
                            case "down":    list.incrementCurrentIndex(); e.accepted = true; return;
                            case "up":      list.decrementCurrentIndex(); e.accepted = true; return;
                            case "confirm": root.copyEntry(list.model[list.currentIndex]); e.accepted = true; return;
                            case "back":    Overlays.close("clipboard"); e.accepted = true; return;
                            case "delete":  root.deleteEntry(list.model[list.currentIndex]); e.accepted = true; return;
                            }
                        }
                    }

                    // ── History list ──────────────────────────────────────────
                    ListView {
                        id: list
                        // Extend into the card's right padding (margin 12 → pill ~4px from
                        // the edge); delegates inset the same 8 so rows stay put and only
                        // the shared scrollbar moves near the window edge.
                        width: parent.width + 8
                        height: parent.height - search.height - footer.height - parent.spacing * 2
                        clip: true
                        model: root.view()
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false

                        // Shared scroll indicator (auto-hides when it fits).
                        ScrollBar.vertical: WScrollBar {}

                        highlightMoveDuration: Motion.fast
                        highlightResizeDuration: 0
                        highlightFollowsCurrentItem: true
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: height
                        highlight: Rectangle {
                            radius: Geometry.radiusSm
                            color: Colors.accent
                        }

                        // Empty-state hint (no history / no matches).
                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: Strings.t("clipboard.empty")
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 15
                        }

                        delegate: Item {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: ListView.view.width - 8   // inset the view's gutter extension
                            height: root.rowH

                            readonly property bool current: ListView.isCurrentItem

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                spacing: 12

                                // Leading media cell — a fixed square holding either
                                // the type glyph or, for image rows, the decoded
                                // thumbnail. Fixed size keeps every row the same height
                                // and the text column aligned: no rift between text and
                                // image rows.
                                Item {
                                    id: media
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: ClipboardConfig.thumbSize
                                    height: ClipboardConfig.thumbSize

                                    readonly property bool wantThumb: rowItem.modelData.isImage && ClipboardConfig.showThumbnails
                                    readonly property string thumbPath: root.thumbDir + "/" + root.thumbTag + "-" + rowItem.modelData.id
                                    property bool thumbReady: false

                                    // Decode this image entry to its cache file on first
                                    // show; the Image binds once it exists. Bounded to
                                    // visible rows (ListView recreates offscreen ones).
                                    Process {
                                        id: decodeProc
                                        command: ["sh", "-c", "printf '%s\\t' " + rowItem.modelData.id
                                            + " | cliphist decode > '" + media.thumbPath + "'"]
                                        onExited: (code) => { if (code === 0) media.thumbReady = true; }
                                    }
                                    Component.onCompleted: if (media.wantThumb) decodeProc.running = true;

                                    // Type glyph — text rows, and image rows until (or
                                    // without) a ready thumbnail.
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !(media.wantThumb && media.thumbReady)
                                        text: rowItem.modelData.isImage
                                            ? String.fromCodePoint(0xf021f)   // nf-md-image
                                            : String.fromCodePoint(0xf0192)   // nf-md-clipboard_text
                                        font.family: Fonts.mono
                                        font.pixelSize: 16
                                        color: rowItem.current ? Colors.accentFg : Colors.muted
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    }

                                    // Thumbnail — rounded, aspect-cropped to the square.
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 6
                                        clip: true
                                        color: "transparent"
                                        visible: media.wantThumb && media.thumbReady
                                        Image {
                                            anchors.fill: parent
                                            source: (media.wantThumb && media.thumbReady) ? ("file://" + media.thumbPath) : ""
                                            fillMode: Image.PreserveAspectCrop
                                            cache: false
                                            asynchronous: true
                                            sourceSize.width: ClipboardConfig.thumbSize * 2
                                            sourceSize.height: ClipboardConfig.thumbSize * 2
                                        }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Text rows: collapse whitespace so multi-line
                                    // snippets show as one tidy line. Image rows: a tidy
                                    // "PNG · 1920×1080 · 42 KiB" label. Elide the rest.
                                    text: {
                                        const md = rowItem.modelData;
                                        let p = md.isImage ? root.imageLabel(md.preview) : String(md.preview);
                                        p = p.replace(/\s+/g, " ").trim();
                                        return p.length > ClipboardConfig.maxPreview
                                            ? p.substring(0, ClipboardConfig.maxPreview)
                                            : p;
                                    }
                                    color: rowItem.current ? Colors.accentFg : Colors.text
                                    font.family: Fonts.family
                                    font.pixelSize: 15
                                    elide: Text.ElideRight
                                    width: rowItem.width - 24 - ClipboardConfig.thumbSize - delBtn.width - parent.spacing * 2
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                            }

                            // Per-row delete button — visible on the current row (and
                            // on hover), the obvious way to prune one entry.
                            Text {
                                id: delBtn
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                text: String.fromCodePoint(0xf0156)   // nf-md-close_circle_outline
                                font.family: Fonts.mono
                                font.pixelSize: 16
                                color: delArea.containsMouse ? Colors.dangerBorder
                                    : (rowItem.current ? Colors.accentFg : Colors.muted)
                                opacity: (rowItem.current || rowHover.containsMouse) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                MouseArea {
                                    id: delArea
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.deleteEntry(rowItem.modelData)
                                }
                            }

                            MouseArea {
                                id: rowHover
                                anchors.fill: parent
                                anchors.rightMargin: 30   // leave the ✕ its own area
                                hoverEnabled: true
                                onPositionChanged: (mouse) => {
                                    const p = rowItem.mapToItem(null, mouse.x, mouse.y);
                                    if (root.lastPointer === null) { root.lastPointer = p; return; }
                                    if (Math.abs(p.x - root.lastPointer.x) + Math.abs(p.y - root.lastPointer.y) < 2)
                                        return;
                                    root.lastPointer = p;
                                    list.currentIndex = rowItem.index;
                                }
                                onClicked: root.copyEntry(rowItem.modelData)
                            }
                        }
                    }

                    // ── Footer hints ──────────────────────────────────────────
                    Item {
                        id: footer
                        width: parent.width
                        height: 18

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Strings.t("clipboard.hints")
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: list.count > 0
                            text: list.count + ""
                            color: Colors.muted
                            font.family: Fonts.mono
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }

            // Topmost of all: no hover highlight while the cursor is hidden, so the
            // keyboard selection is the only mark on screen (see core/HoverGate).
            HoverGate { anchors.fill: parent }
        }
    }
}
