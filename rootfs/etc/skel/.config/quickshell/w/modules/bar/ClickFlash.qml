// W Linux bar — click-flash overlay.
// A transparent fill that pulses (fade in to an apex, then fade out) on a click,
// giving clear feedback on activation / menu-open. One shared primitive used by both
// single-unit block zones and multi-button block buttons: the host sets anchors +
// radius (so the flash matches the rounded element it sits on), this just owns the
// pulse. Sits BELOW the block's icons/text (declared first in the host) so the glyphs
// stay crisp.
//
// Colors resolve through BarConfig.col (a theme TOKEN name, live through Colors, or a
// literal #RRGGBB); the apex alpha is `opacity`. A mouse button with no configured
// color does not flash — pulse() is a no-op for it — so the whole effect is opt-in
// per config key (clickColorLeft / clickColorRight), per button.
import QtQuick
import qs.core

Rectangle {
    id: root

    // Set from a block's settings; undefined/"" = that button doesn't flash.
    property var  colorLeft:   undefined
    property var  colorRight:  undefined
    property real apexOpacity: 0.5
    property int  duration:    Motion.base

    color:   "transparent"
    opacity: 0

    // button: a Qt.MouseButton (LeftButton/RightButton/…). Picks the matching color;
    // bails out (no flash) when that button has no color configured.
    function pulse(button) {
        const c = (button === Qt.RightButton) ? root.colorRight : root.colorLeft;
        if (c === undefined || c === null || c === "") return;
        root.color = BarConfig.col(c, 1.0);   // opaque base; apex alpha comes from opacity
        anim.restart();
    }

    SequentialAnimation {
        id: anim
        NumberAnimation {
            target: root; property: "opacity"; from: 0; to: root.apexOpacity
            duration: Math.max(1, root.duration / 2); easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "opacity"; from: root.apexOpacity; to: 0
            duration: Math.max(1, root.duration / 2); easing.type: Easing.InCubic
        }
    }
}
