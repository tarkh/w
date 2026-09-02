// W Linux — Hub section header.
// A small group label for a settings panel: an uppercase muted caption with a hairline
// rule filling the rest of the row. Replaces a bare divider so grouped rows (e.g. the DNS
// mode + provider, or the firewall zone) read as a titled section. Co-located in
// modules/hub/ so panels reach it via `import qs.modules.hub`. Colors/fonts from the
// shared singletons.
import QtQuick
import qs.core

Item {
    id: root

    property string text: ""

    implicitHeight: lbl.implicitHeight

    Text {
        id: lbl
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: root.text
        color: Colors.muted
        font.family: Fonts.family
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    // Hairline to the right of the caption, so the header doubles as the group divider.
    Rectangle {
        anchors {
            left: lbl.right; leftMargin: 10
            right: parent.right
            verticalCenter: lbl.verticalCenter
        }
        height: 1
        color: Colors.border
        opacity: 0.4
    }
}
