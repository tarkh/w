// W Linux bar block — zone (decorative wrapper / meta-block).
//
// A zone groups other standard blocks behind a single shared background, and can
// optionally fold: when folded it collapses horizontally to an icon + label and
// reveals its inner blocks on demand. Two reveal triggers:
//   • "hover" — the whole zone is the hover target; on hover the icon+label
//     crossfade out and the inner blocks slide in. On leave it collapses back. The
//     handle and the blocks never coexist.
//   • "click" — the icon+label stays as a persistent toggle handle at position 0;
//     clicking it expands/collapses. Inner blocks keep their own click handlers
//     untouched (the handle is a separate hit target). If both icon and label are
//     empty in click mode, a default chevron handle is shown so there's always a
//     toggle.
// When folded.enabled is false the zone is always expanded — a pure decorative
// meta-block (hide the inner blocks' own zones with opacity 0 / padding 0 to make
// several blocks look like one unit).
//
// Inner blocks are rendered exactly like top-level blocks (BarConfig.blockSource +
// Loader, settings handed in onLoaded) and honor "enabled": false the same way.
// Folding only hides them visually — their processes keep running normally.
//
// All colors go through BarConfig.col (theme token or #hex + separate opacity);
// motion follows the shell Motion singleton.
import Quickshell
import QtQuick
import qs.core
import qs.modules.bar
import qs.modules.shading

