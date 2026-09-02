-- W Linux — Hyprland base config (Lua, the config format since Hyprland 0.55).
-- Tuning happens in a later session.

-- Theme-driven fragments rendered by w-style (apply user). Each is a small data
-- module returning a table; hyprland.lua threads the values into hl.config below
-- and the blur layer rules. animations.lua is self-applying (it declares the
-- `snap` curve + animation leaves), so it is only require()d for its side effects.
-- pcall wraps each require so a missing/broken fragment (e.g. before the first
-- `w-style apply` on a fresh account) does not abort the whole config; a baseline
-- fallback keeps the session usable.
local function fragment(mod, fallback)
  local ok, val = pcall(require, mod)
  if ok then return val end
  return fallback
end

local colors = fragment("colors", {
  border_active = "rgba(ffffffff)", border_inactive = "rgba(444444ff)", bg = "rgba(000000ff)",
  group_border_active = "rgba(ffffffff)", group_border_inactive = "rgba(444444ff)",
  tab_active_bg = "rgba(643670ff)", tab_inactive_bg = "rgba(2e0045ff)",
  tab_active_fg = "rgba(ffffffff)", tab_inactive_fg = "rgba(a197a4ff)",
})
local geo = fragment("geometry", { gaps_in = 4, gaps_out = 8, border = 2, rounding = 14, tab_height = 20, tab_rounding = 10, tab_gap = 4, tab_gap_in = 2 })
local fx = fragment("effects", {
  opacity_active = 1.0, opacity_inactive = 1.0, opacity_fullscreen = 1.0,
  blur_enabled = true, blur_size = 3, blur_passes = 3, blur_ignore_alpha = 0.3, app_bg = 0.85,
})
-- Keyboard layout ring + typing behaviour — user-owned, rewritten by `w-keyboard` /
-- the W Hub Input panel (live via hyprctl + persisted here so it survives relogin).
-- The fallback mirrors the shipped default so a fresh account is usable before the
-- first seed.
local kbd = fragment("keyboard", {
  layout = "us,ru", variant = "", options = "grp:alt_shift_toggle",
  repeat_rate = 25, repeat_delay = 600, numlock = false,
})
-- Pointer devices (mouse + touchpad + swipe gestures) — user-owned, rewritten by
-- `w-pointer` / the W Hub Input panel. Same shape of contract as the keyboard ring:
-- the fragment is the source of truth, `hyprctl reload` re-runs this file to apply.
-- The fallback mirrors the shipped skel default (notably touchpad natural scrolling,
-- which W has enabled since its first Hyprland config).
local ptr = fragment("pointer", {
  mouse = {}, touchpad = { natural_scroll = true }, gestures = {}, devices = {},
})
local ptr_mouse = type(ptr.mouse) == "table" and ptr.mouse or {}
local ptr_pad   = type(ptr.touchpad) == "table" and ptr.touchpad or {}
local ptr_gest  = type(ptr.gestures) == "table" and ptr.gestures or {}
local ptr_cur   = type(ptr.cursor) == "table" and ptr.cursor or {}
-- `x or default` is wrong for booleans (false would fall through to the default),
-- so pick explicitly on nil.
local function pick(v, fallback) if v == nil then return fallback end return v end
-- Monitor layout — user-owned, rewritten by `w-monitor` / the W Hub Displays panel.
-- nil fallback (not a table): an absent fragment means "no saved rules", which the
-- loop below already treats as a no-op, leaving the fallback rule below in charge.
local mons = fragment("monitors", nil)
pcall(require, "animations")

-- Re-alpha a "rgba(RRGGBBAA)" color string with an opacity float (0..1). Used to
-- tint the group tab pills with the theme's app-background translucency so they
-- frost like real windows instead of reading as solid plaques.
local function with_opacity(rgba, o)
  local hex = tostring(rgba):match("rgba%((%x%x%x%x%x%x)")
  if not hex then return rgba end
  local a = math.floor(math.max(0, math.min(1, o)) * 255 + 0.5)
  return string.format("rgba(%s%02x)", hex, a)
end

