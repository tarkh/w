// W Linux — shared "secret field": masked bordered box + Save/Remove button pair.
// Canonical shape for provider API keys — write-only, no "did it change" comparison
// (the stored secret never reads back into the box). Two call sites already share this
// exact shape (AI → profile's provider key, AI → Web search → Brave key), with more
// web-search providers coming, hence a named component rather than ad hoc duplication.
// Buttons are standard-size WButton, not the compact Pill used elsewhere in the AI panel.
import QtQuick
import qs.core

Row {
    id: root

    property string placeholder: ""
    property bool hasKey: false
    property bool busy: false
    property int borderWidth: Geometry.border
    // Exposed so a panel's roving-nav can forceActiveFocus() straight into the box
    // (Enter on the row "opens" it) — same shape as WSettingsField.input, one alias
    // hop onto WTextBox.input, not a third hop (quickshell-hub.md gotcha #9).
    property alias input: box.input

    signal save(string text)
    signal remove()

    spacing: 8

    WTextBox {
        id: box
        anchors.verticalCenter: parent.verticalCenter
        width: root.width - saveBtn.width - removeBtn.width - 2 * root.spacing
        password: true
        enabled: !root.busy
        placeholder: root.placeholder
        borderWidth: root.borderWidth
        onAccepted: if (text.trim() !== "") { root.save(text); text = ""; }
    }
    WButton {
        id: saveBtn
        anchors.verticalCenter: parent.verticalCenter
        label: Strings.t("hub.aiKeySave")
        enabled: !root.busy && box.text.trim() !== ""
        borderWidth: root.borderWidth
        onClicked: { root.save(box.text); box.text = ""; }
    }
    WButton {
        id: removeBtn
        anchors.verticalCenter: parent.verticalCenter
        tone: "danger"
        label: Strings.t("hub.aiKeyRemove")
        enabled: root.hasKey && !root.busy
        borderWidth: root.borderWidth
        onClicked: root.remove()
    }
}
