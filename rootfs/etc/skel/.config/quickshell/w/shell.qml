// W Linux — Quickshell shell root.
// The single UI process for the distro. Components are modular: each lives in its
// own file and is mounted here as the shell grows (launcher today; notifications,
// OSD, menus, settings, theme/wallpaper picker later). Theme colors come from the
// Colors singleton, timing from Motion, fonts from Fonts — all rendered by w-style
// from the active theme and live-reloaded.
import Quickshell
import qs.modules.overlay
import qs.modules.bar
import qs.modules.launcher
import qs.modules.clipboard
import qs.modules.assistant
import qs.modules.infobox
import qs.modules.layouts
import qs.modules.hub
import qs.modules.volume
import qs.modules.brightness
import qs.modules.calendar
import qs.modules.powermenu
import qs.modules.notifications
import qs.modules.auth

ShellRoot {
    // Shared scrim+blur backdrop for the modal-center popups (launcher/clipboard/
    // powermenu). Mounted first so its surface sits beneath the popup cards. See
    // modules/overlay/Backdrop.qml.
    Backdrop {}
    // Status bar (layer-shell panel, replaces Waybar). See modules/bar/.
    Bar {}
    // Tray context-menu overlay (native render, driven by TrayMenuState).
    TrayMenu {}
    Launcher {}
    // Clipboard-history viewer (cliphist store, $mod+V). See modules/clipboard/.
    Clipboard {}
    // "Ask W" assistant palette (Super+W, robot bar button). A thin prompt box that
    // hands off to `w-ai ask` in a terminal. See modules/assistant/.
    Assistant {}
    // Generic content overlay (title + Markdown body + action buttons), driven by
    // Overlays.openInfobox(). Used today by the assistant's readiness gate. See
    // modules/infobox/.
    Infobox {}
    // The two global shortcuts `w-session restore` raises the infobox with while it
    // deals last session's windows back onto their workspaces. See modules/infobox/.
    SessionCurtain {}
    // Saved window layouts (SUPER+O): name one, save every workspace or just this
    // one, put a saved one back. Every verb is `w-session`. See modules/layouts/.
    Layouts {}
    // W Hub — central system-control menu (Super+Space, w-logo button). Drill-in
    // "W Settings + Control Center". See modules/hub/.
    Hub {}
    VolumeControl { id: volumeControl }
    // Brightness Control popup (top-center, mirrors Volume). Opened by the Hub tile.
    BrightnessControl { id: brightnessControl }
    // Calendar popup (top-center), opened by left-clicking the bar clock.
    Calendar {}
    PowerMenu {}
    // Notification daemon (freedesktop server + top-right stack).
    Notifications {}
    // Unified auth prompt: the single centered password dialog for every polkit
    // request, driven by the w-authd daemon. Replaces hyprpolkitagent's GTK window.
    AuthPrompt {}
    // Volume / brightness OSD. Suppressed while the Volume/Brightness Control popup
    // is open so adjusting there doesn't also throw an OSD.
    Osd { suppress: volumeControl.active || brightnessControl.active }
}
