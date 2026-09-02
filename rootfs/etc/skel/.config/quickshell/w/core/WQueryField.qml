// W Linux — shared query field: the borderless, oversized text box behind every modal
// palette's search (Launcher/Clipboard/Assistant). Sits inside an already-bordered
// card, so unlike WTextBox it intentionally has no border of its own. Purely the
// visual shell + text binding — key handling (list navigation, Escape-to-close,
// Enter-to-act) differs per caller, so callers keep wiring `Keys.on*` and
// `forceActiveFocus()` on `input` exactly as before extraction; this component only
// dedupes the look. Optional leading `glyph` covers Assistant's brand robot icon;
// Launcher/Clipboard simply leave it unset.
import QtQuick
import QtQuick.Controls
import qs.core

Rectangle {
    id: root

    property alias text: field.text
    property alias input: field
    property string placeholder: ""
    property string glyph: ""   // optional leading glyph (e.g. Assistant's robot icon)

    height: 48
    radius: Geometry.radiusSm
    color: Colors.inputBg

    Row {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 10

        Text {
            visible: root.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: Colors.accentInk
            font.family: Fonts.family
            font.pixelSize: 22
        }

        TextField {
            id: field
            width: root.glyph.length > 0 ? parent.width - parent.spacing - 22 : parent.width
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            background: null
            color: Colors.text
            placeholderText: root.placeholder
            placeholderTextColor: Colors.muted
            font.family: Fonts.family
            font.pixelSize: 18
            selectionColor: Colors.accent
            selectedTextColor: Colors.accentFg
        }
    }
}
