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
// it; a panel without a `help` entry simply gets no button yet. The anchor must
// name a section that actually answers the panel's question — an approximate
// one is worse than no button, which is why the entry is added with the page.
//
// A TABBED panel whose tabs answer different questions overrides this per tab:
// it exposes its own `readonly property var help` (same { page, anchor } shape,
// or null for "no button on this tab") and Hub.qml prefers it over the entry
// here, which stays as the panel's default. See SystemPanel / InputPanel /
// DisplaysPanel; a panel without that property is unaffected.
import QtQuick

QtObject {
    id: root

    readonly property var panels: [
        { route: "appearance",  title: "hub.appearance",  source: "panels/AppearancePanel.qml",
          help: { page: "guide/theming.md", anchor: "the-appearance-panel" } },
        { route: "displays",    title: "hub.displays",    source: "panels/DisplaysPanel.qml",
          help: { page: "guide/displays.md", anchor: "the-monitor-layout" } },
        { route: "notifications", title: "hub.notifications", source: "panels/NotificationsPanel.qml",
          help: { page: "guide/desktop.md", anchor: "the-shell-surfaces" } },
        { route: "input",       title: "hub.input",       source: "panels/InputPanel.qml",
          help: { page: "guide/input.md", anchor: "keyboard-layouts-and-the-switch-key" } },
        { route: "hotkeys",     title: "hub.hotkeys",     source: "panels/HotkeysPanel.qml",
          help: { page: "guide/desktop.md", anchor: "windows-and-workspaces" } },
        { route: "network",     title: "hub.network",     source: "panels/NetworkPanel.qml",
          help: { page: "guide/network.md", anchor: "connections" } },
        { route: "power",       title: "hub.energy",      source: "panels/PowerPanel.qml",
          help: { page: "guide/power.md", anchor: "idle-lock-then-screen-off-then-suspend" } },
        { route: "system",      title: "hub.system",      source: "panels/SystemPanel.qml",
          help: { page: "guide/updates.md", anchor: "where-you-see-updates" } },
        { route: "ai",          title: "hub.ai",          source: "panels/AIProfilesPanel.qml",
          help: { page: "guide/ai.md", anchor: "profiles" } },
        { route: "packs",       title: "hub.packs",       source: "panels/PacksPanel.qml",
          help: { page: "guide/packs.md", anchor: "installing-and-setting-up-for-your-account" } },
        // Deeper drill-ins (not shown in the root grid): the theme builder from
        // Appearance, the layout picker from Input, and the locale + timezone pickers
        // from System (Date & Time is one of that panel's tabs, not a screen of its own,
        // which is why its picker is a `system.` route).
        { route: "appearance.new",  title: "appear.newTheme",  source: "panels/ThemeCreatePanel.qml",
          help: { page: "guide/theming.md", anchor: "creating-a-theme-from-a-wallpaper" } },
        // Same screen, editing an existing theme instead of building one — pushed
        // with { theme: <name> }, which is why routes carry arguments at all.
        { route: "appearance.edit", title: "appear.editTheme", source: "panels/ThemeCreatePanel.qml",
          help: { page: "guide/theming.md", anchor: "creating-a-theme-from-a-wallpaper" } },
        // No `help` here, and that is structural rather than an omission: this is a
        // Mode-B palette (the search field owns the keyboard for as long as it is open,
        // so Up belongs to the result list), which leaves no topmost roving position
        // from which to hand the cursor to the header. A button only the mouse can
        // reach is worse than none — same call as the locale/timezone pickers below.
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
