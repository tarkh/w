// W Linux — Brightness Control popup.
// A top-center card mirroring the Volume Control popup's footprint (same anchor, width
// and dismiss pattern), holding two independently-gated sliders: screen backlight and
// keyboard backlight, each under its own subtitle (mirrors Volume Control's "Output
// device"/"Input device" groups). The Hub's "Brightness" tile and the bar's
// brightness/keyboard-backlight blocks all open it (dispatch global
// quickshell:brightnesscontrol) so the Hub never carries its own inline slider —
// brightness gets the same "tile → popup" treatment as sound. Backed by the shared
// Backlight/KbdBacklight services (brightnessctl+sysfs / w-kbdlight+sysfs); each group
// is visible only when its hardware is present, and the empty-state line shows only
// when neither is. Colors/motion/fonts from the shared singletons.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.notifications
import qs.modules.shading

Scope {
    id: root

    readonly property bool active: Overlays.current === "brightnesscontrol"
    readonly property int cardW: 340

    GlobalShortcut {
        appid: "quickshell"
        name: "brightnesscontrol"
        onPressed: Overlays.toggle("brightnesscontrol")
    }

    PanelWindow {
        id: win
        visible: root.active || card.opacity > 0.01

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:brightnesscontrol"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive
                                                 : WlrKeyboardFocus.None

        // Reset the roving cursor and re-probe the active hotkeys profile's menu_*
        // chords on open — this popup isn't opened through the Hub, so nothing else
        // calls HubNavKeys.refresh() on its behalf (see Hub.qml's onActiveChanged).
        onVisibleChanged: if (visible) {
            card.focusIndex = 0;
            HubNavKeys.refresh();
            card.forceActiveFocus();
        }

        // Transparent backdrop: a click anywhere outside the card dismisses.
        MouseArea { anchors.fill: parent; onClicked: Overlays.close("brightnesscontrol") }

        Rectangle {
            id: card
            anchors {
                top: parent.top; horizontalCenter: parent.horizontalCenter
                topMargin: BarConfig.contentTop + NotifConfig.osdMarginTopOffset
            }
            width: root.cardW
            implicitHeight: col.implicitHeight + 24
            radius: Geometry.radius
            color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
            border.color: Colors.border
            border.width: Geometry.border
            clip: true

            focus: true
            Keys.onEscapePressed: Overlays.close("brightnesscontrol")

            // ── Keyboard roving-focus (flat list, top→bottom) ───────────────────────
            // Mirrors VolumeControl's bespoke roving (see its comment for the full
            // rationale) — much shorter here: at most two rows (display/keyboard
            // sliders), each independently gated by its own hardware availability, so
            // the roving list itself can shrink to 0/1/2 entries at runtime.
            readonly property bool dispOn: Backlight.available
            readonly property bool kbdOn: KbdBacklight.available
            readonly property int focusCount: (card.dispOn ? 1 : 0) + (card.kbdOn ? 1 : 0)
            readonly property int dispIndex: card.dispOn ? 0 : -1
            readonly property int kbdIndex: card.kbdOn ? (card.dispOn ? 1 : 0) : -1
            property int focusIndex: 0
            onFocusCountChanged: card.focusIndex = Math.max(0, Math.min(card.focusIndex, card.focusCount - 1))

            function focusRow(i) { card.focusIndex = Math.max(0, Math.min(i, card.focusCount - 1)); }

            // Left/Right step the focused slider; this panel has no horizontal roving
            // (Up/Down only), so there is nothing for Left/Right to collide with.
            function stepFocused(delta) {
                if (card.focusIndex === card.dispIndex)
                    Backlight.set(Math.max(0, Math.min(1, Backlight.value + delta)));
                else if (card.focusIndex === card.kbdIndex)
                    KbdBacklight.set(Math.max(0, Math.min(1, KbdBacklight.value + delta)));
            }

            Keys.onPressed: (e) => {
                if (card.focusCount === 0) return;
                switch (e.key) {
                case HubNavKeys.down: card.focusRow(card.focusIndex + 1); e.accepted = true; return;
                case HubNavKeys.up:   card.focusRow(card.focusIndex - 1); e.accepted = true; return;
                case HubNavKeys.left:  card.stepFocused(-0.05); e.accepted = true; return;
                case HubNavKeys.right: card.stepFocused(0.05); e.accepted = true; return;
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
            transformOrigin: Item.Top
            scale: root.active ? 1 : 0.94
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.base
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 12
                spacing: 12

                Text {
                    text: Strings.t("brightness.title")
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    leftPadding: 2
                }

                // Empty state only when neither the screen nor the keyboard has a
                // detected backlight.
                Text {
                    visible: !Backlight.available && !KbdBacklight.available
                    text: Strings.t("brightness.none")
                    color: Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 13
                    leftPadding: 2
                }

                // ── Screen brightness ─────────────────────────────────────
                Column {
                    id: displayGroup
                    visible: Backlight.available
                    width: parent.width
                    spacing: 4

                    Text {
                        text: Strings.t("brightness.display")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        leftPadding: 2
                    }

                    Item {
                        id: sliderRow
                        width: parent.width
                        height: 28

                        Rectangle {
                            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                            radius: Geometry.radiusSm
                            visible: card.focusIndex === card.dispIndex
                            color: Colors.hover
                        }

                        Text {
                            id: briLabel
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: Math.round(Backlight.value * 100) + "%"
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 12
                            font.features: ({ "tnum": 1 })
                            width: 34
                            horizontalAlignment: Text.AlignRight
                        }

                        ChromeIcon {
                            id: briIcon
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            size: 18
                            glyph: Glyphs.brightness
                            tint: Colors.muted
                        }

                        // Shared slider (core/WSlider.qml) — was an inline copy, identical
                        // to the keyboard one below and to VolumeControl's. Stateless:
                        // `value` stays bound to the live sensor, the write happens in
                        // onMoved, and ←/→ remain card.stepFocused's business.
                        WSlider {
                            anchors {
                                left: briIcon.right; leftMargin: 10
                                right: briLabel.left; rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            height: 20
                            value: Backlight.value
                            onMoved: (v) => Backlight.set(v)
                        }
                    }
                }

                // ── Divider (only when both groups are shown) ────────────
                Rectangle {
                    visible: Backlight.available && KbdBacklight.available
                    width: parent.width; height: 1
                    color: Colors.border; opacity: 0.5
                }

                // ── Keyboard backlight ────────────────────────────────────
                Column {
                    id: kbdGroup
                    visible: KbdBacklight.available
                    width: parent.width
                    spacing: 4

                    Text {
                        text: Strings.t("brightness.keyboard")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        leftPadding: 2
                    }

                    Item {
                        id: kbdSliderRow
                        width: parent.width
                        height: 28

                        Rectangle {
                            anchors { fill: parent; leftMargin: -8; rightMargin: -8; topMargin: -4; bottomMargin: -4 }
                            radius: Geometry.radiusSm
                            visible: card.focusIndex === card.kbdIndex
                            color: Colors.hover
                        }

                        Text {
                            id: kbdLabel
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: Math.round(KbdBacklight.value * 100) + "%"
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 12
                            font.features: ({ "tnum": 1 })
                            width: 34
                            horizontalAlignment: Text.AlignRight
                        }

                        ChromeIcon {
                            id: kbdIcon
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            size: 18
                            glyph: Glyphs.kbdBacklight
                            tint: Colors.muted
                        }

                        WSlider {
                            anchors {
                                left: kbdIcon.right; leftMargin: 10
                                right: kbdLabel.left; rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            height: 20
                            value: KbdBacklight.value
                            onMoved: (v) => KbdBacklight.set(v)
                        }
                    }
                }
            }
        }
    }
}
