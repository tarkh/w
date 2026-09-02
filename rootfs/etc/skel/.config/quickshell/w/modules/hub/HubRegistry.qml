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
// Empty for Ф0 (foundation only): the Hub opens on its root placeholder. Panels are
// added in later phases (Appearance/Network/System/Input), each as a `panels/*.qml`
// screen plus a row here.
import QtQuick

QtObject {
    id: root

    readonly property var panels: [
        { route: "system",      title: "hub.system",      source: "panels/SystemPanel.qml" },
        { route: "ai",          title: "hub.ai",          source: "panels/AIProfilesPanel.qml" },
        { route: "appearance",  title: "hub.appearance",  source: "panels/AppearancePanel.qml" },
        { route: "notifications", title: "hub.notifications", source: "panels/NotificationsPanel.qml" },
        { route: "datetime",    title: "hub.datetime",    source: "panels/DateTimePanel.qml" },
        { route: "network",     title: "hub.network",     source: "panels/NetworkPanel.qml" },
        { route: "security",    title: "hub.security",    source: "panels/SecurityPanel.qml" },
        { route: "power",       title: "hub.energy",      source: "panels/PowerPanel.qml" },
        { route: "packs",       title: "hub.packs",       source: "panels/PacksPanel.qml" },
        { route: "input",       title: "hub.input",       source: "panels/InputPanel.qml" },
        { route: "displays",    title: "hub.displays",    source: "panels/DisplaysPanel.qml" },
        { route: "hotkeys",     title: "hub.hotkeys",     source: "panels/HotkeysPanel.qml" },
        // Deeper drill-ins (not shown in the root grid): the theme builder from
        // Appearance, the layout picker from Input, the locale picker from System,
        // the timezone picker from Date & Time.
        { route: "appearance.new",  title: "appear.newTheme",  source: "panels/ThemeCreatePanel.qml" },
        // Same screen, editing an existing theme instead of building one — pushed
        // with { theme: <name> }, which is why routes carry arguments at all.
        { route: "appearance.edit", title: "appear.editTheme", source: "panels/ThemeCreatePanel.qml" },
        { route: "input.kbd",       title: "hub.addLanguage", source: "panels/KeyboardPicker.qml" },
        { route: "system.locale",   title: "hub.language",    source: "panels/LocalePicker.qml" },
        { route: "datetime.timezone", title: "hub.timezone",  source: "panels/TimezonePicker.qml" },
    ]

    // Resolve a route → its registry entry (or null). Used by the Hub Loader and by
    // breadcrumb titles. Kept here so routing logic lives with the data.
    function find(route) {
        for (let i = 0; i < root.panels.length; i++)
            if (root.panels[i].route === route) return root.panels[i];
        return null;
    }
}
