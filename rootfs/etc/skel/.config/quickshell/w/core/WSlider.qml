// W Linux — shared horizontal slider.
// One slider shape for the whole shell: the recessed track + accent fill + round
// handle that used to be copied byte-for-byte in VolumeControl and twice in
// BrightnessControl (display + keyboard backlight), and would have been copied again
// by the Hub's Input panel (pointer speed / scroll factor). Same extraction as
// HubDropdown: identical inline copies first, one component once a fourth site
// appeared.
//
// STATELESS by design: it never assigns to `value`. Both existing call sites bind
// `value` to a live source (Pipewire volume, Backlight.value) and a self-assignment
// would break that binding — so the component only reports where the user pointed
// (`moved`) and the owner writes the source. `committed` is the debounced/"let go"
// edge for owners whose write is expensive (a CLI round-trip in the Hub) rather than
// a property poke.
//
// Keyboard: `focused` is set by the OWNER (the panel that owns the roving index —
// the Hub-wide framework rule, see quickshell-hub.md), and the owner calls stepUp()/
// stepDown() from its own Left/Right handler. The focus channel here is the handle's
// accent ring, independent of the row-level focus wash the owner draws.
import QtQuick
import qs.core

Item {
    id: root

    property real from: 0
    property real to: 1
    // 0 = continuous. Anything else snaps both dragging and stepping to the grid.
    property real stepSize: 0
    property real value: 0
    // Roving-focus indicator, set by the owning panel (never by this component).
    property bool focused: false
    // ms of quiet after a keyboard step before `committed` fires; 0 = fire at once.
    // Dragging always commits on release, regardless of this.
    property int commitDelay: 0

    // Where the user pointed right now (drag or step) — continuous feedback.
    signal moved(real value)
    // The value is final: mouse released, or `commitDelay` elapsed after a step.
    signal committed(real value)

    implicitHeight: 20

    readonly property real span: root.to - root.from
    readonly property real position: root.span === 0 ? 0
        : Math.max(0, Math.min(1, (root.value - root.from) / root.span))

    function clampValue(v) {
        let x = Math.max(root.from, Math.min(root.to, v));
        if (root.stepSize > 0) {
            x = root.from + Math.round((x - root.from) / root.stepSize) * root.stepSize;
            // Re-clamp: rounding can land one step outside the range.
            x = Math.max(root.from, Math.min(root.to, x));
            // Kill float dust (0.30000000000000004) so labels and CLI args stay clean.
            x = Math.round(x * 1000) / 1000;
        }
        return x;
    }

    function step(dir) {
        const s = root.stepSize > 0 ? root.stepSize : root.span / 20;
        const v = root.clampValue(root.value + dir * s);
        if (v === root.value) return;
        root.moved(v);
        if (root.commitDelay > 0) commitTimer.restart();
        else root.committed(v);
    }
    function stepUp() { root.step(1); }
    function stepDown() { root.step(-1); }

    // Debounce for keyboard stepping: holding Right walks the value without firing a
    // CLI call per press.
    Timer {
        id: commitTimer
        interval: root.commitDelay
        onTriggered: root.committed(root.value)
    }

    // Unfilled headroom: dim recessed groove.
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 4; radius: 2
        color: Colors.inputBg
    }
    // Filled part, left of the handle.
    Rectangle {
        anchors { left: track.left; verticalCenter: track.verticalCenter }
        width: track.width * root.position
        height: track.height; radius: track.radius
        color: Colors.accent
    }
    Rectangle {
        x: track.width * root.position - width / 2
        anchors.verticalCenter: track.verticalCenter
        width: 14; height: 14; radius: 7
        color: Colors.surface
        // Accent ring while the roving cursor is on this row — a colour channel of
        // its own, so it stays readable over the row's focus wash.
        border.color: root.focused ? Colors.accentInk : Colors.border
        border.width: 2
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.SizeHorCursor
        function seek(mouse) {
            if (track.width <= 0) return;
            const v = root.clampValue(root.from + (mouse.x / track.width) * root.span);
            if (v !== root.value) root.moved(v);
        }
        onPressed: (m) => seek(m)
        onPositionChanged: (m) => { if (pressed) seek(m); }
        onReleased: root.committed(root.value)
    }
}
