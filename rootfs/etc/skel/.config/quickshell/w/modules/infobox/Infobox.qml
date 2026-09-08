// W Linux — generic "infobox" overlay: a title + Markdown body + optional action
// buttons, in the same modal-center card style as the launcher/assistant/Hub. Not
// tied to any one feature: callers drive it entirely through content set via
// Overlays.openInfobox({ title, bodyMarkdown, actions }) — e.g. the assistant's
// readiness gate uses it today to explain an incomplete AI config (see
// modules/assistant/Assistant.qml); a future help/skill viewer can reuse it as-is
// by handing it a loaded .md file's text as bodyMarkdown. Body rendering uses
// QtQuick's built-in Text.MarkdownText (headings/emphasis/lists/code/links/quotes —
// no extra dependency), scrollable so long content (e.g. a full SKILL.md) fits.
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
    readonly property bool shown: root.active && !Overlays.suspended
    readonly property var content: Overlays.infoboxContent || ({})

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
                height: root.docsTall
                    ? root.pinRef
                    : Math.min(col.implicitHeight + 24, root.maxBodyHeight + col.spacing * 2 + 24)
                radius: Geometry.radius
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: 1

                // Bespoke roving over content.actions (0..N buttons) — same pattern as
                // the Auth GUI's dialog buttons, just a flat Row instead of a column.
                readonly property var actionsList: root.content.actions || []
                property int focusIndex: 0
                onActionsListChanged: card.focusIndex = Math.max(0, Math.min(card.focusIndex, card.actionsList.length - 1))
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
                    anchors.margins: 12
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

                    Flickable {
                        id: bodyFlick
                        width: parent.width
                        height: root.docsTall
                            ? card.height - 24
                              - headerRow.height
                              - ((root.content.actions || []).length > 0
                                 ? actionsRow.height + col.spacing : 0)
                              - col.spacing
                            : Math.min(bodyText.implicitHeight, root.maxBodyHeight)
                        visible: bodyText.text.length > 0
                        anchors.rightMargin: -12
                        clip: true
                        contentHeight: bodyText.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: WScrollBar {}

                        Text {
                            id: bodyText
                            width: bodyFlick.width - 12
                            textFormat: Text.MarkdownText
                            text: root.content.bodyMarkdown || ""
                            color: Colors.text
                            linkColor: Colors.accentInk
                            font.family: Fonts.family
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            // A page/link switch replaces the body in place — always
                            // land the reader at the top of what they opened. The
                            // paddings give the in-scroll content air at both ends.
                            topPadding: 6
                            bottomPadding: 10
                            // Pointer over links only: HoverHandler rides the already-
                            // hovered text and hoveredLink flips per position, so the
                            // card's plain text keeps the arrow. (Item.hoverEnabled is
                            // not exposed here — the handler carries the hover itself.)
                            HoverHandler {
                                cursorShape: parent.hoveredLink.length > 0
                                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                            onTextChanged: bodyFlick.contentY = 0
                            onLinkActivated: (link) => {
                                if (root.content.onLink) root.content.onLink(link);
                                else Qt.openUrlExternally(link);
                            }
                        }
                    }

                    Row {
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
