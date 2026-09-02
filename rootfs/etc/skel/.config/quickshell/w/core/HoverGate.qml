// W Linux — cursor-idle hover gate for the modal popups.
// Mounted as the LAST child of a popup's full-screen `content` root, one line per
// popup. While the compositor has hidden the cursor (Overlays.cursorIdle — the
// mirror of `cursor:inactive_timeout`, see Overlays), it takes hover away from
// every control in the popup, so a keyboard-navigated menu shows exactly ONE
// highlight instead of two: the roving focus, plus whatever the invisible pointer
// was resting on.
//
// Why a mask and not `&& !Overlays.cursorIdle` on each hover binding: there are
// ~50 `containsMouse` reads across 25 files in these popups. The mask clears all
// of them at once and leaves every existing binding untouched.
//
// Three Qt 6 behaviours this is built on (all measured on 6.11, not assumed):
//   • A full-screen hoverEnabled MouseArea on top DOES take hover from everything
//     below it, and showing/hiding it RE-DELIVERS hover — so the highlights clear
//     and come back with no pointer motion needed. That is the whole mechanism.
//   • A HoverHandler on a topmost SIBLING blocks hover below it (`blocking: false`
//     does not help), while one on the common ANCESTOR blocks nothing and still
//     receives every move — including the moves the mask is swallowing. Hence the
//     reparent below: it is what lets the gate see the motion that dismisses it.
//   • `HoverHandler.blocking: true` does NOT clear a child MouseArea's
//     containsMouse, so it cannot stand in for the mask.
import QtQuick
import qs.core

Item {
    id: gate

    // Motion source — attached to the item this gate is mounted in, never to `gate`
    // itself (see the sibling-vs-ancestor note above). Any real pointer motion is
    // also what un-hides the cursor, so the two stay in step.
    //
    // ⚠️ pointChanged is NOT the same thing as "the pointer moved": mapping the popup
    // under a still cursor makes the compositor send wl_pointer.enter, and raising or
    // dropping the mask re-delivers hover — each arrives here carrying a position and
    // would otherwise dismiss the gate the instant it armed (measured: the highlight
    // survived the whole open). So the first sample after each arming is only
    // RECORDED, and a wake needs a genuine change of position — the same
    // `lastPointer` guard the launcher's list uses against the same phantom.
    property var lastPointer: null
    HoverHandler {
        id: motion
        parent: gate.parent
        onPointChanged: {
            const p = motion.point.scenePosition;
            if (gate.lastPointer === null) { gate.lastPointer = p; return; }
            if (Math.abs(p.x - gate.lastPointer.x) + Math.abs(p.y - gate.lastPointer.y) < 1)
                return;
            gate.lastPointer = p;
            Overlays.cursorWake();
        }
    }
    // Re-arm the guard every time the cursor goes idle: that is exactly when we start
    // waiting for the next genuine movement, and the mask going up is itself one of
    // the phantom samples above.
    readonly property bool armed: Overlays.cursorIdle
    onArmedChanged: if (gate.armed) gate.lastPointer = null;

    // The mask: a bare Item whose HoverHandler is enough to take hover from
    // everything below (a topmost sibling carrying one blocks the subtree under it —
    // the very behaviour the motion handler above had to be reparented to escape).
    //
    // It is deliberately NOT a MouseArea, even though one would block hover just as
    // well: a MouseArea imposes a cursor wherever it is enabled — the default arrow
    // if none is set (same trap that made the bar's zone overlay mask its blocks'
    // cursors, see blocks/Zone.qml) — so the pointer flashed arrow→hand→arrow across
    // the mask's own edges. Handlers set a cursor only when asked to, so the control
    // underneath keeps its shape for the whole cycle.
    //
    // PointHandler is passive: it never grabs, so a blind click still reaches that
    // control (measured) while telling us the pointer is in use — Qt marks the
    // pressed control hovered, which the wake makes correct again by lifting the mask.
    Item {
        anchors.fill: parent
        visible: Overlays.cursorIdle
        HoverHandler {}
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: if (active) Overlays.cursorWake()
        }
    }
}
