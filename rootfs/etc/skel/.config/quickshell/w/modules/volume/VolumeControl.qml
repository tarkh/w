// W Linux — Volume Control popup.
// Top-right anchored card: default sink volume + mute, output device selector,
// mic mute, and an "Open Mixer" button running VolumeConfig.mixerCommand (the
// wiremix TUI by default) for advanced config. Toggled via a
// Hyprland global shortcut (Super+A). Native PipeWire via Quickshell.Services.Pipewire —
// no subprocess needed. All timing and colors follow the Motion/Colors/Fonts singletons.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.notifications
import qs.modules.shading

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any
    // other popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "volumecontrol"

    readonly property int cardW: 340
    readonly property int rowH: 44

    property list<var> sinks: []
    property list<var> sources: []

    GlobalShortcut {
        appid: "quickshell"
        name: "volumecontrol"
        onPressed: Overlays.toggle("volumecontrol")
    }

    // Keeps PipeWire objects subscribed for reactive property notifications.
    // The default sink/source are tracked explicitly: without an active binding
    // their `.ready` stays false and writes to `.audio.volume`/`.muted` silently
    // no-op (breaking the slider and mute buttons).
    PwObjectTracker {
        objects: [...root.sinks, ...root.sources,
                  Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { root.updateNodes() }
    }

    Component.onCompleted: root.updateNodes()

    function updateNodes() {
        const ns = [], nr = [];
        for (const node of Pipewire.nodes.values) {
            if (!node.isStream) {
                if (node.isSink) ns.push(node);
                else if (node.audio) nr.push(node);
            }
        }
        root.sinks = ns;
        root.sources = nr;
    }

    PanelWindow {
        id: win
        visible: root.active || card.opacity > 0.01

        // Full-screen transparent overlay (no tint, no blur): the backdrop catches
        // clicks outside the card to dismiss — the launcher's proven grab-free
        // pattern. A small corner window + HyprlandFocusGrab proved unreliable once
        // the surface also held exclusive keyboard focus (the two grabs conflict).
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:volumecontrol"
        WlrLayershell.layer: WlrLayer.Overlay
        // Take keyboard focus while open so Escape closes the popup; release it
        // when hidden so the shell never holds the keyboard in the background.
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive
                                                 : WlrKeyboardFocus.None

        // Focus the card on open so Keys.onEscapePressed fires immediately. Reset the
        // roving cursor to the slider and re-probe the active hotkeys profile's menu_*
        // chords — this popup isn't opened through the Hub, so nothing else calls
        // HubNavKeys.refresh() on its behalf (see Hub.qml's onActiveChanged).
        onVisibleChanged: if (visible) {
            card.focusIndex = 0;
            HubNavKeys.refresh();
            card.forceActiveFocus();
        }

        // Transparent backdrop: a click anywhere outside the card dismisses.
        MouseArea { anchors.fill: parent; onClicked: Overlays.close("volumecontrol") }

        Rectangle {
            id: card
            // Top-CENTER, sharing the OSD's footprint (top edge aligns with Osd's
            // NotifConfig.marginTop + 28 = 36). Frees the top-right corner for the
            // notification stack / future notification center.
            anchors {
                top: parent.top; horizontalCenter: parent.horizontalCenter
                // Flush with the open windows' top edge; shares the OSD's offset so the
                // two center popups stay aligned (see NotifConfig.osdMarginTopOffset).
                topMargin: BarConfig.contentTop + NotifConfig.osdMarginTopOffset
            }
            width: root.cardW
            implicitHeight: col.implicitHeight + 24  // 12px top + 12px bottom padding
            radius: Geometry.radius
            // Surface translucency from the effects axis (bg only; sliders/labels are
            // separate items and stay opaque). No own config — bound straight to Effects.
            color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
            border.color: Colors.border
            border.width: Geometry.border
            clip: true

            // Escape closes the popup (keyboard focus is granted on open).
            focus: true
            Keys.onEscapePressed: Overlays.close("volumecontrol")

            // ── Keyboard roving-focus (flat list, top→bottom) ───────────────────────
            // Bespoke roving (not the Hub's buildContent()/focusedKey machinery — this
            // popup isn't a Hub panel, and its content is small and fixed in shape) over
            // a linear focusIndex-by-position (InputPanel's pattern, not a fixed id array
            // like NetworkPanel/PowerMenu): the sink/source row counts vary at runtime
            // (1-4 each, whatever PipeWire enumerates), so there is no fixed set of ids to
            // list. Order top-to-bottom: volume slider, sink rows, output mute, source
            // rows, input mute, Open Mixer.
            readonly property int sinkCount: Math.min(root.sinks.length, 4)
            readonly property int srcCount: Math.min(root.sources.length, 4)
            readonly property int focusCount: 4 + card.sinkCount + card.srcCount
            property int focusIndex: 0
            onFocusCountChanged: card.focusIndex = Math.max(0, Math.min(card.focusIndex, card.focusCount - 1))

            function focusRow(i) { card.focusIndex = Math.max(0, Math.min(i, card.focusCount - 1)); }

            // Left/Right step the focused slider; harmless everywhere else. This panel's
            // roving axis is vertical only (Up/Down) — Left/Right is never claimed by
            // row-to-row navigation, so there is no collision to guard against.
            function stepVolume(delta) {
                if (Pipewire.defaultAudioSink?.ready && Pipewire.defaultAudioSink?.audio)
                    Pipewire.defaultAudioSink.audio.volume =
                        Math.max(0, Math.min(1, Pipewire.defaultAudioSink.audio.volume + delta));
            }

            function activateFocused() {
                const i = card.focusIndex;
                if (i === 0) return;   // slider: nothing to "confirm", Left/Right already drives it
                if (i <= card.sinkCount) {
                    const node = root.sinks[i - 1];
                    if (node) Pipewire.preferredDefaultAudioSink = node;
                    return;
                }
                if (i === card.sinkCount + 1) {
                    if (Pipewire.defaultAudioSink?.ready && Pipewire.defaultAudioSink?.audio)
                        Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted;
                    return;
                }
                const srcBase = card.sinkCount + 2;
                if (i < srcBase + card.srcCount) {
                    const node = root.sources[i - srcBase];
                    if (node) Pipewire.preferredDefaultAudioSource = node;
                    return;
                }
                if (i === srcBase + card.srcCount) {
                    if (Pipewire.defaultAudioSource?.ready && Pipewire.defaultAudioSource?.audio)
                        Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted;
                    return;
                }
                Quickshell.execDetached(VolumeConfig.mixerCommand);
                Overlays.close("volumecontrol");
            }

            Keys.onPressed: (e) => {
                switch (e.key) {
                case HubNavKeys.down: card.focusRow(card.focusIndex + 1); e.accepted = true; return;
                case HubNavKeys.up:   card.focusRow(card.focusIndex - 1); e.accepted = true; return;
                case HubNavKeys.left:
                case HubNavKeys.right:
                    // Only the slider (index 0) owns Left/Right — elsewhere in the list
                    // (a device row, a mute button, Open Mixer) it does nothing, so it
                    // can't silently retune the sink out from under whatever's focused.
                    if (card.focusIndex === 0)
                        card.stepVolume(e.key === HubNavKeys.right ? 0.05 : -0.05);
                    e.accepted = true;
                    return;
                case HubNavKeys.confirm:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    card.activateFocused();
                    e.accepted = true;
                    return;
                }
            }

            opacity: root.active ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Scale-in from the top edge (matches the top-center anchor point).
            transformOrigin: Item.Top
            scale: root.active ? 1 : 0.94
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.base
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Swallow clicks so the window doesn't accidentally pass through.
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 12
                spacing: 12

                // ── Title ────────────────────────────────────────────────
                Text {
                    text: Strings.t("volume.title")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    leftPadding: 2
                }

                // ── Volume slider ────────────────────────────────────────
                Item {
                    id: sliderRow
                    width: parent.width
                    height: 28

                    Rectangle {
                        anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                        radius: Geometry.radiusSm
                        visible: card.focusIndex === 0
                        color: Colors.hover
                    }

                    Text {
                        id: volLabel
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: Math.round((Pipewire.defaultAudioSink?.audio?.volume ?? 0) * 100) + "%"
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 12
                        width: 32
                        horizontalAlignment: Text.AlignRight
                    }

                    // The shared slider (core/WSlider.qml) — this markup used to be an
                    // inline copy, identical to the two in BrightnessControl. It is
                    // stateless: `value` stays a live binding to the sink and the write
                    // happens here, in onMoved. Keyboard stepping is NOT delegated to it:
                    // card.stepVolume already owns ←/→ for every row of this popup.
                    WSlider {
                        anchors {
                            left: parent.left; right: volLabel.left
                            rightMargin: 8; verticalCenter: parent.verticalCenter
                        }
                        height: 20
                        value: Pipewire.defaultAudioSink?.audio?.volume ?? 0
                        onMoved: (v) => {
                            if (Pipewire.defaultAudioSink?.ready && Pipewire.defaultAudioSink?.audio)
                                Pipewire.defaultAudioSink.audio.volume = v;
                        }
                    }
                }

                // ── Divider ──────────────────────────────────────────────
                Rectangle {
                    width: parent.width; height: 1
                    color: Colors.border; opacity: 0.5
                }

                // ── Output device: selector + mute (tight group) ─────────
                Column {
                    width: parent.width
                    spacing: 4

                Text {
                    text: Strings.t("volume.outputDevice")
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    leftPadding: 2
                }

                Row {
                    width: parent.width
                    spacing: 6

                    // Selector list: current device accent-highlighted, click to switch.
                    Column {
                        id: sinkList
                        width: parent.width - 46   // 40px mute button + 6px gap
                        spacing: 4

                        Repeater {
                            model: root.sinks.slice(0, 4)

                            delegate: Item {
                                id: sinkRow
                                required property var modelData
                                required property int index

                                readonly property bool isCurrent: modelData === Pipewire.defaultAudioSink
                                readonly property bool focused: card.focusIndex === (1 + sinkRow.index)

                                width: sinkList.width
                                height: 40

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Geometry.radiusSm
                                    color: isCurrent ? Colors.accent
                                           : ((devMa.containsMouse || sinkRow.focused) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                                    border.width: sinkRow.focused ? 2 : 0
                                    border.color: isCurrent ? Colors.accentFg : Colors.accentInk
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                Row {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    spacing: 8

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6; height: 6; radius: 3
                                        color: isCurrent ? Colors.accentFg : "transparent"
                                        border.color: isCurrent ? "transparent" : Colors.border
                                        border.width: 1
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.description || modelData.name || "Unknown"
                                        color: isCurrent ? Colors.accentFg : Colors.text
                                        font.family: Fonts.family
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                        width: parent.width - 22
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    }
                                }

                                MouseArea {
                                    id: devMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Pipewire.preferredDefaultAudioSink = modelData
                                }
                            }
                        }
                    }

                    // Mute toggle for the default sink: square, one-row tall, accent when muted.
                    Rectangle {
                        id: sinkMuteBtn
                        width: 40; height: 40
                        radius: Geometry.radiusSm
                        readonly property bool muted: Pipewire.defaultAudioSink?.audio?.muted ?? false
                        readonly property bool focused: card.focusIndex === card.sinkCount + 1
                        color: muted ? Colors.accent
                               : ((sinkMuteMa.containsMouse || focused) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                        border.color: focused ? (muted ? Colors.accentFg : Colors.accentInk)
                                      : (muted ? "transparent" : Colors.border)
                        border.width: focused ? 2 : 1
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        ChromeIcon {
                            anchors.centerIn: parent
                            size: 16
                            glyph: Glyphs.volume(1, Pipewire.defaultAudioSink?.audio?.muted ?? false)
                            tint: Pipewire.defaultAudioSink?.audio?.muted ? Colors.accentFg : Colors.muted
                        }

                        MouseArea {
                            id: sinkMuteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Pipewire.defaultAudioSink?.ready && Pipewire.defaultAudioSink?.audio)
                                    Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted;
                            }
                        }
                    }
                }
                }   // end output device group

                // ── Divider ──────────────────────────────────────────────
                Rectangle {
                    width: parent.width; height: 1
                    color: Colors.border; opacity: 0.5
                }

                // ── Input device: selector + mute (tight group) ──────────
                Column {
                    width: parent.width
                    spacing: 4

                Text {
                    text: Strings.t("volume.inputDevice")
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    leftPadding: 2
                }

                Row {
                    width: parent.width
                    spacing: 6

                    // Selector list: current device accent-highlighted, click to switch.
                    Column {
                        id: srcList
                        width: parent.width - 46   // 40px mute button + 6px gap
                        spacing: 4

                        Repeater {
                            model: root.sources.slice(0, 4)

                            delegate: Item {
                                id: srcRow
                                required property var modelData
                                required property int index

                                readonly property bool isCurrent: modelData === Pipewire.defaultAudioSource
                                readonly property bool focused: card.focusIndex === (card.sinkCount + 2 + srcRow.index)

                                width: srcList.width
                                height: 40

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Geometry.radiusSm
                                    color: isCurrent ? Colors.accent
                                           : ((srcDevMa.containsMouse || srcRow.focused) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                                    border.width: srcRow.focused ? 2 : 0
                                    border.color: isCurrent ? Colors.accentFg : Colors.accentInk
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                Row {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    spacing: 8

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6; height: 6; radius: 3
                                        color: isCurrent ? Colors.accentFg : "transparent"
                                        border.color: isCurrent ? "transparent" : Colors.border
                                        border.width: 1
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.description || modelData.name || "Unknown"
                                        color: isCurrent ? Colors.accentFg : Colors.text
                                        font.family: Fonts.family
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                        width: parent.width - 22
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    }
                                }

                                MouseArea {
                                    id: srcDevMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Pipewire.preferredDefaultAudioSource = modelData
                                }
                            }
                        }
                    }

                    // Mute toggle for the default source: square, one-row tall, accent when muted.
                    Rectangle {
                        id: srcMuteBtn
                        width: 40; height: 40
                        radius: Geometry.radiusSm
                        readonly property bool muted: Pipewire.defaultAudioSource?.audio?.muted ?? false
                        readonly property bool focused: card.focusIndex === card.sinkCount + 2 + card.srcCount
                        color: muted ? Colors.accent
                               : ((srcMuteMa.containsMouse || focused) ? Colors.hover : Colors.alpha(Colors.hover, 0))
                        border.color: focused ? (muted ? Colors.accentFg : Colors.accentInk)
                                      : (muted ? "transparent" : Colors.border)
                        border.width: focused ? 2 : 1
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        ChromeIcon {
                            anchors.centerIn: parent
                            size: 16
                            glyph: Glyphs.mic(Pipewire.defaultAudioSource?.audio?.muted ?? false)
                            tint: Pipewire.defaultAudioSource?.audio?.muted ? Colors.accentFg : Colors.muted
                        }

                        MouseArea {
                            id: srcMuteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Pipewire.defaultAudioSource?.ready && Pipewire.defaultAudioSource?.audio)
                                    Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted;
                            }
                        }
                    }
                }
                }   // end input device group

                // ── Divider ──────────────────────────────────────────────
                Rectangle {
                    width: parent.width; height: 1
                    color: Colors.border; opacity: 0.5
                }

                // ── Open Mixer ───────────────────────────────────────────
                Rectangle {
                    id: mixerBtn
                    width: parent.width
                    height: 36
                    radius: Geometry.radiusSm
                    readonly property bool focused: card.focusIndex === card.focusCount - 1
                    color: (mixerMa.containsMouse || focused) ? Colors.hover : Colors.alpha(Colors.hover, 0)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    border.color: focused ? Colors.accentInk : Colors.border
                    border.width: focused ? 2 : 1

                    Text {
                        anchors.centerIn: parent
                        text: Strings.t("volume.openMixer")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: mixerMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(VolumeConfig.mixerCommand);
                            Overlays.close("volumecontrol");
                        }
                    }
                }
            }
        }
    }
}