-- ── Monitors ─────────────────────────────────────────────────────────────────
-- Fallback rule first: catches any output with no saved w-monitor rule (unconfigured
-- / freshly hotplugged). Explicit whitelist below — `primary` is a W concept, not a
-- Hyprland one, and passing it through to hl.monitor() would be a runtime type error.
-- scale "auto" (quoted, like every scale we emit) matches the default the explicit
-- branch below uses for a rule with no scale of its own, so an output behaves the
-- same before and after w-monitor first writes a rule for it — and a HiDPI screen
-- plugged into a fresh session is not pinned to 1.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- Every output name our own rules mention — used ONLY as a static list for the
-- best-effort boot safety net in the Autostart section below (hyprland.start),
-- never as a runtime query. ⚠️ KNOWN INCOMPLETE (see w-monitor.md §Отложено/known
-- bugs, VM-verified 2026-07-31): this recovers a monitor that got disabled while
-- at least one OTHER real output stayed enabled and reached a real modeset at
-- boot. It does NOT recover the worse case — every configured output disabled
-- from the very first modeset — because Hyprland then falls back to its own
-- internal synthetic "FALLBACK" pseudo-monitor, and its renderer never bootstraps
-- a real one after that; a later hl.monitor(disabled=false) call is accepted (no
-- error) but never reaches the hardware. No in-Lua API exists to detect
-- "connected but disabled" ahead of that point either (hl.get_monitors() only
-- reports currently-ENABLED outputs, and monitor.added never fires for a
-- connector that starts out disabled=true) — re-declaring disabled=false for a
-- name that isn't connected is a harmless no-op, so this blind retry is still
-- worth keeping for the case it does cover.
--
-- The worse case IS covered now, just not from here: `w-monitor sanity` re-enables
-- one connected output if every one of them would start disabled, and it runs
-- BEFORE this file is parsed — from /etc/xdg/uwsm/env-hyprland (graphical-session-
-- pre) for the session, from greetd's ExecStartPre for the greeter. Outside the
-- compositor it can read /sys/class/drm, which is the piece no in-Lua API offers.
-- So by the time execution reaches this net, "every output disabled" should already
-- be impossible; the net stays as the second line for the case it always handled.
local configured_names = {}
if type(mons) == "table" and type(mons.outputs) == "table" then
  for _, m in ipairs(mons.outputs) do
    if type(m) == "table" and type(m.output) == "string" and m.output ~= "" then
      table.insert(configured_names, m.output)
      if m.disabled then
        hl.monitor({ output = m.output, disabled = true })
      else
        hl.monitor({ output = m.output, mode = m.mode or "preferred",
                     position = m.position or "auto", scale = m.scale or "auto",
                     transform = m.transform or 0 })
      end
    end
  end
end

