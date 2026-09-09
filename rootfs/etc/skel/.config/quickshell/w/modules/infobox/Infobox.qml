// W Linux — generic "infobox" overlay: a title + Markdown body + optional action
// buttons, in the same modal-center card style as the launcher/assistant/Hub. Not
// tied to any one feature: callers drive it entirely through content set via
// Overlays.openInfobox({ title, bodyMarkdown, actions }) — e.g. the assistant's
// readiness gate uses it today to explain an incomplete AI config (see
// modules/assistant/Assistant.qml); a future help/skill viewer can reuse it as-is
// by handing it a loaded .md file's text as bodyMarkdown. Body rendering goes
// through core/Markdown (canonical GFM in, themed rich text out — block rhythm,
// code plaques, shell highlighting, link colour), scrollable so long content
// (e.g. a full docs page) fits.
//
//   content = {
//     title: string,
//     bodyMarkdown: string,
//     glyph: string,   // optional — a large centred glyph above the title, which also
//                      // centres the title: a card that states one thing rather than
//                      // explaining several (session restore's curtain).
//     actions: [ { label: string, primary: bool /* optional */, exec: function } ],  // optional
//     onLink: function(link)   // optional — take over link hits entirely (the docs
//                              // viewer navigates between its pages with them);
//                              // default opens the link in the browser
//   }
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import qs.core

