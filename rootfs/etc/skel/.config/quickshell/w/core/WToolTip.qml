// W Linux — themed tooltip.
//
// The attached `ToolTip.visible/text` form draws with the Controls Basic style: a
// square, off-palette box that reads as foreign next to every other W surface. This
// one takes the shape of what it is closest to in meaning — a dropdown (HubMenu):
// surface fill, border accent, the theme's small radius, theme font. Declare it
// inside the item it describes and bind `visible`:
//
//     MouseArea { id: ma; hoverEnabled: true
//         WToolTip { text: "…"; visible: ma.containsMouse } }
//
// Positioned under its parent and horizontally centred, like the attached form.
import QtQuick
import QtQuick.Controls
import qs.core

ToolTip {
    id: root

    delay: 300
    padding: 8
    margins: 6
    x: parent ? Math.round((parent.width - implicitWidth) / 2) : 0
    y: parent ? parent.height + 6 : 0

    contentItem: Text {
        text: root.text
        color: Colors.text
        font.family: Fonts.family
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }
    background: Rectangle {
        color: Colors.surface
        border.color: Colors.border
        border.width: Geometry.border
        radius: Geometry.radiusSm
    }
}