-- ── Options ──────────────────────────────────────────────────────────────────
hl.config({
  misc = {
    background_color = colors.bg,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    -- Session is supervised by systemd (uwsm), not the start-hyprland watchdog,
    -- so silence Hyprland's "launched without start-hyprland" warning.
    disable_watchdog_warning = true,
    -- No auto "Hyprland was updated to X" popup grabbing focus on login after
    -- every version bump — W is curated and updates are driven deliberately.
    disable_hyprland_guiutils_check = true,
  },

  input = {
    kb_layout = kbd.layout,
    kb_variant = kbd.variant,
    kb_options = kbd.options,
    repeat_rate = pick(kbd.repeat_rate, 25),
    repeat_delay = pick(kbd.repeat_delay, 600),
    numlock_by_default = pick(kbd.numlock, false),
    follow_mouse = 1,
    -- Global pointer keys: libinput applies them to EVERY pointer device, so they
    -- are the mouse's settings — the touchpad's own speed/accel are overridden
    -- per-device below (input.touchpad has no sensitivity key of its own).
    sensitivity = pick(ptr_mouse.sensitivity, 0.0),
    accel_profile = pick(ptr_mouse.accel_profile, "adaptive"),
    natural_scroll = pick(ptr_mouse.natural_scroll, false),
    scroll_factor = pick(ptr_mouse.scroll_factor, 1.0),
    left_handed = pick(ptr_mouse.left_handed, false),
    touchpad = {
      natural_scroll = pick(ptr_pad.natural_scroll, true),
      scroll_factor = pick(ptr_pad.scroll_factor, 1.0),
      disable_while_typing = pick(ptr_pad.disable_while_typing, true),
      tap_to_click = pick(ptr_pad.tap_to_click, true),
      tap_button_map = pick(ptr_pad.tap_button_map, "lrm"),
      clickfinger_behavior = pick(ptr_pad.clickfinger_behavior, false),
      middle_button_emulation = pick(ptr_pad.middle_button_emulation, false),
      tap_and_drag = pick(ptr_pad.tap_and_drag, true),
      drag_lock = pick(ptr_pad.drag_lock, 0),
      drag_3fg = pick(ptr_pad.drag_3fg, 0),
    },
  },

  -- Workspace-swipe tuning. The swipe itself is declared as an hl.gesture() below
  -- (workspace_swipe/_fingers were removed from this category in 0.55).
  gestures = {
    workspace_swipe_distance = pick(ptr_gest.swipe_distance, 300),
    workspace_swipe_invert = pick(ptr_gest.swipe_invert, true),
    workspace_swipe_create_new = pick(ptr_gest.swipe_create_new, true),
  },

  -- Cursor idle-hiding: seconds of pointer inactivity before the cursor is hidden
  -- (0 = never). This is the session-wide system value from the pointer fragment;
  -- while a modal Quickshell popup holds the cursor lease, w_cursor_lease() below
  -- swaps in the shorter menu_timeout so the pointer gets out of the way of
  -- keyboard-first navigation (and any movement brings it right back).
  cursor = {
    inactive_timeout = pick(ptr_cur.system_timeout, 0.0),
  },

  general = {
    gaps_in = geo.gaps_in,
    gaps_out = geo.gaps_out,
    border_size = geo.border,
    col = {
      active_border = colors.border_active,
      inactive_border = colors.border_inactive,
    },
    layout = "dwindle",
  },

  decoration = {
    rounding = geo.rounding,
    -- Focus-driven window opacity (whole window incl. text/widgets) from the active
    -- theme's effects. Active = focused, inactive = unfocused, fullscreen kept
    -- opaque for video. Per-app exceptions: a window_rule with opacity "… override".
    active_opacity = fx.opacity_active,
    inactive_opacity = fx.opacity_inactive,
    fullscreen_opacity = fx.opacity_fullscreen,
    -- Blur applies behind translucent windows AND opted-in shell layers (see the
    -- layer rules below). Opaque windows (focused Ghostty) are unaffected.
    blur = {
      enabled = fx.blur_enabled,
      size = fx.blur_size,
      passes = fx.blur_passes,
      new_optimizations = true,
    },
    shadow = { enabled = false },
  },

  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },

  dwindle = { preserve_split = true },

  -- Window groups: the group outline reuses the window border colors, and the
  -- groupbar tabs render as themed pill plaques instead of Hyprland's default
  -- yellow-green underline. gradients=true fills each tab; indicator_height=0
  -- drops the underline line; gradient_round_only_edges=false rounds every tab
  -- fully. Tab height and corner radius are set independently by the theme
  -- (geo.tab_height / geo.tab_rounding). Pills are tinted with the theme's app-bg
  -- translucency and blurred so they frost like windows. keep_upper_gap=false
  -- removes the gap above the bar (it padded the inter-window gaps). Colors: inactive
  -- tab = bar/card surface, active = launcher selection accent.
  group = {
    col = {
      border_active = colors.group_border_active,
      border_inactive = colors.group_border_inactive,
    },
    groupbar = {
      enabled = true,
      gradients = true,
      indicator_height = 0,
      height = geo.tab_height,
      gaps_in = geo.tab_gap_in,
      gaps_out = geo.tab_gap,
      keep_upper_gap = false,
      gradient_rounding = geo.tab_rounding,
      gradient_rounding_power = 2.0,
      gradient_round_only_edges = false,
      blur = fx.blur_enabled,
      font_size = 11,
      text_color = colors.tab_active_fg,
      text_color_inactive = colors.tab_inactive_fg,
      col = {
        active = with_opacity(colors.tab_active_bg, fx.app_bg),
        inactive = with_opacity(colors.tab_inactive_bg, fx.app_bg),
      },
    },
  },
})

