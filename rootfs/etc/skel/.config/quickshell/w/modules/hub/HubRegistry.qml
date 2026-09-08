pragma Singleton

// W Linux — Hub panel registry.
// The single ordered source of truth for the Hub's drill-in panels: display order,
// routing and deep-link targets all live here (not in JSON) because panels are real
// QML screens. Each entry is:
//   { route: "appearance", title: "hub.appearance", icon: <glyph|name>, source: "panels/AppearancePanel.qml" }
// `route` is the key used by deep-links (Overlays.open("hub", { route })) and by the
// Hub's Loader to resolve the current screen's `source`. Order in `panels` = order in
// the root grid — system-defined, NOT user-configurable.
//
// Order below = order in the root grid's section block, and the two are kept in step by
// hand — the grid is the visible contract, this list is what routing resolves against.
// Security and Date & Time are NOT here: they are tabs of the System panel, rendered by
// panels/SecuritySection.qml and panels/DateTimeSection.qml, which are loaded by that
// panel rather than routed to.
//
// `help` — the panel's user documentation: { page, anchor } into the docs tree
// (/usr/share/doc/w, resolved by core/DocsViewer). The header's "?" button uses
// it; a panel without a `help` entry simply gets no button yet.
import QtQuick

QtObject {
    id: root

    readonly property var panels: [
        { route: "appearance",  title: "hub.appearance",  source: "panels/AppearancePanel.qml",
          help: { page: "guide/theming.md", anchor: "the-appearance-panel" } },
        { route: "displays",    title: "hub.displays",    source: "panels/DisplaysPanel.qml" },
        { route: "notifications", title: "hub.notifications", source: "panels/NotificationsPanel.qml" },
        { route: "input",       title: "hub.input",       source: "panels/InputPanel.qml" },
        { route: "hotkeys",     title: "hub.hotkeys",     source: "panels/HotkeysPanel.qml" },
        { route: "network",     title: "hub.network",     source: "panels/NetworkPanel.qml" },
        { route: "power",       title: "hub.energy",      source: "panels/PowerPanel.qml" },
        { route: "system",      title: "hub.system",      source: "panels/SystemPanel.qml",
          help: { page: "guide/updates.md", anchor: "where-you-see-updates" } },
        { route: "ai",          title: "hub.ai",          source: "panels/AIProfilesPanel.qml" },
        { route: "packs",       title: "hub.packs",       source: "panels/PacksPanel.qml" },
        // Deeper drill-ins (not shown in the root grid): the theme builder from
        // Appearance, the layout picker from Input, and the locale + timezone pickers
        // from System (Date & Time is one of that panel's tabs, not a screen of its own,
        // which is why its picker is a `system.` route).
        { route: "appearance.new",  title: "appear.newTheme",  source: "panels/ThemeCreatePanel.qml" },
        // Same screen, editing an existing theme instead of building one — pushed
        // with { theme: <name> }, which is why routes carry arguments at all.
        { route: "appearance.edit", title: "appear.editTheme", source: "panels/ThemeCreatePanel.qml" },
        { route: "input.kbd",       title: "hub.addLanguage", source: "panels/KeyboardPicker.qml" },
        { route: "system.locale",   title: "hub.language",    source: "panels/LocalePicker.qml" },
        { route: "system.timezone", title: "hub.timezone",    source: "panels/TimezonePicker.qml" },
    ]

    // Resolve a route → its registry entry (or null). Used by the Hub Loader and by
    // breadcrumb titles. Kept here so routing logic lives with the data.
    function find(route) {
        for (let i = 0; i < root.panels.length; i++)
            if (root.panels[i].route === route) return root.panels[i];
        return null;
    }
}
