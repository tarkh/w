// W Linux — shared bordered text-input box.
// The visual unit behind every Hub settings-field: a themed, bordered Rectangle
// wrapping a borderless TextField (as opposed to WQueryField's borderless search box —
// that one already sits inside an already-bordered card and intentionally has no
// border of its own). Used bare (fields with no paired button, e.g. the new-profile
// name prompt) and as the input half of WSettingsField/WSecretField. Border turns
// danger-red once the field is non-empty and `valid` is false — mirrors the Hostname/
// Idle-timeout fields this replaces. Height matches WButton/SelectRow's dropdown button
// (30px) so a box+button row sits at the same scale as the dropdowns around it.
import QtQuick
import QtQuick.Controls
import qs.core

Rectangle {
    id: root

    property alias text: field.text
    property alias input: field
    property string placeholder: ""
    property bool password: false
    property bool numeric: false
    property bool valid: true
    property int borderWidth: Geometry.border

    signal accepted()

    implicitHeight: 30
    radius: Geometry.radiusSm
    color: Colors.inputBg
    // Real Qt keyboard focus on the wrapped TextField — no separate `focused` prop
    // needed (unlike Tile/SelectRow/HubRow/WButton/WPill, this is an actual editable
    // control, so entering it via Tab/Enter really does give it activeFocus).
    border.width: field.activeFocus ? 2 : root.borderWidth
    border.color: (field.text.length > 0 && !root.valid) ? Colors.dangerBorder
                  : (field.activeFocus ? Colors.accentInk : Colors.border)
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    opacity: root.enabled ? 1 : 0.5

    TextField {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 10; anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: root.numeric ? TextInput.AlignHCenter : TextInput.AlignLeft
        background: null
        color: Colors.text
        enabled: root.enabled
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        inputMethodHints: root.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
        placeholderText: root.placeholder
        placeholderTextColor: Colors.muted
        font.family: Fonts.family; font.pixelSize: 14
        selectionColor: Colors.accent; selectedTextColor: Colors.accentFg
        onAccepted: root.accepted()
    }
}