Item {
    id: block

    // Set by the (Bar/Zone) Loader from the block's "settings" object in bar.json.
    property var settings: ({})

    // ── Zone styling (mirrors the per-block zone convention) ──────────────────
    readonly property var zonePad:    settings.zonePadding || ({})
    readonly property var zoneRadius: settings.zoneRadius !== undefined ? settings.zoneRadius : BarConfig.radiusZone
    readonly property int itemsGap:   BarConfig.geo(settings.itemsGap, BarConfig.gapItem)
    // Applies to the FOLDED presentation (handle only, no revealed items) — a small
    // icon-only handle in a pill zone looks oval just like a leaf block. Expanded
    // (items revealed) is already wider than the height in practice, so the floor
    // is a no-op there.
    readonly property bool minSquare: BarConfig.minSquare
    // A `zone` wraps other blocks, so it takes the same padding scale as a leaf block.
    readonly property int padL: BarConfig.padOf(zonePad, "left",   BarConfig.padZoneH)
    readonly property int padR: BarConfig.padOf(zonePad, "right",  BarConfig.padZoneH)
    readonly property int padT: BarConfig.padOf(zonePad, "top",    BarConfig.padZoneV)
    readonly property int padB: BarConfig.padOf(zonePad, "bottom", BarConfig.padZoneV)

    // Nested blocks. Preferred location is the block's top-level "items", handed in by
    // the Loader as itemsModel — ALREADY resolved for this monitor by BarConfig.blocksFor
    // ("enabled" plus the per-monitor `show` override), so it must not be filtered again
    // here: `show` may legitimately revive an item whose global "enabled" is false, and a
    // second enabledOnly() pass would drop it right back out. The settings.items fallback
    // (older configs, no per-monitor resolution possible) still gets the plain filter.
    property var itemsModel: []
    readonly property bool fromLoader: !!(itemsModel && itemsModel.length)
    readonly property var items: block.fromLoader ? itemsModel : BarConfig.enabledOnly(settings.items || [])

    // ── Folded config ─────────────────────────────────────────────────────────
    readonly property var  fcfg:        settings.folded || ({})
    readonly property bool foldEnabled: fcfg.enabled === true
    readonly property bool clickMode:   fcfg.trigger === "click"
    readonly property bool showChevron: fcfg.chevron === true

    readonly property string fIcon:   fcfg.icon  !== undefined ? fcfg.icon  : ""
    readonly property string fLabel:  fcfg.label !== undefined ? fcfg.label : ""
    readonly property int    iconSize: fcfg.iconSize !== undefined ? fcfg.iconSize : 18
    readonly property int    fontSize: fcfg.fontSize !== undefined ? fcfg.fontSize : 12
    readonly property int    iconGap:  fcfg.iconGap  !== undefined ? fcfg.iconGap  : 6

    // An icon string is treated as an image (themed name or file path) when it looks
    // like a path / has an extension / resolves as a theme icon; otherwise it's a
    // Nerd Font glyph rendered as plain text. Shading only applies to image icons.
    readonly property bool fIconIsPath:  fIcon.indexOf("/") >= 0 || fIcon.indexOf(".") >= 0
    readonly property bool fIconIsImage: fIcon.length > 0 && (fIconIsPath || Quickshell.hasThemeIcon(fIcon))
    function iconShadeMode() {
        switch (fcfg.iconMode) {
        case "tint":  return ShadedIcon.Tint;
        case "solid": return ShadedIcon.Solid;
        default:      return ShadedIcon.Original;
        }
    }

    // In click mode the handle persists as a toggle. With no icon/label, fall back to
    // a default chevron so there's always something to click.
    readonly property bool handlePersists:   foldEnabled && clickMode
    readonly property bool hasHandleContent:  fIcon.length > 0 || fLabel.length > 0
    readonly property bool defaultHandle:     handlePersists && !hasHandleContent
    readonly property bool handleHasChrome:   foldEnabled && (hasHandleContent || defaultHandle || showChevron)

    // ── Expansion state ───────────────────────────────────────────────────────
    property bool hovered:    false
    property bool pinnedOpen: false
    readonly property bool expanded: !foldEnabled || (clickMode ? pinnedOpen : hovered)

    // Collapse the whole zone (and its gap) when there's nothing to show: no visible
    // child and no folded chrome to display.
    readonly property bool anyChildVisible: {
        for (var i = 0; i < itemsRepeater.count; i++) {
            var ld = itemsRepeater.itemAt(i);
            if (ld && ld.item) {
                var bv = ld.item.barVisible;
                if (bv === undefined || bv === true) return true;
            }
        }
        return false;
    }
    readonly property bool barVisible: anyChildVisible || (foldEnabled && handleHasChrome)

    // Whole-zone interaction (click-flash + cursor for the wrapper as one unit). Only
    // active when the zone opts in via clickColor*/cursor — otherwise the interaction
    // overlay would impose its cursor over the inner blocks and mask their own.
    readonly property bool clickInteractive:
        settings.clickColorLeft  !== undefined
        || settings.clickColorRight !== undefined
        || settings.cursor       !== undefined

    implicitWidth:  zone.width
    implicitHeight: parent ? parent.height : zone.height

    Rectangle {
        id: zone
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - block.padT - block.padB
        clip: true
        radius: BarConfig.elemRadius(block.zoneRadius, height, 0)
        color:  BarConfig.col(block.settings.zoneColor, block.settings.zoneOpacity)
        border.width: BarConfig.zoneBorderWidth(block.settings)
        border.color: BarConfig.zoneBorderColor(block.settings)
        // Width follows its animated children (handle + items); no Behavior here, or
        // the animation would double up. The minSquare floor is a constant (height),
        // not a toggled one, so Math.max stays smooth through the fold animation.
        width: Math.max(block.padL + handle.width + itemsBox.width + block.padR,
                         block.minSquare ? height : 0)

        // The width the zone settles at once fully folded (itemsBox gone). Built from
        // static/intrinsic sizes only (padding, the handle's natural content width,
        // own height) — never from `width` above, which is still animating mid-fold as
        // itemsBox shrinks. Used to give the handle a fixed centering target instead of
        // one that chases the live width (see handle.anchors.leftMargin below).
        readonly property int foldedWidth: Math.max(block.padL + handleRow.implicitWidth + block.padR,
                                                      block.minSquare ? height : 0)

        // Whole-zone click-flash, under the handle + inner blocks. Opt-in via
        // clickColorLeft/clickColorRight (pulse() is a no-op for an unset button).
        ClickFlash {
            id: flash
            anchors.fill: parent
            radius: zone.radius
            colorLeft:   block.settings.clickColorLeft
            colorRight:  block.settings.clickColorRight
            apexOpacity: block.settings.clickOpacity  !== undefined ? block.settings.clickOpacity  : 0.5
            duration:    block.settings.clickDuration !== undefined ? block.settings.clickDuration : Motion.base
        }

        // ── Folded handle: icon + label (+ optional chevron) ──────────────────
        Item {
            id: handle
            anchors.left: parent.left
            // Centered instead of padL-anchored while folded under minSquare, so a
            // lone icon sits in the middle of the widened (height-floored) zone
            // instead of hugging the left edge. Animated (unlike leftMargin
            // elsewhere) because, in click mode, the handle stays visible and
            // shifting position must not jump when itemsBox reveals/hides.
            //
            // Targets zone.foldedWidth (stable), NOT the live zone.width: the latter
            // is still animating down from its expanded size as itemsBox collapses, so
            // chasing it made the icon swing out toward the old (still-wide) center
            // before sliding back — a visible glitch. handleRow.implicitWidth (not the
            // live, possibly-animating handle.width) keeps the target fixed the instant
            // the fold starts, so this Behavior eases straight to the resting position.
            anchors.leftMargin: (block.minSquare && !block.expanded)
                ? (zone.foldedWidth - handleRow.implicitWidth) / 2
                : block.padL
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            Behavior on anchors.leftMargin {
                NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve }
            }

            readonly property bool present: block.foldEnabled && block.handleHasChrome
            // hover: shown only while folded (crossfades out on expand). click: always.
            width: !present ? 0
                 : (block.handlePersists ? handleRow.implicitWidth
                                         : (block.expanded ? 0 : handleRow.implicitWidth))
            opacity: !present ? 0
                   : (block.handlePersists ? 1 : (block.expanded ? 0 : 1))
            visible: width > 0 || opacity > 0
            clip: true

            Behavior on width   { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve } }
            Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve } }

            Row {
                id: handleRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: block.iconGap

                // Glyph icon.
                Text {
                    visible: block.fIcon.length > 0 && !block.fIconIsImage
                    anchors.verticalCenter: parent.verticalCenter
                    text: block.fIcon
                    font.family: Fonts.mono
                    font.pixelSize: block.iconSize
                    color: BarConfig.col(
                        block.fcfg.iconColor   !== undefined ? block.fcfg.iconColor   : block.fcfg.textColor,
                        block.fcfg.iconOpacity !== undefined ? block.fcfg.iconOpacity : 1.0)
                }
                // Image / themed icon (shaded).
                ShadedIcon {
                    visible: block.fIconIsImage
                    anchors.verticalCenter: parent.verticalCenter
                    size: block.iconSize
                    icon:   block.fIconIsPath ? "" : block.fIcon
                    source: block.fIconIsPath ? (block.fIcon.charAt(0) === "/" ? "file://" + block.fIcon : block.fIcon) : ""
                    mode:   block.iconShadeMode()
                    tint:   BarConfig.col(block.fcfg.iconColor !== undefined ? block.fcfg.iconColor : "text", 1.0)
                    opacity: block.fcfg.iconOpacity !== undefined ? block.fcfg.iconOpacity : 1.0
                    strength: block.fcfg.iconStrength !== undefined ? block.fcfg.iconStrength : 1.0
                    shade:    block.fcfg.iconShade    !== undefined ? block.fcfg.iconShade    : 0.45
                    lift:     block.fcfg.iconLift     !== undefined ? block.fcfg.iconLift     : 0.20
                }
                // Label.
                Text {
                    visible: block.fLabel.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: block.fLabel
                    font.family: Fonts.family
                    font.pixelSize: block.fontSize
                    color: BarConfig.col(
                        block.fcfg.textColor   !== undefined ? block.fcfg.textColor   : "text",
                        block.fcfg.textOpacity !== undefined ? block.fcfg.textOpacity : 1.0)
                }
                // Optional expand/collapse chevron (also the default handle glyph when
                // click mode has no icon/label). Rotates to point down when expanded.
                Text {
                    visible: block.showChevron || block.defaultHandle
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf105"           // nf-fa-angle_right (escaped: raw PUA glyphs drop on write)
                    font.family: Fonts.mono
                    font.pixelSize: block.iconSize
                    rotation: block.expanded ? 90 : 0
                    color: BarConfig.col(
                        block.fcfg.iconColor   !== undefined ? block.fcfg.iconColor   : "text",
                        block.fcfg.iconOpacity !== undefined ? block.fcfg.iconOpacity : 0.7)
                    Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve } }
                }
            }

            // Click-mode toggle. Hover mode drives expansion via the zone HoverHandler.
            MouseArea {
                anchors.fill: parent
                enabled: block.handlePersists
                cursorShape: block.handlePersists ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: block.pinnedOpen = !block.pinnedOpen
            }
        }

        // ── Inner blocks ──────────────────────────────────────────────────────
        Item {
            id: itemsBox
            anchors.left: handle.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            clip: true
            // Leading gap separates the persistent handle (click mode) from the items.
            readonly property int leadGap: block.handlePersists ? block.itemsGap : 0
            width: block.expanded ? (leadGap + itemsRow.implicitWidth) : 0
            Behavior on width { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve } }

            Row {
                id: itemsRow
                anchors.left: parent.left
                anchors.leftMargin: itemsBox.leadGap
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: block.itemsGap
                // The inner blocks fade in/out as the zone expands/collapses, on top of
                // the width slide — softer than a bare reveal.
                opacity: block.expanded ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.bezierCurve } }

                Repeater {
                    id: itemsRepeater
                    model: block.items
                    delegate: itemDelegate
                }
            }
        }

        // Hover trigger covering the whole (growing) zone. acceptedButtons:NoButton so
        // it only tracks hover — presses fall straight through to the click-mode handle
        // and to the inner blocks (their clicks stay intact). HoverHandler proved
        // unreliable on this layer-Top surface; MouseArea+hoverEnabled is the pattern
        // used across the shell and works here. The pointer stays inside once the zone
        // expands, so it holds open until the cursor leaves.
        //
        // Only enabled for hover-fold: a MouseArea imposes its cursorShape (default
        // arrow) wherever it's enabled — regardless of acceptedButtons — so an
        // always-on overlay would mask the inner blocks' own cursors (the reason
        // cpu/ram/temp/disk showed an arrow). hovered only drives expansion in
        // hover-fold mode, so gating it off elsewhere is safe.
        MouseArea {
            anchors.fill: parent
            enabled: block.foldEnabled && !block.clickMode
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onContainsMouseChanged: block.hovered = containsMouse
        }

        // Whole-zone interaction overlay (topmost): the zone's own cursor + click-flash.
        // Disabled unless the zone opts in (clickInteractive) so it never masks the
        // inner blocks' cursors when unused. Presses are declined (accepted=false) so
        // they still reach the inner blocks' handlers (e.g. cpu→btop) and the click-mode
        // fold handle — the whole zone flashes AND the clicked element acts. hoverEnabled
        // is false so the fold hover-tracker above keeps working.
        MouseArea {
            anchors.fill: parent
            enabled: block.clickInteractive
            hoverEnabled: false
            cursorShape: BarConfig.cursor(block.settings.cursor, Qt.ArrowCursor)
            acceptedButtons: Qt.LeftButton | (block.settings.clickColorRight !== undefined ? Qt.RightButton : Qt.NoButton)
            onPressed: (mouse) => { flash.pulse(mouse.button); mouse.accepted = false; }
        }
    }

    // Same delegate as the Bar: load the nested block and hand it its settings. A
    // hidden child (barVisible false) collapses out of the inner Row.
    Component {
        id: itemDelegate
        Loader {
            id: ld
            required property var modelData
            height: itemsRow.height
            width:  item ? item.implicitWidth : 0
            visible: item && item.barVisible !== undefined ? item.barVisible : true
            source: BarConfig.blockSource(modelData.type)
            onLoaded: {
                if (!item) return;
                item.settings = modelData.settings;
                // Support nested zones: hand a top-level "items" through as well.
                if (item.itemsModel !== undefined && modelData.items !== undefined)
                    item.itemsModel = modelData.items;
            }
        }
    }
}
