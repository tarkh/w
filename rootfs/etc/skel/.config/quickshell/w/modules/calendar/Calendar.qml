// W Linux — Calendar popup.
// Top-center anchored card with a month grid: a glanceable calendar opened by
// left-clicking the bar clock (Hyprland global quickshell:calendar). Pure QML —
// the grid is plain Date arithmetic, no external program or package. Month/weekday
// names and the week-start come from Qt.locale() (so they follow the system
// language); our only own string ("Today") comes from the shared Strings dictionary.
// Window, fade+scale animation and dismiss (Esc / click-outside) mirror the Volume
// Control popup; colors/radius/opacity/motion all flow through the theme singletons.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.notifications

Scope {
    id: root

    // Single-open coordination: bound to the shared Overlays state, so opening any
    // other popup closes this one (and vice versa). Toggle/close go through Overlays.
    readonly property bool active: Overlays.current === "calendar"

    readonly property int cell: 34          // day cell size (square)
    readonly property int pad:  14          // card inner padding
    readonly property int cardW: cell * 7 + pad * 2

    // Localization source: month/weekday names + week start follow the system locale.
    readonly property var loc: Qt.locale()
    // First day of week as a JS index (0=Sun..6=Sat), robust to either Qt enum
    // convention (Sun=0..Sat=6 stays; Mon=1..Sun=7 maps Sunday 7→0, rest unchanged).
    readonly property int firstDow: loc.firstDayOfWeek % 7

    // View state. `now` is the real today (refreshed each open so the highlight is
    // correct); viewYear/viewMonth is the displayed month, moved by the nav arrows.
    property var now: new Date()
    property int viewYear:  now.getFullYear()
    property int viewMonth: now.getMonth()

    readonly property bool atCurrentMonth:
        viewYear === now.getFullYear() && viewMonth === now.getMonth()

    // Keyboard nav: Left/Right always shift the month (immediate action, like a
    // WPill tab — no cursor to move there). Down/Up toggle a `todayFocused` state
    // that decides what Confirm does (there's nothing else in this card to select
    // — the day grid isn't clickable). Snaps back to false when the button
    // disappears (month shifted back onto today by the arrows themselves).
    readonly property bool todayVisible: !root.atCurrentMonth

    // Leading blank cells before day 1, so the grid aligns to the locale's week start.
    readonly property var firstOfMonth: new Date(viewYear, viewMonth, 1)
    readonly property int lead: (firstOfMonth.getDay() - firstDow + 7) % 7

    function cellDate(i)   { return new Date(viewYear, viewMonth, 1 - lead + i); }
    function cap(s)        { return s.length ? s[0].toUpperCase() + s.slice(1) : s; }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth()    === b.getMonth()
            && a.getDate()     === b.getDate();
    }

    // Localized short weekday name for header column `col`, derived from a real date
    // (2024-01-07 is a Sunday) to sidestep dayName index conventions entirely.
    function weekdayShort(col) {
        return root.loc.toString(new Date(2024, 0, 7 + (root.firstDow + col) % 7), "ddd");
    }

    function shift(months) {
        let m = root.viewMonth + months, y = root.viewYear;
        while (m < 0)  { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        root.viewMonth = m; root.viewYear = y;
    }
    function resetToToday() {
        root.now = new Date();
        root.viewYear  = root.now.getFullYear();
        root.viewMonth = root.now.getMonth();
    }

    // Snap to the real current month every time the popup opens.
    onActiveChanged: if (active) resetToToday()

    GlobalShortcut {
        appid: "quickshell"
        name: "calendar"
        onPressed: Overlays.toggle("calendar")
    }

    PanelWindow {
        id: win
        visible: root.active || card.opacity > 0.01

        // Full-screen transparent overlay: the backdrop catches outside clicks to
        // dismiss (the launcher/volume grab-free pattern); the card itself is opaque.
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "quickshell:calendar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive
                                                 : WlrKeyboardFocus.None

        onVisibleChanged: if (visible) card.forceActiveFocus()

        MouseArea { anchors.fill: parent; onClicked: Overlays.close("calendar") }

        Rectangle {
            id: card
            anchors {
                top: parent.top; horizontalCenter: parent.horizontalCenter
                // Share the OSD/Volume top offset so the center popups stay aligned.
                topMargin: BarConfig.contentTop + NotifConfig.osdMarginTopOffset
            }
            width: root.cardW
            implicitHeight: col.implicitHeight + root.pad * 2
            radius: Geometry.radius
            // Surface translucency from the effects axis (bg only; text stays opaque).
            color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, Effects.surfaceOpacity)
            border.color: Colors.border
            border.width: Geometry.border
            clip: true

            // Raw toggle; derived below so it self-clears once Today hides again
            // (e.g. the arrows themselves shift back onto the current month).
            property bool _todayArmed: false
            readonly property bool todayFocused: root.todayVisible && card._todayArmed

            focus: true
            Keys.onEscapePressed: Overlays.close("calendar")
            Keys.onPressed: (e) => {
                switch (e.key) {
                case HubNavKeys.left:  root.shift(-1); e.accepted = true; return;
                case HubNavKeys.right: root.shift(1); e.accepted = true; return;
                case HubNavKeys.down:
                    if (root.todayVisible) card._todayArmed = true;
                    e.accepted = true; return;
                case HubNavKeys.up:
                    card._todayArmed = false;
                    e.accepted = true; return;
                case HubNavKeys.confirm:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    if (card.todayFocused) root.resetToToday();
                    e.accepted = true; return;
                }
            }

            opacity: root.active ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            transformOrigin: Item.Top
            scale: root.active ? 1 : 0.94
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.base
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.bezierCurve
                }
            }

            // Swallow clicks so they don't fall through to the dismiss backdrop.
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: root.pad
                spacing: 8

                // ── Header: ‹  Month YYYY  › ─────────────────────────────
                Item {
                    width: parent.width
                    height: 28

                    // Prev / next month nav. Glyphs via String.fromCodePoint so the
                    // raw PUA chars are never dropped on file write (project rule).
                    component NavButton: Rectangle {
                        property string glyph
                        signal activated()
                        width: 28; height: 28; radius: Geometry.radiusSm
                        color: navMa.containsMouse ? Colors.hover : Colors.alpha(Colors.hover, 0)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Text {
                            anchors.centerIn: parent
                            text: parent.glyph
                            font.family: Fonts.mono
                            font.pixelSize: 16
                            color: Colors.muted
                        }
                        MouseArea {
                            id: navMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.activated()
                        }
                    }

                    NavButton {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        glyph: String.fromCodePoint(0xf104)   // nf-fa-angle_left
                        onActivated: root.shift(-1)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.cap(root.loc.standaloneMonthName(root.viewMonth + 1, Locale.LongFormat))
                              + " " + root.viewYear
                        color: Colors.text
                        font.family: Fonts.family
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }

                    NavButton {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        glyph: String.fromCodePoint(0xf105)   // nf-fa-angle_right
                        onActivated: root.shift(1)
                    }
                }

                // ── Weekday header row ───────────────────────────────────
                Row {
                    Repeater {
                        model: 7
                        delegate: Text {
                            required property int index
                            width: root.cell
                            horizontalAlignment: Text.AlignHCenter
                            text: root.weekdayShort(index)
                            color: Colors.muted
                            font.family: Fonts.family
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }

                // ── Divider ──────────────────────────────────────────────
                Rectangle { width: parent.width; height: 1; color: Colors.border; opacity: 0.5 }

                // ── Day grid (6 weeks × 7 days = fixed 42 cells, no breathing) ─
                Grid {
                    columns: 7
                    Repeater {
                        model: 42
                        delegate: Item {
                            required property int index
                            readonly property var  date:    root.cellDate(index)
                            readonly property bool inMonth: date.getMonth() === root.viewMonth
                            readonly property bool isToday: root.sameDay(date, root.now)

                            width: root.cell
                            height: root.cell

                            // Today highlight: accent circle behind the number.
                            Rectangle {
                                anchors.centerIn: parent
                                width: root.cell - 6; height: root.cell - 6
                                radius: width / 2
                                visible: isToday
                                color: Colors.accent
                            }

                            Text {
                                anchors.centerIn: parent
                                text: date.getDate()
                                font.family: Fonts.family
                                font.pixelSize: 13
                                font.features: ({ "tnum": 1 })
                                color: isToday  ? Colors.accentFg
                                     : inMonth  ? Colors.text
                                                : Colors.muted
                                opacity: inMonth || isToday ? 1 : 0.45
                            }
                        }
                    }
                }

                // ── Today reset (only when viewing another month) ────────
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: Geometry.radiusSm
                    visible: !root.atCurrentMonth
                    color: (todayMa.containsMouse || card.todayFocused) ? Colors.hover : Colors.alpha(Colors.hover, 0)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    border.color: card.todayFocused ? Colors.accentInk : Colors.border
                    border.width: card.todayFocused ? 2 : 1

                    Text {
                        anchors.centerIn: parent
                        text: Strings.t("calendar.today")
                        color: Colors.muted
                        font.family: Fonts.family
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: todayMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetToToday()
                    }
                }
            }
        }
    }
}