-- ── Pointer devices ──────────────────────────────────────────────────────────
-- Per-device touchpad rules. Speed (`sensitivity`), acceleration profile and the
-- on/off switch exist only per-device in Hyprland — the input.touchpad category has
-- no key for them — so `w-pointer detect` records the touchpad names it found via
-- `hyprctl devices` in the fragment and they are re-declared here on every config
-- run. An empty list (desktop, or a laptop before the first detect) simply means the
-- global input{} values above stay in charge; a name that is no longer connected is
-- a harmless no-op.
if type(ptr.devices) == "table" and type(ptr.devices.touchpads) == "table" then
  for _, name in ipairs(ptr.devices.touchpads) do
    if type(name) == "string" and name ~= "" then
      hl.device({
        name = name,
        enabled = pick(ptr_pad.enabled, true),
        sensitivity = pick(ptr_pad.sensitivity, 0.0),
        accel_profile = pick(ptr_pad.accel_profile, "adaptive"),
      })
    end
  end
end

-- Workspace swipe. Since 0.55 the finger count is part of the gesture declaration
-- (the old gestures:workspace_swipe_fingers is gone), so "off" is expressed by not
-- declaring the gesture at all — `hyprctl reload` re-runs this file from scratch,
-- which is why removing it here really removes it.
local swipe_fingers = pick(ptr_gest.workspace_fingers, 3)
if type(swipe_fingers) == "number" and swipe_fingers >= 2 then
  hl.gesture({ fingers = swipe_fingers, direction = "horizontal", action = "workspace" })
end

-- ── Cursor lease (modal Quickshell popups) ───────────────────────────────────
-- While one of the shell's modal popups (launcher / hub / clipboard / power menu /
-- assistant) is open, the cursor idle timeout is swapped from the session-wide
-- system_timeout to the shorter menu_timeout, so the pointer gets out of the way
-- of keyboard-first navigation (any mouse movement brings it right back — that's
-- native inactive_timeout behaviour).
--
-- The trigger is the shared Backdrop surface (`quickshell:overlay-scrim`): it is
-- mapped exactly while a modal-group popup is shown (map-on-demand, see
-- modules/overlay/Backdrop.qml), so layer.opened/layer.closed on its namespace IS
-- the lease. This makes the fail-safe structural rather than watchdog-driven: if
-- the shell dies mid-lease (crash / SIGKILL), the compositor unmaps its surfaces,
-- layer.closed fires and the system value is restored in the same frame — there is
-- no code path, and no timer window, in which the cursor stays hidden forever.
-- Suspending for a polkit prompt drops the scrim for the same reason it drops the
-- keyboard grab, and restoring it re-fires layer.opened.
--
-- The one gap events cannot cover: `hyprctl reload` while a popup is open rebuilds
-- this whole state (re-applying the system value), and the already-mapped scrim
-- fires no layer.opened afterwards. The shell covers it with a ~2s heartbeat eval
-- (core/Overlays.qml) while its popup is open.
local cursor_menu_t = pick(ptr_cur.menu_timeout, 0.1)
local cursor_system_t = pick(ptr_cur.system_timeout, 0.0)
local function cursor_apply(menu)
  hl.config({
    cursor = { inactive_timeout = menu and cursor_menu_t or cursor_system_t },
  })
end
hl.on("layer.opened", function(ls)
  if ls ~= nil and ls.namespace == "quickshell:overlay-scrim" then cursor_apply(true) end
end)
hl.on("layer.closed", function(ls)
  if ls ~= nil and ls.namespace == "quickshell:overlay-scrim" then cursor_apply(false) end
end)

