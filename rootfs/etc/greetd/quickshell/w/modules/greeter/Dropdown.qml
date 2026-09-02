// W Linux — greeter dropdown.
// A palette-styled select used for both the user and the session pickers. Header
// shows the current label + a chevron; clicking opens a Popup list below (Popup
// owns positioning + click-outside/Escape dismissal). Hover states follow the
// theme palette. Model is [{ label, value }]; `activated(value)` fires on pick.
import QtQuick
import QtQuick.Controls
import qs.core

Item {
    id: root

    property var model: []                 // [{ label, value }]
    property var currentValue: undefined
    property string placeholder: ""
    signal activated(var value)

    implicitHeight: 46
    activeFocusOnTab: true

    function labelFor(v) {
        for (const m of root.model) if (m.value === v) return m.label;
        return root.placeholder;
    }

    function indexOf(v) {
        for (let i = 0; i < root.model.length; i++) if (root.model[i].value === v) return i;
        return 0;
    }

    // Keyboard: no HubNavKeys here (greeter has no user profile to read it
    // from) — a small fixed scheme instead, same style as PowerMenu.qml's
    // hardcoded Left/Right. Popup's own CloseOnEscape never fires because
    // active focus stays on `root` (the popup is never given focus), so
    // Escape is handled here alongside Up/Down/Enter.
    //
    // Closed: only Enter/Space open it — Up/Down are reserved for jumping to
    // the previous/next focusable on the card (via nextItemInFocusChain, the
    // same chain Tab/Shift+Tab already walk), same as every other element.
    // Ctrl+J/K mirror Down/Up for the same jump, one step below Tab-order for
    // power users — mnemonic-fixed like the rest of the greeter, not tied to
    // a HubNavKeys/profile mapping.
    property int highlightIndex: -1
    Keys.onPressed: (event) => {
        if (!popup.opened) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.highlightIndex = root.indexOf(root.currentValue);
                popup.open();
                event.accepted = true;
                return;
            }
            const fwd = event.key === Qt.Key_Down || (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier));
            const bwd = event.key === Qt.Key_Up   || (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier));
            if (fwd) { root.nextItemInFocusChain(true).forceActiveFocus(); event.accepted = true; }
            else if (bwd) { root.nextItemInFocusChain(false).forceActiveFocus(); event.accepted = true; }
            return;
        }
        if (event.key === Qt.Key_Down) {
            root.highlightIndex = Math.min(root.highlightIndex + 1, root.model.length - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.highlightIndex = Math.max(root.highlightIndex - 1, 0);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const m = root.model[root.highlightIndex];
            if (m) { root.currentValue = m.value; root.activated(m.value); }
            popup.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            popup.close();
            event.accepted = true;
        }
    }

    Rectangle {
        id: head
        anchors.fill: parent
        radius: Geometry.radiusSm
        color: Colors.inputBg
        // Focus ring: width is constant — only color animates. Animating
        // border.width itself (even 1↔2) pops instead of transitioning
        // smoothly (no scene-graph node to interpolate through), so every
        // focusable in the greeter shares this fixed-width/color-only scheme.
        border.width: 1.5
        border.color: (hover.hovered || popup.opened || root.activeFocus) ? Colors.accent : "transparent"
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        HoverHandler { id: hover }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: chev.left
            anchors.rightMargin: 8
            text: root.labelFor(root.currentValue)
            color: Colors.text
            font.family: Fonts.family
            font.pixelSize: 15
            elide: Text.ElideRight
        }

        Text {
            id: chev
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 14
            text: "▾"                 // ▾
            color: Colors.muted
            font.pixelSize: 14
            rotation: popup.opened ? 180 : 0
            Behavior on rotation {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.forceActiveFocus();
                if (popup.opened) { popup.close(); }
                else { root.highlightIndex = root.indexOf(root.currentValue); popup.open(); }
            }
        }
    }

    Popup {
        id: popup
        y: head.height + 6
        width: head.width
        padding: 6
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        background: Rectangle {
            radius: Geometry.radiusSm
            color: Colors.surface
            border.color: Colors.border
            border.width: Geometry.border
        }

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fast } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.fast } }

        contentItem: Column {
            spacing: 2
            Repeater {
                model: root.model
                delegate: Rectangle {
                    id: delegateRoot
                    required property var modelData
                    required property int index
                    property bool picked: rowMa.containsMouse || index === root.highlightIndex
                    width: popup.availableWidth
                    height: 38
                    radius: Geometry.radiusSm
                    color: delegateRoot.picked ? Colors.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        text: delegateRoot.modelData.label
                        color: delegateRoot.picked ? Colors.accentFg : Colors.text
                        font.family: Fonts.family
                        font.pixelSize: 15
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.currentValue = delegateRoot.modelData.value;
                            root.activated(delegateRoot.modelData.value);
                            popup.close();
                        }
                    }
                }
            }
        }
    }
}