Scope {
    id: root

    // The hotkey (catalog token "docs", SUPER + F1): documentation on demand,
    // landing on index.md. Handled here because this module already owns the
    // rendering surface; the resolution logic is core/DocsViewer's.
    GlobalShortcut {
        appid: "quickshell"
        name: "docs"
        onPressed: DocsViewer.openIndex()
    }

    readonly property bool active: Overlays.current === "infobox"
    // Reset the roving cursor on every real open (not suspend/resume) — a fresh
    // openInfobox() call means a fresh actions array.
    onActiveChanged: if (active) card.focusIndex = 0
    // A page or link switch replaces the body in place — always land the reader at
    // the top of what they opened, and drop the stale copy source with it.
    onBlocksChanged: { bodyFlick.contentY = 0; card.copyFrom = null; }
    readonly property bool shown: root.active && !Overlays.suspended
    readonly property var content: Overlays.infoboxContent || ({})
    // The body, already split into prose/code chunks by the shared renderer.
    readonly property var blocks: Markdown.render(root.content.bodyMarkdown || "")

    // A PASSIVE card takes no keyboard focus. It exists for the one caller whose
    // card is scenery rather than a dialog: the session curtain, which is raised
    // over a desktop that w-session is actively rearranging.
    //
    // This is not a style choice, it is a correctness one, and it cost a silent
    // regression to find. An exclusive-keyboard-focus layer surface does not just
    // grab the keys — it FREEZES which window is active: measured, `hl.dsp.focus`
    // on a window answers "ok" and changes nothing while such a layer is up. The
    // whole of phase 2 is built on focusing an anchor window (dwindle cuts the
    // ACTIVE window, and `splitratio` sets the ratio of the ACTIVE window's
    // split), so with a focus-grabbing curtain over it every restore came back
    // with default 50/50 splits — the exact thing the feature exists to preserve.
    // Hyprland said so every time ("cannot alter split ratio"); nobody was
    // listening, because hyprctl reports a dispatcher warning with exit code 0.
    readonly property bool passive: root.content.passive === true

    readonly property int cardW: Overlays.cardWidth
    readonly property int pinRef: 480
    readonly property int maxBodyHeight: 320

    // A TALL card is the documentation viewer's form: pinned to the launcher's
    // full height, body Flickable filling what the header and actions leave.
    // Kept as a content flag rather than a separate popup: same surface, same
    // fallback rules, the docs are just this card's long-form guest.
    readonly property bool docsTall: root.content.tall === true
    // Optional back affordance in the header ({ exec, label? }) — a deep-linked
    // card gets "‹ Back" at the LEFT and a left-aligned compact title; without
    // it the card keeps its statement layout (and glyph cards stay centred).
    readonly property var back: root.content.back || null

    PanelWindow {
        id: win
        visible: root.shown || fade.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Tint + blur come from the shared Backdrop surface (infobox is in
        // Overlays.blurGroup) — same contract as assistant/launcher/Hub.
        WlrLayershell.namespace: "quickshell:infobox"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: (root.shown && !root.passive)
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            id: fade
            anchors.fill: parent
            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            MouseArea { anchors.fill: parent; onClicked: Overlays.close("infobox") }

            Rectangle {
                id: card
                x: Math.round((fade.width - width) / 2)
                y: Math.round((fade.height - root.pinRef) / 2)
                width: root.cardW
                // A document earns more air than a three-line statement does.
                readonly property int padC: root.docsTall ? 16 : 12
                height: root.docsTall
                    ? root.pinRef
                    : Math.min(col.implicitHeight + padC * 2,
                               root.maxBodyHeight + col.spacing * 2 + padC * 2)
                radius: Geometry.radius
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: 1

                // Bespoke roving over content.actions (0..N buttons) — same pattern as
                // the Auth GUI's dialog buttons, just a flat Row instead of a column.
                readonly property var actionsList: root.content.actions || []
                property int focusIndex: 0
                // The code block holding the current selection, if any (only code is
                // selectable — see the body below).
                property var copyFrom: null
                onActionsListChanged: card.focusIndex = Math.max(0, Math.min(card.focusIndex, card.actionsList.length - 1))
                // Scroll the body by dy, clamped. The tall card is a document: the
                // reader must be able to reach the bottom of a page without a mouse.
                function scrollBy(dy) {
                    const lim = Math.max(0, bodyFlick.contentHeight - bodyFlick.height);
                    bodyFlick.contentY = Math.max(0, Math.min(lim, bodyFlick.contentY + dy));
                }
                function activateFocused() {
                    const a = card.actionsList[card.focusIndex];
                    if (!a) return;
                    if (a.exec) a.exec();
                    Overlays.close("infobox");
                }

                // Hold focus so Esc works while open (like the power menu).
                focus: root.shown
                Keys.onEscapePressed: Overlays.close("infobox")
                Keys.onPressed: (e) => {
                    // Copy out of the code block the reader last selected in.
                    if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) {
                        if (card.copyFrom) card.copyFrom.copy();
                        e.accepted = true; return;
                    }
                    // On a TALL card the arrows and page keys scroll: there is more
                    // page than fits, and the actions row (0-1 buttons) has no use
                    // for a vertical axis.
                    if (root.docsTall) {
                        const page = Math.max(40, bodyFlick.height - 24);
                        switch (e.key) {
                        case HubNavKeys.down:  card.scrollBy(60);    e.accepted = true; return;
                        case HubNavKeys.up:    card.scrollBy(-60);   e.accepted = true; return;
                        case Qt.Key_PageDown:  card.scrollBy(page);  e.accepted = true; return;
                        case Qt.Key_PageUp:    card.scrollBy(-page); e.accepted = true; return;
                        case Qt.Key_Home:      bodyFlick.contentY = 0; e.accepted = true; return;
                        case Qt.Key_End:       card.scrollBy(bodyFlick.contentHeight); e.accepted = true; return;
                        }
                    }
                    if (card.actionsList.length === 0) return;
                    switch (e.key) {
                    case HubNavKeys.left:
                        card.focusIndex = Math.max(0, card.focusIndex - 1);
                        e.accepted = true; return;
                    case HubNavKeys.right:
                        card.focusIndex = Math.min(card.actionsList.length - 1, card.focusIndex + 1);
                        e.accepted = true; return;
                    case HubNavKeys.confirm:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        card.activateFocused();
                        e.accepted = true; return;
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

                MouseArea { anchors.fill: parent }   // swallow clicks (don't dismiss)

                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: card.padC
                    spacing: 10

                    // Header line: optional ‹ Back + title on ONE compact line
                    // (the docs card). The glyph form — a large centred glyph above
                    // a centred title — stays for statement cards (curtain, AI gate).
                    // Header: ONE compact line, laid out by hand over a plain Item —
                    // NOT a Row: children of positioners may not anchor (verticalCenter
                    // is exactly what the back affordance needs), and an anchored child
                    // makes Row refuse to lay out entirely (title flush-left, back
                    // invisible — the runtime warning is easy to miss).
                    Item {
                        id: headerRow
                        width: parent.width
                        height: 26
                        visible: (root.content.title || "").length > 0 || root.back

                        Text {
                            id: backText
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.back
                                ? "‹ " + (root.back.label || Strings.t("hub.back"))
                                : ""
                            color: backMa.containsMouse ? Colors.accentInk : Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 13
                            visible: root.back !== null
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        Text {
                            id: titleText
                            x: root.back ? backText.implicitWidth + 8 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x
                            text: root.content.title || ""
                            color: Colors.text
                            font.family: Fonts.family
                            font.pixelSize: 17
                            font.bold: true
                            elide: Text.ElideRight
                            horizontalAlignment: root.content.glyph ? Text.AlignHCenter : Text.AlignLeft
                            visible: text.length > 0
                        }

                        MouseArea {
                            id: backMa
                            x: 0
                            width: backText.implicitWidth
                            height: parent.height
                            visible: root.back !== null
                            hoverEnabled: true
                            cursorShape: visible ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (root.back && root.back.exec) root.back.exec()
                        }
                    }

                    // A document gets a hairline under its header — the statement
                    // cards do not, their header IS the message.
                    Rectangle {
                        id: sep
                        width: parent.width
                        height: 1
                        color: Colors.alpha(Colors.border, 0.45)
                        visible: root.docsTall
                    }

                    Flickable {
                        id: bodyFlick
                        width: parent.width
                        height: root.docsTall
                            ? card.height - card.padC * 2
                              - headerRow.height
                              - ((root.content.actions || []).length > 0
                                 ? actionsRow.height + col.spacing : 0)
                              - col.spacing
                              - (sep.height + col.spacing)
                            : Math.min(bodyCol.implicitHeight + 16, root.maxBodyHeight)
                        visible: root.blocks.length > 0
                        anchors.rightMargin: -card.padC
                        clip: true
                        contentHeight: bodyCol.implicitHeight + 16
                        boundsBehavior: Flickable.StopAtBounds
                        // Whole-pixel scroll offsets. A wheel or a drag otherwise
                        // leaves contentY on a half pixel, and rich text then has to
                        // be re-rasterised at a subpixel origin on every frame.
                        pixelAligned: true
                        ScrollBar.vertical: WScrollBar {}

                        // The body is a COLUMN OF CHUNKS, not one text item, and both
                        // reasons are load-bearing.
                        //
                        // Prose is a `Text`, never a read-only `TextEdit`. TextEdit was
                        // tried, for selection; a long document inside a Flickable then
                        // came up with WHOLE BLOCKS unpainted — blank where the text
                        // belongs, layout otherwise correct — and scrolling back up
                        // never brought the top ones back. Reproduced by the user on the
                        // VM and on real hardware, reproducible in NO headless probe
                        // here. TextEdit builds its scene graph as per-block nodes
                        // updated incrementally against the viewport it observes; Text
                        // rebuilds its node instead, and does not lose blocks.
                        //
                        // Code is where selection actually matters (a command, a path),
                        // so a code chunk IS a TextEdit — but a small one holding a
                        // single text block, which is not the shape that broke. It also
                        // gets a real Rectangle for its ground: rounded, padded, and
                        // spaced by ordinary layout, where the `<table>` it replaced got
                        // no frame margin from Qt at all and the paragraph above sat on
                        // top of it.
                        Column {
                            id: bodyCol
                            y: 6
                            width: bodyFlick.width - 12
                            spacing: Math.round(Markdown.air * 4)

                            Repeater {
                                model: root.blocks
                                delegate: Loader {
                                    required property var modelData
                                    // Width only: an explicit height here would be bound
                                    // to the item's implicitHeight while the Loader
                                    // resizes the item to that same height — a loop.
                                    // Left alone, the Loader takes the item's implicit
                                    // height and the Column positions by it.
                                    width: bodyCol.width
                                    sourceComponent: modelData.code ? codeChunk : proseChunk
                                    onLoaded: item.html = modelData.html
                                }
                            }
                        }
                    }

                    Component {
                        id: proseChunk
                        Text {
                            property string html: ""
                            text: html
                            textFormat: Text.RichText
                            color: Colors.text
                            linkColor: Colors.accentInk
                            font.family: Fonts.family
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            // Raster glyphs, not distance fields: a long document is the
                            // case where that cache overflows, and this card is static
                            // and pixel-aligned, so it gives up nothing.
                            renderType: Text.NativeRendering
                            // Pointer over links only: HoverHandler rides the already-
                            // hovered text and hoveredLink flips per position, so the
                            // card's plain text keeps the arrow. (Item.hoverEnabled is
                            // not exposed here — the handler carries the hover itself.)
                            HoverHandler {
                                cursorShape: parent.hoveredLink.length > 0
                                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                            onLinkActivated: (link) => {
                                if (root.content.onLink) root.content.onLink(link);
                                else Qt.openUrlExternally(link);
                            }
                        }
                    }

                    Component {
                        id: codeChunk
                        Rectangle {
                            id: codeGround
                            property string html: ""
                            implicitHeight: codeText.implicitHeight + 18
                            radius: Geometry.radiusSm
                            color: Colors.inputBg

                            TextEdit {
                                id: codeText
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.margins: 9
                                text: codeGround.html
                                textFormat: TextEdit.RichText
                                color: Colors.text
                                font.family: Fonts.mono
                                font.pixelSize: 13
                                wrapMode: TextEdit.Wrap
                                renderType: TextEdit.NativeRendering
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Colors.selection
                                selectedTextColor: Colors.text
                                // Never takes Qt focus: the card owns the keys, so
                                // dragging out a selection must not hand the arrows to a
                                // text cursor — nor let a passive card (the session
                                // curtain) start competing for focus.
                                activeFocusOnPress: false
                                // Ctrl+C on the card copies from whichever block was
                                // last selected; a fresh selection anywhere claims it.
                                onSelectedTextChanged: if (selectedText.length > 0) card.copyFrom = codeText
                                HoverHandler { cursorShape: Qt.IBeamCursor }
                            }
                        }
                    }

                    Row {
                        id: actionsRow
                        width: parent.width
                        spacing: 8
                        layoutDirection: Qt.RightToLeft
                        visible: (root.content.actions || []).length > 0

                        Repeater {
                            model: root.content.actions || []
                            delegate: Rectangle {
                                id: actionTile
                                required property var modelData
                                required property int index
                                readonly property bool focused: card.focusIndex === index

                                width: label.implicitWidth + 28
                                height: 34
                                radius: Geometry.radiusSm
                                color: modelData.primary ? Colors.accent
                                     : ((actionMa.containsMouse || actionTile.focused) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                                border.color: actionTile.focused ? Colors.accentInk
                                            : (modelData.primary ? Colors.accent : Colors.border)
                                border.width: actionTile.focused ? 2 : 1

                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: modelData.label || ""
                                    color: modelData.primary ? Colors.accentFg : Colors.text
                                    font.family: Fonts.family
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: actionMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.exec) modelData.exec();
                                        Overlays.close("infobox");
                                    }
                                }
                            }
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
