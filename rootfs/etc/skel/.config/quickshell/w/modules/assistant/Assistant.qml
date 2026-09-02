// W Linux — "Ask W" assistant palette.
// A one-line prompt box over the shared tinted, compositor-blurred backdrop — the
// Quickshell entry point to W's OS assistant. Layer-shell overlay with exclusive
// keyboard focus (grabs input in Hyprland); toggled by the `assistant` hotkey
// (Super+W) and the bar's robot button. It does NOT render a chat: on Enter it hands
// the question to `w-ai ask` in a terminal, where the real session lives (streaming,
// tool approvals, polkit prompts). An empty prompt just opens a bare session. So the
// palette is a thin, predictable input layer — one action, one destination. See
// ai-integration.md §6 (host-approval ≠ polkit) and quickshell-assistant.md.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.core

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any
    // other popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "assistant"

    // Visually shown: open AND not suspended (stepped aside for a higher-priority
    // modal, e.g. the auth prompt). Same contract the launcher/Hub use.
    readonly property bool shown: root.active && !Overlays.suspended

    // Card geometry. Width is the shared Overlays.cardWidth so the input field lines
    // up with launcher/clipboard/Hub for the group crossfade. The card is compact
    // (single input + hint), but its TOP pins to the same y as the launcher's card
    // (ref 480) so the fields sit on the same line across the modal-center group.
    readonly property int cardW: Overlays.cardWidth
    readonly property int pinRef: 480

    // Toggle from Hyprland:  bind = SUPER, W, global, quickshell:assistant. Both entry
    // points (this hotkey and the bar's robot button) dispatch the same Hyprland
    // global, so this is the single choke point for the readiness gate below.
    GlobalShortcut {
        appid: "quickshell"
        name: "assistant"
        onPressed: root.trigger()
    }

    // Closing (already open) is instant — no need to re-check. Opening fresh first
    // asks `w-ai ready` (goose/local: provider+model+key complete?) so a broken AI
    // config shows a clear infobox instead of a terminal popping open with goose's
    // own opaque error. See ai-integration.md §6 / w-ai's `ready` command.
    function trigger() {
        if (root.active || (Overlays.current === "infobox" && Overlays.infoboxContent && Overlays.infoboxContent.id === "ai-not-ready")) {
            Overlays.close(Overlays.current);
            return;
        }
        readyCheck.running = true;
    }

    Process {
        id: readyCheck
        command: ["w-ai", "ready"]
        onExited: (code) => {
            if (code === 0) {
                Overlays.toggle("assistant");
            } else {
                Overlays.openInfobox({
                    id: "ai-not-ready",
                    title: Strings.t("ai.notReady.title"),
                    bodyMarkdown: Strings.t("ai.notReady.body"),
                    actions: [{
                        label: Strings.t("ai.notReady.action"),
                        primary: true,
                        exec: () => Overlays.open("hub", { route: "ai" }),
                    }],
                });
            }
        }
    }

    // Hand the prompt to the terminal and close. Term.exec builds `w-term -e …`; the
    // question is passed as one argv element (no shell), so spaces/quotes are safe.
    // Empty prompt → a bare `w-ai` session. All AI substance happens in that session.
    function submit(text) {
        const q = text.trim();
        Quickshell.execDetached(q.length > 0 ? Term.exec(["w-ai", "ask", q])
                                             : Term.exec(["w-ai"]));
        Overlays.close("assistant");
    }

    PanelWindow {
        id: win

        // Stay mapped while fading out, then unmap once invisible.
        visible: root.shown || content.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Layer-shell: overlay above everything, grab keyboard. The tint + blur come
        // from the shared Backdrop surface (assistant is in Overlays.blurGroup), so
        // this namespace is NOT blur_layer'd individually — the scrim carries it.
        WlrLayershell.namespace: "quickshell:assistant"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                promptField.input.forceActiveFocus();
            } else if (!root.active) {
                // Reset only on a REAL close (not a suspend) so a restored palette keeps
                // its text.
                promptField.text = "";
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
            // Backdrop surface, so this layer is input-only.
            MouseArea { anchors.fill: parent; onClicked: Overlays.close("assistant") }

            // Palette card. Top pinned to the launcher's line so the input field never
            // jumps during the group crossfade.
            Rectangle {
                id: card
                // Round to whole pixels — a fractional origin (odd screen widths) makes
                // the top/left border render subpixel-blurred ("thicker").
                x: Math.round((content.width - width) / 2)
                y: Math.round((content.height - root.pinRef) / 2)
                width: root.cardW
                height: col.implicitHeight + 24
                radius: Geometry.radius
                // Surface translucency from the effects axis (bg only; the input field
                // and glyph stay opaque). The scrim+blur backdrop frosts through.
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
                border.color: Colors.border
                border.width: AssistantConfig.border

                // Entrance: subtle scale-in from the top (keeps the input put).
                transformOrigin: Item.Top
                scale: root.shown ? 1 : 0.96
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.base
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.bezierCurve
                    }
                }

                // Swallow clicks so they don't reach the dismiss MouseArea.
                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 12
                    spacing: 10

                    // ── Prompt field (robot glyph + input) ────────────────────
                    WQueryField {
                        id: promptField
                        width: parent.width
                        placeholder: Strings.t("assistant.placeholder")
                        glyph: String.fromCodePoint(0xf06a9)   // nf-md-robot — the assistant's identity

                        // Mode B, minus the list: there is nothing to page through here,
                        // so only confirm/back resolve — but they resolve through the
                        // same resolver as every other W palette, so a profile that moves
                        // menu_back off Escape moves it here too (see core/HubNavKeys.qml).
                        input.Keys.onPressed: (e) => {
                            switch (HubNavKeys.fieldAction(e)) {
                            case "confirm": root.submit(promptField.text); e.accepted = true; return;
                            case "back":    Overlays.close("assistant"); e.accepted = true; return;
                            }
                        }
                    }

                    // ── Hint line ─────────────────────────────────────────────
                    Text {
                        width: parent.width
                        text: Strings.t("assistant.hints")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            // Topmost of all: no hover highlight while the cursor is hidden, so the
            // keyboard selection is the only mark on screen (see core/HoverGate).
            HoverGate { anchors.fill: parent }
        }
    }
}
