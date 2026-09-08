// W Linux — Hub breadcrumb header.
// The top row of a drill-in panel: a `‹ Back` affordance plus the panel title,
// and, when the panel has one, a help button on the right that opens THAT
// panel's documentation page at the section that explains it (HubRegistry.help).
// On the root screen there is nothing above it, so the back control is hidden
// and only the title shows (Ф1 gives the root its own heading). Emits `back()`
// on click / when the caller wires Esc/Backspace to it; the Hub owns the actual
// pop. Colors/fonts follow the shared singletons. Reusable across every panel
// so the breadcrumb reads identically.
import QtQuick
import qs.core
import qs.modules.shading

Item {
    id: root

    property string title: ""
    property bool canGoBack: false
    property string helpPage: ""       // docs page of this panel; "" → no button
    property string helpAnchor: ""     // section slug within that page

    signal back()

    implicitHeight: 40
    implicitWidth: parent ? parent.width : 0

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // `‹ Back` chevron — only on sub-panels (root has nothing to go back to).
        Item {
            width: backRow.implicitWidth
            height: root.height
            visible: root.canGoBack

            Row {
                id: backRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹"                      // ‹
                    color: back.containsMouse ? Colors.accentInk : Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 22
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("hub.back")
                    color: back.containsMouse ? Colors.accentInk : Colors.muted
                    font.family: Fonts.family
                    font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }

            MouseArea {
                id: back
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.back()
            }
        }
    }

    // Panel title. Centered on the card so it reads as a heading regardless of the
    // back control's width.
    Text {
        anchors.centerIn: parent
        text: root.title
        color: Colors.text
        font.family: Fonts.family
        font.pixelSize: 16
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    // Help on this panel: the "?" opens the panel's page at its section. Present
    // on the SAME right edge as the back affordance's left corner — the one
    // spot that is free on every panel regardless of its content layout.
    Item {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        visible: root.helpPage.length > 0

        ChromeIcon {
            anchors.centerIn: parent
            glyph: DocsViewer.helpGlyph
            size: 20
        }

        MouseArea {
            id: helpMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: DocsViewer.openPage(root.helpPage, root.helpAnchor)
        }
    }
}