-- ── Autostart ────────────────────────────────────────────────────────────────
-- Session is uwsm-managed: `uwsm finalize` signals readiness (Type=notify) so
-- graphical-session.target activates, then daemons launch as their own units in
-- app-graphical.slice via `uwsm app` for proper cgroups and clean shutdown.
-- hyprland.start fires once at compositor start (not on `hyprctl reload`), so this
-- is the exec-once equivalent and does not re-spawn on theme reloads.
hl.on("hyprland.start", function()
  -- Boot safety net: see configured_names' comment above for why this is a blind
  -- retry rather than a targeted one. Boot-time only (hyprland.start does not
  -- re-fire on reload/hotplug) — a monitor pulled mid-session is a separate,
  -- not-yet-covered concern.
  local any_configured_live = false
  for _, m in ipairs(hl.get_monitors()) do
    for _, name in ipairs(configured_names) do
      if m.name == name then any_configured_live = true end
    end
  end
  if not any_configured_live then
    for _, name in ipairs(configured_names) do
      hl.monitor({ output = name, disabled = false, mode = "preferred", position = "auto", scale = "auto" })
    end
  end

  hl.exec_cmd("uwsm finalize")
  -- Sync session env into the D-Bus activation environment so services started by
  -- D-Bus (e.g. the xdg-desktop-portal-hyprland share picker) inherit QT theming.
  hl.exec_cmd("dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME")
  -- hyprpaper itself is NOT exec'd here: hyprpaper.service is --global-enabled
  -- (mod_hyprland, PartOf=graphical-session.target) so systemd starts/stops/
  -- restarts it with the session for every account, not just the one active
  -- during apply. This only tells the (already-starting) daemon which image to
  -- show. Log (don't /dev/null) — a silent failure here once meant a stale
  -- wallpaper with zero trace anywhere: ~/.local/state/w-wallpaper-apply.log +
  -- the journal, same pattern as the w-style render below.
  hl.exec_cmd("w-wallpaper apply --wait 2>&1 | tee \"${XDG_STATE_HOME:-$HOME/.local/state}/w-wallpaper-apply.log\" | systemd-cat -t w-wallpaper-apply")
  -- W auth agent: registers as the polkit agent and renders the password prompt
  -- in the Quickshell shell (modules/auth/). Replaces hyprpolkitagent.
  hl.exec_cmd("systemctl --user start w-authd")
  -- Auto-mount removable drives (USB/SATA: NTFS/exFAT/APFS) on insert + notify;
  -- its SNI tray item is picked up by the running tray.
  hl.exec_cmd("uwsm app -- udiskie")
  -- NetworkManager tray applet. --indicator forces the SNI/StatusNotifier backend
  -- (+libappindicator) that Quickshell's tray reads; the default XEmbed tray is
  -- invisible under Wayland. Harmless no-op if the package isn't installed.
  hl.exec_cmd("uwsm app -- nm-applet --indicator")
  -- Bluetooth tray applet (blueman). Native StatusNotifier (no --indicator needed).
  hl.exec_cmd("uwsm app -- blueman-applet")
  -- Idle daemon (auto-lock + lock-before-sleep + DPMS) runs as the packaged
  -- hypridle.service (systemd --user unit, global-enabled by mod_power), not exec'd
  -- here. See w-power.md.
  -- Clipboard history: two `wl-paste --watch` daemons record the clipboard (text +
  -- images) into cliphist's db. They store via `w-cliphist-store`, a thin gate that
  -- reads clipboard.json live — it drops password-manager-flagged offers
  -- (CLIPBOARD_STATE=sensitive) and honours the manager on/off toggle. Browsed by the
  -- Quickshell Clipboard component ($mod+V). See quickshell-clipboard.md.
  hl.exec_cmd("uwsm app -- wl-paste --type text --watch w-cliphist-store")
  hl.exec_cmd("uwsm app -- wl-paste --type image --watch w-cliphist-store")
  -- Keep the LIVE clipboard alive after the source app closes. Wayland serves the
  -- selection from the owner client, so closing it would kill the selection (cliphist
  -- only records history). wl-clip-persist takes ownership on owner-loss. `regular` =
  -- the Ctrl+C/V clipboard (not the mouse PRIMARY selection).
  hl.exec_cmd("uwsm app -- wl-clip-persist --clipboard regular")
  -- UI shell: single Quickshell process (-c w = the W config). Hosts the launcher,
  -- bar, volume, power menu and notifications.
  hl.exec_cmd("uwsm app -- quickshell -c w")
  -- Session memory (w-session) is NOT started here, deliberately: this file is
  -- class `user` (seed-if-absent), so a line added to it would only ever reach
  -- accounts created afterwards — every existing machine would silently never
  -- get the feature. Its two units are global-enabled by mod_session and pulled
  -- in by graphical-session.target instead, the same arrangement hypridle and
  -- the night light use for the same reason. See w-session.md.
end)

-- ── Animations ───────────────────────────────────────────────────────────────
-- The `snap` curve and animation leaves are declared in animations.lua, rendered
-- from the active theme's motion.conf (`w-style apply motion`) and kept in sync
-- with Quickshell's motion.json. It is require()d at the top of this file.

-- ── Layer rules ──────────────────────────────────────────────────────────────
-- w-windowblind drives the theme crossfade: an overlay layer-surface (like
-- hyprlock) holding a freeze-frame that fades out to reveal the newly applied
-- theme. Layer-shell never touches the tiling layout, so windows don't jump.
hl.layer_rule({ match = { namespace = "^(w-windowblind)$" }, animation = "fade" })

-- Blur the translucent shell surfaces. ignore_alpha (from effects.conf) couples
-- blur to surface alpha: blur is skipped where alpha is below it, so it tracks
-- fades and stays out of fully-transparent backdrops / rounded-corner gaps (no
-- rectangular halo). At surface opacity 1.0 the opaque card simply hides the blur.
local function blur_layer(ns)
  hl.layer_rule({ match = { namespace = ns }, blur = true, ignore_alpha = fx.blur_ignore_alpha })
end
-- launcher / clipboard / powermenu / hub share ONE backdrop surface (quickshell:
-- overlay-scrim) that owns their scrim + blur, so switching between them never remaps
-- the blur (no unblur→blur flash). Their own translucent cards frost against it — so
-- these popup namespaces are NOT blur_layer'd individually (the scrim carries it).
blur_layer("^(quickshell:overlay-scrim)$")
blur_layer("^(quickshell:bar)$")
blur_layer("^(quickshell:traymenu)$")
blur_layer("^(quickshell:notifications)$")
blur_layer("^(quickshell:osd)$")
blur_layer("^(quickshell:volumecontrol)$")
blur_layer("^(quickshell:brightnesscontrol)$")
blur_layer("^(quickshell:calendar)$")
-- Auth prompt: frost ONLY under the card, NOT the whole screen. The surface carries a
-- low-alpha dim (the rest of the screen stays merely dimmed, per the design) plus the
-- denser card. A higher ignore_alpha than the shared 0.3 keeps the dim below the blur
-- threshold while the card — composited over that dim — clears it, so the blur hugs the
-- rounded card and nothing else. (auth dim default 0.45 < 0.6 < card-over-dim alpha.)
hl.layer_rule({ match = { namespace = "^(quickshell:auth)$" }, blur = true, ignore_alpha = 0.6 })

-- ── Window rules ─────────────────────────────────────────────────────────────
-- satty (screenshot annotation, opened by w-screenshot): float it above the tiled
-- windows, center it and size it to 70% of the monitor. Runtime class is
-- `com.gabm.satty` (matches the desktop file's StartupWMClass, per hyprctl).
hl.window_rule({
  match  = { class = "^(com\\.gabm\\.satty)$" },
  float  = true,
  size   = { "monitor_w * 0.7", "monitor_h * 0.7" },
  center = true,
})

-- ── Keybindings ──────────────────────────────────────────────────────────────
-- Binds are DATA. The W action catalog (hotkeys-catalog.lua, W-managed) maps stable
-- tokens → Hyprland dispatchers + default chords; the active profile (hotkeys.lua,
-- user-owned, rewritten by `w-hotkeys` and the W Hub) maps tokens → chords. catalog.apply
-- binds every action from the active map (falling back to catalog defaults), the
-- workspace/focus families, any user custom exec actions, and the fixed media/mouse binds.
-- `hyprctl reload` re-runs this file, so a profile switch (or a single rebind) applies live
-- — the hyprland.start autostart hook does NOT re-fire on reload, so nothing re-spawns.
local hkcat = fragment("hotkeys-catalog", nil)
if hkcat then
  hkcat.apply(fragment("hotkeys", nil))
else
  -- Baseline fallback: the catalog is missing (a fresh account before the first
  -- `w-style`/deploy). Bind just enough to operate + escape the session.
  local mod = "SUPER"
  hl.bind(mod .. " + Return",    hl.dsp.exec_cmd("w-term"))
  hl.bind(mod .. " + D",         hl.dsp.global("quickshell:launcher"))
  hl.bind(mod .. " + Space",     hl.dsp.global("quickshell:hub"))
  hl.bind(mod .. " + Q",         hl.dsp.window.close())
  hl.bind(mod .. " + SHIFT + M", hl.dsp.exit())
  for i = 1, 5 do hl.bind(mod .. " + " .. i, hl.dsp.focus({ workspace = i })) end
end
