// W Linux — shared "settings field": bordered box + accent Change button.
// Canonical shape for every free-text Hub setting that needs an explicit confirm step
// (Network → Hostname, Energy → Idle timeout, AI → Model/Ollama Host): the button stays
// disabled until the value both differs from `value` and passes `validator`, exactly
// like the hand-rolled Hostname/Idle-timeout fields this replaces. Two layouts in one
// component — `fixedWidth: 0` (default) stretches the box to fill the row minus the
// button (Hostname); `fixedWidth > 0` gives a narrow fixed box plus an optional
// trailing `suffix` label (Idle timeout's "мин").
import QtQuick
import qs.core

Row {
    id: root

    property string value: ""             // current/persisted value the field starts from
    property string placeholder: ""
    property bool numeric: false
    property int fixedWidth: 0             // 0 = fill the row (minus the button)
    property string suffix: ""             // optional trailing label, e.g. "мин"
    property var validator: (text) => true
    property int borderWidth: Geometry.border
    // Exposed so a panel's roving-nav can forceActiveFocus() straight into the field
    // (Enter on the row "opens" it) and wire Tab/Esc to hand focus back out.
    property alias input: box.input

    signal applied(string text)

    spacing: 8

    readonly property string trimmed: box.text.trim()
    readonly property bool dirty: root.trimmed.length > 0 && root.trimmed !== root.value
    readonly property bool valid: root.validator(root.trimmed)
    readonly property bool active: root.dirty && root.valid

    function commit() { if (root.active) root.applied(root.trimmed); }

    WTextBox {
        id: box
        anchors.verticalCenter: parent.verticalCenter
        width: root.fixedWidth > 0
               ? root.fixedWidth
               : root.width - btn.width - (suffixText.visible ? suffixText.implicitWidth + root.spacing : 0) - root.spacing
        text: root.value
        placeholder: root.placeholder
        numeric: root.numeric
        valid: root.valid
        borderWidth: root.borderWidth
        onAccepted: root.commit()
    }
    Text {
        id: suffixText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.suffix.length > 0
        text: root.suffix
        color: Colors.muted
        font.family: Fonts.family; font.pixelSize: 13
    }
    WButton {
        id: btn
        anchors.verticalCenter: parent.verticalCenter
        label: Strings.t("hub.change")
        enabled: root.active
        borderWidth: root.borderWidth
        onClicked: root.commit()
    }
}
